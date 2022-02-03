defmodule BrodGroupSubscriberExample.KafkaOffsets do
  @moduledoc """
  Manage DETS table to keep track of Kafka offsets.
  """
  require Logger

  @default_offsets_file "kafka_offsets.DETS"

  @doc "Open offsets file"
  @spec open_file(Keyword.t()) :: {:ok, :dets.tab_name()} | {:error, term()}
  def open_file(args) do
    state_dir = args[:state_dir]
    file = args[:file] || @default_offsets_file
    tab = args[:tab] || __MODULE__
    path = to_charlist(Path.join(state_dir, file))

    :dets.open_file(tab, file: path)
  end

  def insert(objects) do
    insert(__MODULE__, objects)
  end

  def insert(tab, objects) do
    :dets.insert(tab, objects)
  end

  @doc "Open offsets table"
  @spec close(:dets.tab_name()) :: :ok | {:error, term()}
  def close(tab) do
    :dets.close(tab)
  end

  def close do
    close(__MODULE__)
  end

  @spec get_offsets() :: {:ok, list()} | {:error, term()}
  def get_offsets do
    get_offsets(__MODULE__)
  end

  @spec get_offsets(:dets.tab_name()) :: {:ok, list()} | {:error, term()}
  def get_offsets(tab) do
    reduce_tab(:dets.match_object(tab, :_, 500), [])
  end

  def reduce_tab({:error, reason}, _acc), do: {:error, reason}

  def reduce_tab(:"$end_of_table", acc), do: {:ok, Enum.reverse(acc)}

  def reduce_tab({match, continuation}, acc) do
    reduce_tab(:dets.match_object(continuation), [match | acc])
  end
end
