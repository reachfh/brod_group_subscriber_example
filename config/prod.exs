import Config

app_ext_name = String.replace(to_string(Mix.Project.config[:app]), "_", "-")
state_dir = "/var/lib/#{app_ext_name}"
data_dir = "#{state_dir}/data"
log_dir = "/var/log/#{app_ext_name}"
log_root = log_dir
config_dir = "/etc/#{app_ext_name}"
cache_dir = "/var/cache/#{app_ext_name}"

config :brod_group_subscriber_example,
  config_dir: config_dir,
  state_dir: state_dir,
  data_dir: data_dir,
  cache_dir: cache_dir,
  kafka_subscriber_config: %{
    # Client id of the brod client (mandatory)
    client: :client1,
    # Consumer group ID which should be unique per kafka cluster (mandatory)
    group_id: app_ext_name,
    # Predefined set of topic names to join the group (mandatory)
    topics: [
      "foo",
    ],
    # Data passed to `CbModule:init/2' when initializing subscriber.
    # Optional, default :undefined
    init_data: %{
      # Mapping from Kafka topic to Avro subject/schema
      subjects: %{
        # "log_request" => "com.cogini.RequestLog"
      },
      offsets_tab: :kafka_offsets
    },
    # Type of message handled by callback module, :message (default) or :message_set
    message_type: :message_set, # default is :message
    # Config for group coordinator (optional)
    group_config: [
      offset_commit_policy: :consumer_managed, # default :commit_to_kafka_v2
      # offset_commit_interval_seconds: 5, # default 5
      # partition_assignment_strategy: :callback_implemented, # default :roundrobin_v2
    ],
    # Config for partition consumer (optional)
    consumer_config: [
      begin_offset: :earliest, # default is :latest
      # offset_reset_policy: :reset_by_subscriber, # default
      offset_reset_policy: :reset_to_earliest,
      # The window size (number of messages) allowed to fetch-ahead
      prefetch_count: 1000, # default 10
      # The total number of bytes allowed to fetch-ahead.
      # prefetch_bytes: 1024000, # default 102400, 100 KB
      # brod_consumer is greedy, it only stops fetching more messages in
      # when number of unacked messages has exceeded prefetch_count AND
      # the unacked total volume has exceeded prefetch_bytes</li>

      #  Maximum bytes to fetch in a batch of messages.
      # max_bytes: 1048576, # default 1048576, 1 MB
      max_bytes: 131_072, # default 1MB
    ]
  }

config :brod,
  clients: [
    client1: [
      endpoints: [localhost: 9092], # non ssl
      # endpoints: [localhost: 9093], # ssl
      allow_topic_auto_creation: false, # for safety, default true
      # get_metadata_timeout_seconds: 5, # default 5
      # max_metadata_sock_retry: 2, # seems obsolete
      max_metadata_sock_retry: 5,
      # query_api_versions: false, # default true, set false for Kafka < 0.10
      # reconnect_cool_down_seconds: 1, # default 1
      restart_delay_seconds: 10, # default 5
      # ssl: [
      #   certfile: to_charlist("#{config_dir}/ssl/kafka/cert.pem"),
      #   keyfile: to_charlist("#{config_dir}/ssl/kafka/key.pem"),
      #   cacertfile: to_charlist("#{config_dir}/ssl/kafka/ca.cert.pem")
      # ],
      # Credentials for SASL/Plain authentication.
      # sasl: {:plain, "username", "password"}
      # connect_timeout: 5000, # default 5000
      # request_timeout: 240000, # default 240000
    ]
  ]

config :setup,
  home: '.',
  log_dir: log_dir,
  data_dir: state_dir

config :logger,
  backends: [:console],
  level: :info,
  utc_log: true

#   compile_time_purge_matching: [
#     [level_lower_than: :info]
#   ]

config :logger, :console,
  level: :info,
  # format: "$metadata[$level] $levelpad$message\n",
  # format: {BrodGroupSubscriberExample.LoggerFormatter, :format_journald},
  format: {BrodGroupSubscriberExample.LoggerFormatter, :format},
  # metadata: :all
  metadata: [:pid, :application, :module, :function, :line]
  # metadata: [:pid, :module, :function, :line]

# SASL progress reports are logged at info level

# Supervisor reports and crash reports are issued as error level log events,
# and are logged through the default handler started by Kernel.
#
# Progress reports are issued as info level log events, and since the default
# primary log level is notice, these are not logged by default. To enable
# printing of progress reports, set the primary log level to info.
#
# All SASL reports have a metadata field domain which is set to [otp,sasl].
# This field can be used by filters to stop or allow the log events.

