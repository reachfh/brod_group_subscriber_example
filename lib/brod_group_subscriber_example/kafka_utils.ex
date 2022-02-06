defmodule BrodGroupSubscriberExample.KafkaUtils do
  @moduledoc "Utility functions for dealing with Kafka"

  @default_client :client1

  @type endpoint() :: {host :: atom(), port :: non_neg_integer()}

  def connection, do: connection(@default_client)
  @spec connection(atom) :: {list({charlist, non_neg_integer}), Keyword.t()}
  def connection(client) do
    clients = Application.get_env(:brod, :clients)
    config = clients[client]

    endpoints = config[:endpoints] || [{'localhost', 9092}]

    sock_opts =
      case Keyword.fetch(config, :ssl) do
        {:ok, ssl_opts} ->
          [ssl: ssl_opts]

        :error ->
          []
      end

    {endpoints, sock_opts}
  end

  @spec resolve_offsets(binary(), :earliest | :latest, atom()) :: list({non_neg_integer(), integer()})
  def resolve_offsets(topic, type, client) do
    {endpoints, sock_opts} = connection(client)

    {:ok, partitions_count} = :brod.get_partitions_count(client, topic)

    for i <- Range.new(0, partitions_count - 1),
        {:ok, offset} = :brod.resolve_offset(endpoints, topic, i, type, sock_opts) do
      {i, offset}
    end
  end

  @spec list_all_groups(atom()) :: list({endpoint(), list({:brod_cg, name :: binary(), type :: binary()})})
  def list_all_groups(client) do
    {endpoints, sock_opts} = connection(client)

    for {endpoint, groups} <- :brod.list_all_groups(endpoints, sock_opts),
        groups != [],
        do: {endpoint, groups}
  end

  @spec list_all_topics(atom()) :: list(binary())
  def list_all_topics(client) do
    {:ok, metadata} = :brod_client.get_metadata(client, :all)
    for %{name: name} <- metadata[:topics], do: name
  end

  # @spec fetch_committed_offsets(binary(), binary(), atom()) :: {non_neg_integer(), non_neg_integer()}
  def fetch_committed_offsets(topic, consumer_group, client) do
    {endpoints, sock_opts} = connection(client)
    {:ok, response} = :brod.fetch_committed_offsets(endpoints, sock_opts, consumer_group)

    for r <- response,
        r[:topic] == topic,
        pr <- r[:partition_responses],
        do: {pr[:partition], pr[:offset]}
  end

  @spec lag(binary(), binary(), atom()) :: list({non_neg_integer(), integer()})
  def lag(topic, consumer_group, client) do
    offsets = resolve_offsets(topic, :latest, client)
    comitted_offsets = fetch_committed_offsets(topic, consumer_group, client)

    for {{part, current}, {_part2, committed}} <- Enum.zip(offsets, comitted_offsets) do
      {part, current - committed}
    end
  end

  @spec lag_total(binary(), binary(), atom()) :: non_neg_integer()
  def lag_total(topic, consumer_group, client) do
    # Enum.reduce(lag(topic, consumer_group, client), 0, fn {_part, recs}, acc ->
    #   acc + recs
    # end)
    for {_part, recs} <- lag(topic, consumer_group, client), reduce: 0 do
      acc -> acc + recs
    end
  end

  @spec buf(binary(), binary(), atom()) :: list({non_neg_integer(), integer()})
  def buf(topic, consumer_group, client) do
    offsets = resolve_offsets(topic, :earliest, client)
    comitted_offsets = fetch_committed_offsets(topic, consumer_group, client)

    for {{part, current}, {_part2, committed}} <- Enum.zip(offsets, comitted_offsets) do
      {part, committed - current}
    end
  end

  def buf_total(topic, consumer_group, client) do
    Enum.reduce(lag(topic, consumer_group, client), 0, fn {_part, recs}, acc ->
      acc + recs
    end)
  end

  @spec cap(binary(), atom()) :: list({non_neg_integer(), integer()})
  def cap(topic, client) do
    earliest_offsets = resolve_offsets(topic, :earliest, client)
    latest_offsets = resolve_offsets(topic, :latest, client)

    for {{part, earliest}, {_part2, latest}} <- Enum.zip(earliest_offsets, latest_offsets) do
      {part, latest - earliest}
    end
  end

  def cap_total(topic, consumer_group, client) do
    # Enum.reduce(lag(topic, consumer_group, client), 0, fn {_part, recs}, acc ->
    #   acc + recs
    # end)
    for {_part, recs} <- lag(topic, consumer_group, client), reduce: 0 do
      acc -> acc + recs
    end
  end
end
