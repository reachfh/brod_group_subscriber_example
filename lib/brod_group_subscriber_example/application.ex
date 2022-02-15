defmodule BrodGroupSubscriberExample.Application do
  @moduledoc false

  @app Mix.Project.config()[:app]

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

    schema_dir = Path.join(to_string(:code.priv_dir(@app)), "avro_schema")
    aliases = Application.get_env(@app, :kafka_subject_aliases, %{})

    kafka_subscriber_config = Application.get_env(@app, :kafka_subscriber_config)
    offsets_tab = kafka_subscriber_config[:init_data][:offsets_tab]
    offsets_path = Path.join(state_dir, "#{offsets_tab}.DETS")

    Logger.info("kafka_subscriber_config: #{inspect(kafka_subscriber_config)}")

    children = [
      {AvroSchema, [cache_dir: cache_dir]},
      {BrodGroupSubscriberExample.AvroSchemaLoader, [schema_dir: schema_dir, aliases: aliases]},
      {BrodGroupSubscriberExample.KafkaOffsets, [tab_name: offsets_tab, file: offsets_path]},
      {BrodGroupSubscriberExample.Subscriber, [subscriber_config: kafka_subscriber_config]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: BrodGroupSubscriberExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # @impl true
  # def stop(_state) do
  #   case KafkaOffsets.close() do
  #     {:error, reason} ->
  #       Logger.error("Error closing offsets table #{inspect(reason)}")
  #       :ok
  #
  #     :ok ->
  #       :ok
  #   end
  # end
end