# filter on domain
# logger:set_primary_config(level, info).
# logger:set_module_level(mymodule, info).

# domain - a list of domains for the logged message. For example,
# all Elixir reports default to `[:elixir]`.
# Erlang reports may start with `[:otp]` or `[:sasl]`

# https://github.com/elixir-lang/elixir/blob/master/lib/logger/lib/logger.ex#L521
# Erlang/OTP handlers must be listed under your own application:
#     config :my_app, :logger, [
#       {:handler, :name_of_the_handler, ACustomHandler, configuration = %{}}
#     ]
#
# And then explicitly attached in your `c:Application.start/2` callback:
#     :logger.add_handlers(:my_app)

# Erlang logger config for app
config :brod_group_subscriber_example, :logger,
  [
    {:handler, :crash_log, :logger_std_h, %{
        level: :error,
        filter_default: :stop,
        filters: [
          {:domain_filter, {&:logger_filters.domain/2, {:log, :equal, [:otp, :sasl]}}}
        ],
        config: %{
          file: :filename.join(log_root, 'crash.log'),
          max_no_bytes: 10_485_760,
          max_no_files: 10,
        },
      }
    },
    {:handler, :notice_log, :logger_std_h, %{
        level: :notice,
        config: %{
          file: :filename.join(log_root, 'notice.log'),
          max_no_bytes: 10_485_760,
          max_no_files: 10,
        },
        formatter: {:logger_formatter, %{
          time_offset: 0,
          # template: [:time, '[', :level, '] ', :msg, '\n']
          template: [
            :time, ' ', '[', :level, '] ', {:pid, [:pid, ' '], []},
            {:mfa, [:mfa, ' '], []}, {:file, [:file], []}, {:line, [':', :line, ' '], []}, :msg, '\n'
          ]
        }}
      }
    },
    {:handler, :error_log, :logger_std_h, %{
        level: :error,
        config: %{
          file: :filename.join(log_root, 'error.log'),
          max_no_bytes: 10_485_760,
          max_no_files: 10,
        },
        formatter: {:logger_formatter, %{
          time_offset: 0,
          # template: [:time, '[', :level, '] ', :msg, '\n']
          template: [
            :time, ' ', '[', :level, '] ', {:pid, [:pid, ' '], []},
            {:mfa, [:mfa, ' '], []}, {:file, [:file], []}, {:line, [':', :line, ' '], []}, :msg, '\n'
          ]
        }}
      }
    },
    {:handler, :info_log, :logger_std_h, %{
        level: :info,
        config: %{
          file: :filename.join(log_root, 'info.log'),
          max_no_bytes: 10_485_760,
          max_no_files: 10,
        },
        formatter: {:logger_formatter, %{
          time_offset: 0,
          # template: [:time, '[', :level, '] ', :msg, '\n']
          template: [
            :time, ' ', '[', :level, '] ', {:pid, [:pid, ' '], []},
            {:mfa, [:mfa, ' '], []}, {:file, [:file], []}, {:line, [':', :line, ' '], []}, :msg, '\n'
          ]
        }}
      }
    },
    {:handler, :debug_log, :logger_std_h, %{
        level: :debug,
        config: %{
          file: :filename.join(log_root, 'debug.log'),
          max_no_bytes: 10_485_760,
          max_no_files: 10,
        },
        formatter: {:logger_formatter, %{
          time_offset: 0,
          # template: [:time, '[', :level, '] ', :msg, '\n']
          template: [
            :time, ' ', '[', :level, '] ', {:pid, [:pid, ' '], []},
            {:mfa, [:mfa, ' '], []}, {:file, [:file], []}, {:line, [':', :line, ' '], []}, :msg, '\n'
          ]
        }}
      }
    }
  ]

# config :opentelemetry, :processors,
#   otel_batch_processor: %{
#     exporter: {:otel_exporter_stdout, []}
#   }

# https://hexdocs.pm/opentelemetry_exporter/1.0.0/readme.html
# Maybe OTEL_EXPORTER_OTLP_ENDPOINT=http://opentelemetry-collector:55680
config :opentelemetry, :processors,
  otel_batch_processor: %{
    exporter: {
      :opentelemetry_exporter,
      %{
        protocol: :grpc,
        endpoints: [
          # gRPC
          'http://localhost:4317'
          # HTTP
          # 'http://localhost:4318'
          # 'http://localhost:55681'
          # {:http, 'localhost', 4318, []}
        ]
        # headers: [{"x-honeycomb-dataset", "experiments"}]
      }
    }
  }
