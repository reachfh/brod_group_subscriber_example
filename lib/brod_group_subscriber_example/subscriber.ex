defmodule BrodGroupSubscriberExample.Subscriber do
  @moduledoc """
  Kafka consumer group subscriber example.

  """
  # https://github.com/klarna/brod/blob/master/src/brod_group_subscriber_v2.erl
  @behaviour :brod_group_subscriber_v2

  @offsets_tab :kafka_offsets

  require Logger
  # alias PrometheusExometer.Metrics

  require Record

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  @type cb_state() :: term()

  # use Retry

  @impl :brod_group_subscriber_v2
  def init(init_info, args) do
    Logger.info("init: #{inspect(init_info)} #{inspect(args)}")

    state = %{
      # Mapping from Kafka topic to Avro subject/schema
      subjects: args[:subjects] || %{},

      # Cache of decoders by Avro schema reference
      decoders: %{},
      init_info: init_info
    }

    {:ok, state}
  end

  # Callback when message_type = message_set
  # This processes a batch of messages at a time
  @impl :brod_group_subscriber_v2
  def handle_message(kafka_message_set(messages: messages, high_wm_offset: high_wm_offset), state) do
    %{topic: topic, partition: partition} = state.init_info

    Logger.debug("Processing message_set #{topic} #{partition} #{high_wm_offset}")
    # Metrics.inc([:records], [topic: topic], length(messages))

    # Convert list of Kafka Avro messages into list of JSON encoded Elasticsearch bulk records
    # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html
    {data, state} =
      Enum.reduce(messages, {[], state}, fn message, {acc, state} ->
        kafka_message(value: value) = message

        # Logger.debug("Processing message topic #{topic} key #{key} ts #{ts} offset #{offset}")

        subject = state[:subjects][topic]

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

            # {:error, :unknown_tag} ->
            #   Metrics.inc([:records, :error], topic: topic)
            #   {:ok, encoded} = encode_error(message, "unknown_tag", es_config)
            #   {[encoded | acc], state}
        end
      end)

    lag = get_lag(List.last(messages))
    Logger.debug("lag: #{lag}")
    # Metrics.inc([:lag], [topic: topic], lag)

    for record <- data do
      Logger.info("record: #{inspect(record)}")
    end

    Logger.debug("Saving offset #{inspect(topic)} #{inspect(partition)} #{inspect(high_wm_offset)}")
    :dets.insert(@offsets_tab, {{topic, partition}, to_integer(high_wm_offset)})

    {:ok, :ack, state}
  end


  # Get Avro decoder and cache in state
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

  defp get_lag(message) do
    kafka_message(ts: last_ts) = message
    {:ok, last_datetime} = DateTime.from_unix(last_ts, :microsecond)
    last_datetime = DateTime.truncate(last_datetime, :second)
    {:ok, now_datetime} = DateTime.now("Etc/UTC")
    DateTime.diff(now_datetime, last_datetime)
  end

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
