defmodule BrodGroupSubscriberExample.SubscriberBase do
  @callback child_spec(Keyword.t()) :: map()
  @callback init(map(), map()) :: {:ok, map()}
  @callback handle_message(tuple(), map()) :: {:ok, :ack, map()} | {:ok, :commit, map()} | {:ok, map()}
  @callback process_message(map(), map()) :: {:ok, map()} | {:ok, :ack, map()} | {:error, term(), map()}


  @optional_callbacks child_spec: 1, init: 2, handle_message: 2

  require Logger

  require Record

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts] do
      alias BrodGroupSubscriberExample.SubscriberBase

      @behaviour SubscriberBase

      require Logger
      require OpenTelemetry.Tracer, as: Tracer

      require Record
      Record.defrecord(
        :kafka_message,
        Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
      )

      Record.defrecord(
        :kafka_message_set,
        Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
      )

      @doc "Start under Supervisor"
      def child_spec(config) do
        id = config[:id] || __MODULE__
        subscriber_config = config[:subscriber_config] |> Map.put(:cb_module, __MODULE__)

        %{
          id: id,
          start: {:brod_group_subscriber_v2, :start_link, [subscriber_config]}
        }
      end

      @doc "Initialize subscriber"
      # @impl :brod_group_subscriber_v2
      def init(init_info, init_data) do
        Logger.debug("init: init_info: #{inspect(init_info)}, init_data: #{inspect(init_data)}")

        state = Map.put(init_info, :init_data, init_data)

        {:ok, state}
      end

      @dialyzer {:nowarn_function, [handle_message: 2]}

      # @impl :brod_group_subscriber_v2
      def handle_message(message, state) do
        %{partition: partition, topic: topic} = state
        kafka_message(offset: offset, key: key, value: value, ts: ts, headers: headers) = message
        %{dead_letter_queues: dead_letter_queues, client: client} = state.init_data
        Logger.debug("#{inspect(message)} #{inspect(state)}")

        ctx = :otel_propagator_text_map.extract(headers)
        Logger.debug("trace context from kafka headers: #{inspect(ctx)}")

        lag = SubscriberBase.get_lag(message)
        attributes = [
          offset: offset, ts: ts, lag: lag,
        ] ++ SubscriberBase.messaging_attributes_process(message, state)

        Tracer.with_span "#{topic} process", %{kind: :consumer, attributes: attributes} do
          Logger.debug("topic #{topic} part #{partition} #{inspect(message)}")

          message = %{offset: offset, key: key, value: value, ts: ts, headers: headers}

          case process_message(message, state) do
            {:ok, state} ->
              {:ok, :ack, state}

            {:error, reason, state} ->
              Logger.error("#{inspect(reason)}")
              Tracer.set_status({:error, reason})

              dlq_topic = dead_letter_queues[topic]

              send_attributes = SubscriberBase.messaging_attributes_send(dlq_topic, key, value)
              Tracer.with_span "#{dlq_topic} send", %{kind: :producer, attributes: send_attributes} do

                # TODO: set header
                produce_headers = :otel_propagator_text_map.inject([])
                Logger.debug("produce_headers: #{inspect(produce_headers)}")

                {:ok, offset} = :brod.produce_sync_offset(client, dlq_topic, :random, key, value)

                Tracer.set_attribute("offset", offset)

                Logger.debug("Produced key #{inspect(key)} to topic #{dlq_topic} offset #{offset}")

                Tracer.set_status({:ok, ""})

                {:ok, :ack, state}
              end
          end
        end
      end

      def process_message(message, state) do
        Log.info("#{inspect(message)} #{inspect(state)}")
        {:ok, state}
      end

      defoverridable SubscriberBase

    end
  end

  # https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/messaging.md
  def messaging_attributes_process(message, state) do
    kafka_message(key: key, value: value) = message
    %{partition: partition, topic: topic, group_id: group_id} = state

    [
      # {"service.name", @app},
      {"messaging.operation", "process"}, # or maybe "receive"
      {"messaging.system", "kafka"},
      {"messaging.destination_kind", "topic"},
      {"messaging.kafka.message_key", key},
      {"messaging.message_payload_size_bytes", byte_size(value)},
      {"messaging.destination", topic},
      {"messaging.kafka.partition", partition},
      {"messaging.kafka.consumer_group", group_id},
    ]
  end

  def messaging_attributes_send(topic, key, value) do
    [
      # {"service.name", @app},
      # {"peer.service", @app},
      {"messaging.system", "kafka"},
      {"messaging.destination_kind", "topic"},
      {"messaging.destination", topic},
      {"messaging.kafka.message_key", key},
      {"messaging.message_payload_size_bytes", byte_size(value)},
      {"messaging.operation", "send"},
    ]
  end

  @doc "Calcuate age of message in seconds"
  @spec get_lag(non_neg_integer() | tuple()) :: non_neg_integer()
  def get_lag(kafka_message(ts: ts)) do
    get_lag(ts)
  end

  def get_lag(ts) when is_integer(ts) do
    {:ok, datetime} = DateTime.from_unix(ts, :millisecond)
    datetime = DateTime.truncate(datetime, :second)
    {:ok, now_datetime} = DateTime.now("Etc/UTC")
    DateTime.diff(now_datetime, datetime)
  end

  # Get Avro decoder and cache in state
  # @spec get_decoder(binary(), map()) ::
  def get_decoder(reg, state) do
    decoders = state[:decoders] || %{}

    case Map.fetch(decoders, reg) do
      {:ok, decoder} ->
        {decoder, state}

      :error ->
        {:ok, schema} = AvroSchema.get_schema(reg)
        {:ok, decoder} = AvroSchema.make_decoder(schema)
        {decoder, %{state | decoders: Map.put(decoders, reg, decoder)}}
    end
  end

  # TODO: this is not friendly to tracing
  @spec backoff(non_neg_integer(), map()) :: non_neg_integer()
  def backoff(took, %{backoff_threshold: backoff_threshold} = config) do
    backoff_multiple = config[:backoff_multiple] || 10
    if took > backoff_threshold do
      backoff = backoff_multiple * took
      Logger.warning("Backoff #{backoff}")
      Process.sleep(backoff)
      backoff
    else
      0
    end
  end

  def backoff(_took, _config) do
    0
  end

end
