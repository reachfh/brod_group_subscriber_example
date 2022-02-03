defmodule BrodGroupSubscriberExample.Application do
  @moduledoc false

  @app Mix.Project.config[:app]

  @kafka_offsets_tab :kafka_offsets
  @default_kafka_offsets_file "kafka_offsets.DETS"

  use Application

  require Logger

  @impl true
  def start(_type, _args) do
    :ok = :logger.add_handlers(@app)

    # conf_dir = to_string(Application.get_env(@app, :conf_dir, "config"))

    state_dir = Application.get_env(@app, :state_dir)
    state_data_dir = Path.join(state_dir, "data")
    :ok = File.mkdir_p(state_data_dir)

    cache_dir = Application.get_env(@app, :cache_dir, "/tmp")
    :ok = File.mkdir_p(cache_dir)

    # schema_dir = Path.join(to_string(:code.priv_dir(@app)), "avro_schema")

    kafka_offsets_file = Application.get_env(@app, :kafka_offsets_file, @default_kafka_offsets_file)
    kafka_offsets_path = to_charlist(Path.join(state_dir, kafka_offsets_file))
    Logger.info("Opening Kafka offsets file: #{kafka_offsets_path}")
    {:ok, @kafka_offsets_tab} = :dets.open_file(@kafka_offsets_tab, file: kafka_offsets_path)
    Logger.debug("Kafka offsets: #{inspect(get_kafka_offsets(), limit: :infinity)}")

    subjects = Application.get_env(@app, :kafka_topic_subjects, %{})
    # aliases = Application.get_env(@app, :kafka_subject_aliases, %{})

    consumer_config = Application.get_env(@app, :kafka_consumer)

    init_data = %{
      subjects: subjects,
    }
    children = [
      {AvroSchema, [cache_dir: cache_dir]},
      # {BrodGroupSubscriberExample.AvroSchemaLoader, [schema_dir: schema_dir, aliases: aliases]},
      brod_group_subscriber_v2(consumer_config, BrodGroupSubscriberExample.Subscriber, init_data)
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BrodGroupSubscriberExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def stop(_state) do
    case :dets.close(@kafka_offsets_tab) do
      {:error, message} ->
        Logger.error("Error closing DETS table #{@kafka_offsets_tab}: #{inspect(message)}")
        :ok

      :ok ->
        :ok
    end
  end

  @spec brod_group_subscriber_v2(Keyword.t(), module(), term()) :: map()
  defp brod_group_subscriber_v2(config, cb_module, init_data) do
    subscriber_config = %{
      client: config[:client_id] || :client1,
      group_id: config[:group_id],
      topics: config[:topics],
      group_config: config[:group_config],
      consumer_config: config[:consumer_config],
      message_type: config[:message_type] || :message,
      cb_module: cb_module,
      init_data: init_data
    }

    %{
      id: :brod_group_subscriber,
      start: {:brod_group_subscriber_v2, :start_link, [subscriber_config]}
    }
  end

  def get_kafka_offsets do
    loop_offsets({@kafka_offsets_tab, :_, 500})
  end

  defp loop_offsets(:"$end_of_table"), do: []

  defp loop_offsets({match, continuation}) do
    [match | loop_offsets(:dets.match_object(continuation))]
  end

  defp loop_offsets({tid, pat, limit}) do
    :lists.append(loop_offsets(:dets.match_object(tid, pat, limit)))
  end
end
