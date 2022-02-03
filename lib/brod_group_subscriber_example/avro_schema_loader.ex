defmodule BrodGroupSubscriberExample.AvroSchemaLoader do
  @moduledoc """
  Load schemas from files and preload cache with fingerprints.

  This is a GenServer because it needs to be started after the `AvroSchema`
  cache and run before the Kafka consumer.
  """
  use GenServer

  require Logger

  # GenServer callbacks

  @doc "Start the GenServer."
  @spec start_link(list, list) :: {:ok, pid} | {:error, any}
  def start_link(args, opts \\ []) do
    app =
      __MODULE__
      |> to_string()
      |> String.split(".")
      |> List.first()
      |> Macro.underscore()

    defaults = [
      name: __MODULE__,
      otp_app: app
    ]

    GenServer.start_link(__MODULE__, args, Keyword.merge(defaults, opts))
  end

  @doc "Stop the GenServer"
  @spec stop() :: :ok
  def stop do
    GenServer.call(__MODULE__, :stop)
  end

  @impl true
  def init(args) do
    Logger.info("init: #{inspect(args)}")

    schema_dir =
      args[:schema_dir] || Path.join(to_string(:code.priv_dir(args[:otp_app])), "avro_schema")

    aliases = args[:aliases] || %{}

    {:ok, schema_files} = AvroSchema.get_schema_files(schema_dir)

    for path <- schema_files do
      Logger.info("Reading Avro schema file #{path}")
      {:ok, _registered} = AvroSchema.cache_schema_file(path, aliases)
    end

    # for {key, _value} <- AvroSchema.dump() do
    #   Logger.debug("cache: #{inspect key}")
    # end

    state = %{}
    {:ok, state}
  end
end
