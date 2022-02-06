defmodule BrodGroupSubscriberExample.Subscriber do
  @moduledoc """
  Kafka consumer group subscriber example.

  """
  # https://github.com/kafka2beam/brod/blob/master/src/brod_group_subscriber_v2.erl
  @behaviour :brod_group_subscriber_v2

  @app Mix.Project.config[:app]

  require Logger

  require Record

  # alias BrodGroupSubscriberExample.Telemetry

  require OpenTelemetry.Tracer, as: Tracer

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  # Record.defrecord(
  #   :brod_produce_reply,
  #   Record.extract(:brod_produce_reply, from_lib: "brod/include/brod.hrl")
  # )

  # use Retry
  # result =
  #   retry with: linear_backoff(backoff, 2) |> Stream.take(max_tries) do
  #     Elastix.Bulk.post_raw(elastic_url, data, elastix_options)
  #   after
  #     result -> result
  #   else
  #     error ->
  #       Logger.debug("Error: #{inspect(error)}")
  #       error
  #   end

  @spec child_spec(Keyword.t()) :: map()
  def child_spec(config) do
    Logger.debug("child_spec: #{inspect(config)}")

    id = config[:id] || __MODULE__
    subscriber_config = config[:subscriber_config] |> Map.put(:cb_module, __MODULE__)

    %{
      id: id,
      start: {:brod_group_subscriber_v2, :start_link, [subscriber_config]}
    }
  end

  @doc "Initialize partition subscriber process."
  @impl :brod_group_subscriber_v2
  def init(init_info, init_data) do
    Logger.debug("init: init_info: #{inspect(init_info)}, init_data: #{inspect(init_data)}")

    state =
      init_info
      |> Map.put(:init_data, init_data)
      # Cache decoders by Avro schema reference
      |> Map.put(:decoders, %{})

    {:ok, state}
  end

  # The proto of handle_message specifies kafka_message, but we have kafka_message_set
  @dialyzer {:nowarn_function, handle_message: 2}

  # Callback when message_type = message_set
  # This processes a batch of messages at a time
  @impl :brod_group_subscriber_v2
  def handle_message(kafka_message_set(messages: messages, high_wm_offset: high_wm_offset), state) do
    %{topic: topic, partition: partition, init_data: init_data} = state

    Logger.debug("Processing message_set #{topic} #{partition} #{high_wm_offset}")
    :telemetry.execute([:record], %{count: length(messages)}, %{topic: topic, partition: partition})

    # Mapping from Kafka topic to Avro subject/schema
    subject = init_data[:subjects][topic]

    {data, state} =
      Enum.reduce(messages, {[], state}, fn message, {acc, state} ->
        kafka_message(value: value) = message

        # Logger.debug("Processing message topic #{topic} key #{key} ts #{ts} offset #{offset}")

        case AvroSchema.untag(value) do
          {:ok, {{:confluent, regid}, bin}} ->
            {decoder, state} = get_decoder(regid, state)
            {:ok, record} = AvroSchema.decode(bin, decoder)
            {[record | acc], state}

          {:ok, {{:avro, fp}, bin}} ->
            # fp_hex = Base.encode16(fp, case: :lower)
            # Logger.debug("Message tag Avro #{subject} #{fp_hex}")
            {decoder, state} = get_decoder({subject, fp}, state)
            {:ok, record} = AvroSchema.decode(bin, decoder)
            {[record | acc], state}

          {:error, :unknown_tag} ->
            :telemetry.execute([:record, :error], %{count: 1}, %{topic: topic, partition: partition})
            # {:ok, encoded} = encode_error(message, "unknown_tag", es_config)
            {[value | acc], state}
        end
      end)

    lag = get_lag(List.last(messages))
    Logger.debug("lag: #{lag}")
    :telemetry.execute([:lag], %{duration: lag}, %{topic: topic, partition: partition})

    for record <- data do
      Logger.info("record: #{inspect(record)}")
    end

    # offsets_tab = init_data[:offsets_tab]
    # Logger.debug("Saving offset #{inspect(topic)} #{partition} #{high_wm_offset}")
    # :ok = :dets.insert(offsets_tab, {{topic, partition}, to_integer(high_wm_offset)})

    {:ok, :ack, state}
  end

  # https://github.com/open-telemetry/opentelemetry-specification/blob/main/specification/trace/semantic_conventions/messaging.md

  def handle_message(message, state) do
    %{partition: partition, topic: topic} = state
    kafka_message(offset: offset, key: key, value: value, ts: ts, headers: headers) = message
    %{dead_letter_queues: dlq, client: client} = state.init_data
    Logger.debug("#{inspect(message)} #{inspect(state)}")

    ctx = :otel_propagator_text_map.extract(headers)
    Logger.debug("trace context from kafka headers: #{inspect(ctx)}")

    lag = get_lag(message)
    attributes = [
      offset: offset, ts: ts, lag: lag,
    ] ++ messaging_attributes_process(message, state)

    Tracer.with_span "#{topic} process", %{kind: :consumer, attributes: attributes} do
      Logger.debug("topic #{topic} part #{partition} #{inspect(message)}")

      dlq_topic = dlq[topic]
      Tracer.set_status({:error, ""})
      send_attributes = messaging_attributes_send(dlq_topic, key, value)
      Tracer.with_span "#{dlq_topic} send", %{kind: :producer, attributes: send_attributes} do

        # TODO: set header
        produce_headers = :otel_propagator_text_map.inject([])
        Logger.debug("produce_headers: #{inspect(produce_headers)}")
        {:ok, offset} = :brod.produce_sync_offset(client, dlq_topic, :random, key, value)

        Tracer.add_event(:produce_dlq, topic: topic, key: key, offset: offset)
        Tracer.set_attribute("offset", offset)

        Logger.debug("Produced key #{inspect(key)} to topic #{dlq_topic} offset #{offset}")

        Tracer.set_status({:ok, ""})
      end

      {:ok, :ack, state}
    end
  end

  def messaging_attributes_process(message, state) do
    kafka_message(key: key, value: value) = message
    %{partition: partition, topic: topic, group_id: group_id} = state
     [
      {"service.name", @app},
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
      {"service.name", @app},
      {"peer.service", @app},
      {"messaging.system", "kafka"},
      {"messaging.destination_kind", "topic"},
      {"messaging.destination", topic},
      {"messaging.kafka.message_key", key},
      {"messaging.message_payload_size_bytes", byte_size(value)},
      {"messaging.operation", "send"},
    ]
  end

  # def handle_message(message, state) do
  #   %{partition: partition, topic: topic} = state
  #
  #   kafka_message(offset: offset, key: key, value: value) = message
  #
  #   metadata = %{topic: topic, partition: partition}
  #   measurements = %{offset: offset, key: key, value: value}
  #   start_time = Telemetry.start(:handle_message, metadata, measurements)
  #   Telemetry.event(:lag, %{duration: get_lag(message)}, metadata)
  #
  #   Logger.info("topic #{topic} part #{partition} #{inspect(message)}")
  #
  #   # # TODO: maybe put info into kafka headers, e.g. original offset, trace id
  #   %{dead_letter_queues: dlq, client: client} = state.init_data
  #   dlq_topic = dlq[topic]
  #   {:ok, offset} = :brod.produce_sync_offset(client, dlq_topic, :random, key, value)
  #   Logger.debug("Produced key #{inspect(key)} to topic #{dlq_topic} offset #{offset}")
  #
  #   Telemetry.stop(:handle_message, start_time, metadata, measurements)
  #   {:ok, :ack, state}
  # end

  # def handle_message(message, state) do
  #   # kafka_protocol/include/kpro_public.hrl
  #   kafka_message(offset: offset, key: key, value: value) = message
  #   %{partition: partition, topic: topic} = state
  #
  #   metadata = %{topic: topic, partition: partition}
  #   measurements = %{offset: offset, key: key, value: value}
  #
  #   start_time = Telemetry.start(:handle_message, metadata, measurements)
  #
  #   Telemetry.event(:lag, %{duration: get_lag(message)}, metadata)
  #
  #   Logger.info("#{topic} part #{partition} offset #{offset} #{inspect(key)} #{inspect(value)}")
  #
  #   %{subjects: subjects, dead_letter_queues: dlq, client: client} = state.init_data
  #   # Get Avro subject/schema for topic
  #   subject = subjects[topic]
  #
  #   case AvroSchema.untag(value) do
  #     {:ok, {{:confluent, regid}, bin}} ->
  #       {decoder, state} = get_decoder(regid, state)
  #       {:ok, record} = AvroSchema.decode(bin, decoder)
  #
  #       Logger.debug("record: #{inspect(record)}")
  #
  #       Telemetry.stop(:handle_message, start_time, metadata, measurements)
  #       {:ok, :ack, state}
  #
  #     {:ok, {{:avro, fp}, bin}} ->
  #       {decoder, state} = get_decoder({subject, fp}, state)
  #       {:ok, record} = AvroSchema.decode(bin, decoder)
  #       Logger.info("record: #{inspect(record)}")
  #
  #       Telemetry.stop(:handle_message, start_time, metadata, measurements)
  #       {:ok, :ack, state}
  #
  #     {:error, :unknown_tag} ->
  #       Logger.error("unknown_tag: #{topic} part #{partition} offset #{offset} key #{inspect(key)} #{inspect(value)}")
  #
  #       # TODO: maybe put info into kafka headers, e.g. original offset, trace id
  #       dlq_topic = dlq[topic]
  #       {:ok, offset} = :brod.produce_sync_offset(client, dlq_topic, :random, key, value)
  #       Logger.debug("Produced key #{inspect(key)} to topic #{dlq_topic} offset #{offset}")
  #
  #       Telemetry.stop(:handle_message, start_time, metadata, measurements)
  #       {:ok, :ack, state}
  #   end
  # end

  # @doc "Handle ack from async produce"
  # def handle_info(brod_produce_reply(call_ref: call_ref, result: result), state) do
  #   Logger.info("#{inspect(call_ref)} #{inspect(result)}")
  #   {:noreply, state}
  # end

  # Get Avro decoder and cache in state
  # @spec get_decoder(binary(), map()) ::
  defp get_decoder(reg, %{decoders: decoders} = state) do
    case Map.fetch(decoders, reg) do
      {:ok, decoder} ->
        {decoder, state}

      :error ->
        {:ok, schema} = AvroSchema.get_schema(reg)
        {:ok, decoder} = AvroSchema.make_decoder(schema)
        {decoder, %{state | decoders: Map.put(decoders, reg, decoder)}}
    end
  end

  @impl :brod_group_subscriber_v2
  @spec get_committed_offset(term(), :brod.topic(), :brod.partition()) ::
          {:ok, :brod.offset() | :undefined}
  def get_committed_offset(init_data, topic, partition) do
    Logger.debug("init_data: #{inspect(init_data)}")

    offsets_tab = init_data.offsets_tab
    offsets_data = :dets.foldl(fn {key, value}, acc -> [{key, value} | acc] end, [], offsets_tab)
    Logger.debug("Kafka offsets: #{inspect(offsets_data, limit: :infinity)}")

    case :dets.lookup(offsets_tab, {topic, partition}) do
      [{_k, offset}] ->
        Logger.debug("Found offset for #{inspect(topic)} partition #{partition} offset #{offset}")

        {:ok, offset}

      _ ->
        :undefined
    end
  end

  @spec get_lag(non_neg_integer() | tuple()) :: non_neg_integer()
  defp get_lag(kafka_message(ts: ts)) do
    get_lag(ts)
  end

  defp get_lag(ts) when is_integer(ts) do
    {:ok, datetime} = DateTime.from_unix(ts, :millisecond)
    datetime = DateTime.truncate(datetime, :second)
    {:ok, now_datetime} = DateTime.now("Etc/UTC")
    DateTime.diff(now_datetime, datetime)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
