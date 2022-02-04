defmodule BrodGroupSubscriberExample.KafkaOffsets do
  @moduledoc """
  Manage DETS table to keep track of Kafka offsets.

  This is a GenServer to manage the lifecycle of the file, closing it properly on shutdown.
  """
  use GenServer

  require Logger

  @default_tab_name :kafka_offsets

  @spec start_link(Keyword.t(), Keyword.t()) :: {:ok, pid()} | {:error, term()}
  def start_link(args, opts \\ []) do
    GenServer.start_link(__MODULE__, args, opts)
  end

  @impl true
  def init(args) do
    Logger.debug("init: #{inspect(args)}")

    Process.flag(:trap_exit, true)

    tab_name = args[:tab_name] || @default_tab_name
    file =
      case Keyword.fetch(args, :file) do
        {:ok, value} ->
          value
        :error ->
          "/tmp/#{tab_name}.DETS"
      end

    Logger.info("Opening DETS table #{tab_name} file #{file}")
    {:ok, tab} = :dets.open_file(tab_name, file: to_charlist(file))

    state = %{
      tab: tab
    }

    {:ok, state}
  end

  @impl true
  def terminate(reason, state) do
    tab = state.tab
    Logger.debug("Closing DETS table #{tab} #{reason}")
    :dets.close(tab)
  end

  # :dets.insert(tab, objects)

  # @spec get_offsets() :: {:ok, list()} | {:error, term()}
  # def get_offsets do
  #   get_offsets(__MODULE__)
  # end

  # @spec get_offsets(:dets.tab_name()) :: {:ok, list()} | {:error, term()}
  # def get_offsets(tab) do
  #   reduce_tab(:dets.match_object(tab, :_, 500), [])
  # end

  # def reduce_tab({:error, reason}, _acc), do: {:error, reason}

  # def reduce_tab(:"$end_of_table", acc), do: {:ok, Enum.reverse(acc)}

  # def reduce_tab({match, continuation}, acc) do
  #   reduce_tab(:dets.match_object(continuation), [match | acc])
  # end
end
