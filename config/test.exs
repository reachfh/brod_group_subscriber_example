import Config

app_ext_name = String.replace(to_string(Mix.Project.config()[:app]), "_", "-")
state_dir = "state"
data_dir = "#{state_dir}/data"
log_dir = "logs"
log_root = log_dir
config_dir = "config"
cache_dir = "cache"

config :brod_group_subscriber_example,
  config_dir: config_dir,
  state_dir: state_dir,
  data_dir: data_dir,
  cache_dir: cache_dir

config :setup,
  home: '.',
  log_dir: log_dir,
  data_dir: state_dir

config :logger,
  level: :warn

config :logger, :console,
  # format: "[$level] $message\n"
  format: {BrodGroupSubscriberExample.LoggerFormatter, :format},
  metadata: [:pid, :module, :function, :line]

# https://opentelemetry.io/docs/reference/specification/resource/semantic_conventions/
config :opentelemetry, :resource, [
  # In production service.name is set based on OS env vars from Erlang release
  service: [
    name: Mix.Project.config()[:app],
    version: Mix.Project.config()[:version]
  ]
]
