defmodule BrodGroupSubscriberExample.Subscriber do
  @moduledoc """
  Kafka consumer group subscriber example.

  """
  # https://github.com/kafka2beam/brod/blob/master/src/brod_group_subscriber_v2.erl
  @behaviour :brod_group_subscriber_v2

  require Logger

  require Record

  alias BrodGroupSubscriberExample.Telemetry

  Record.defrecord(
    :kafka_message,
    Record.extract(:kafka_message, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :kafka_message_set,
    Record.extract(:kafka_message_set, from_lib: "brod/include/brod.hrl")
  )

  Record.defrecord(
    :brod_produce_reply,
    Record.extract(:brod_produce_reply, from_lib: "brod/include/brod.hrl")
  )

  # use Retry

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

    offsets_tab = init_data[:offsets_tab]

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

    Logger.debug("Saving offset #{inspect(topic)} #{partition} #{high_wm_offset}")
    :ok = :dets.insert(offsets_tab, {{topic, partition}, to_integer(high_wm_offset)})

    {:ok, :ack, state}
  end

  def handle_message(topic, partition, message, state) do
    kafka_message(offset: offset, key: key, value: value) = message

    metadata = %{
      topic: topic,
      partition: partition,
      offset: offset,
      key: key,
      value: value,
    }

    start_time = Telemetry.start(:handle_message, metadata)

    Logger.info("#{inspect(topic)} #{partition} #{offset} #{inspect(key)} #{inspect(value)}")

    %{subjects: subjects, dead_letter_queues: dlq, offsets_tab: offsets_tab, client: client} =
      state.init_data

    # Get Avro subject/schema for topic
    subject = subjects[topic]

    case AvroSchema.untag(value) do
      {:ok, {{:confluent, regid}, bin}} ->
        {decoder, state} = get_decoder(regid, state)
        {:ok, record} = AvroSchema.decode(bin, decoder)

        Logger.info("record: #{inspect(record)}")

        Logger.debug("Saving offset #{inspect(topic)} #{partition} #{offset}")
        :ok = :dets.insert(offsets_tab, {{topic, partition}, to_integer(offset)})

        Telemetry.stop(:handle_message, start_time, metadata, %{tag: :confluent})

        {:ok, :ack, state}

      {:ok, {{:avro, fp}, bin}} ->
        # fp_hex = Base.encode16(fp, case: :lower)
        # Logger.debug("Message tag Avro #{subject} #{fp_hex}")
        {decoder, state} = get_decoder({subject, fp}, state)
        {:ok, record} = AvroSchema.decode(bin, decoder)
        Logger.info("record: #{inspect(record)}")

        Logger.debug("Saving offset #{inspect(topic)} #{partition} #{offset}")
        :ok = :dets.insert(offsets_tab, {{topic, partition}, to_integer(offset)})

        Telemetry.stop(:handle_message, start_time, metadata, %{tag: :avro})

        {:ok, :ack, state}

      {:error, :unknown_tag} ->
        Logger.error(
          "unknown_tag: #{inspect(topic)} #{partition} #{offset} #{inspect(key)} #{inspect(value)}"
        )

        {:ok, offset} = :brod.produce_sync_offset(client, dlq[topic], :random, key, value)
        Logger.debug(fn -> "Produced #{key} to #{topic} offset #{offset}" end)

        Telemetry.stop(:handle_message, start_time, metadata, %{tag: :none})

        {:ok, :ack, state}
    end
  end

  # def handle_info(brod_produce_reply(call_ref: call_ref, result: result), state) do
  #   Logger.info("#{inspect(call_ref)} #{inspect(result)}")
  #   {:noreply, state}
  # end

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

  defp to_integer(value) when is_integer(value), do: value
  defp to_integer(value) when is_binary(value), do: String.to_integer(value)
end
