import Config

app_ext_name = String.replace(to_string(Mix.Project.config[:app]), "_", "-")
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
  cache_dir: cache_dir,
  kafka_subscriber_config: %{
    # Client id of the brod client (mandatory)
    client: :client1,
    # Consumer group ID which should be unique per kafka cluster (mandatory)
    group_id: app_ext_name,
    # Predefined set of topic names to join the group (mandatory)
    topics: [
      "foo"
    ],
    # Data passed to `CbModule:init/2' when initializing subscriber.
    # Optional, default :undefined
    init_data: %{
      # Mapping from Kafka topic to Avro subject/schema
      subjects: %{
        # "log_request" => "com.cogini.RequestLog"
      },
      dead_letter_queues: %{
        "foo" => "foo-dlq"
      },
      offsets_tab: :kafka_offsets,
      client: :client1
    },
    # Type of message handled by callback module, :message (default) or :message_set
    # message_type: :message_set, # default :message
    message_type: :message,
    # Config for group coordinator (optional)
    group_config: [
      # offset_commit_policy: :consumer_managed, # default :commit_to_kafka_v2
      # offset_commit_interval_seconds: 5, # default 5
      # partition_assignment_strategy: :callback_implemented, # default :roundrobin_v2
    ],
    # Config for partition consumer (optional)
    consumer_config: [
      # begin_offset: :earliest, # default is :latest
      # offset_reset_policy: :reset_by_subscriber, # default
      # offset_reset_policy: :reset_to_earliest,
      # The window size (number of messages) allowed to fetch-ahead
      # prefetch_count: 1000, # default 10
      # The total number of bytes allowed to fetch-ahead.
      # prefetch_bytes: 1024000, # default 102400, 100 KB
      # brod_consumer is greedy, it only stops fetching more messages in
      # when number of unacked messages has exceeded prefetch_count AND
      # the unacked total volume has exceeded prefetch_bytes</li>

      #  Maximum bytes to fetch in a batch of messages.
      # max_bytes: 1048576, # default 1048576, 1 MB
      # max_bytes: 131_072, # default 1MB
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

      auto_start_producers: true,
      default_producer_config: [
        # See brod/src/brod_producer.erl
        # required_acks: -1,
        # ack_timeout: 10000,
        partition_buffer_limit: 512, # default is 256
        # partition_onwire_limit: 1,
        # max_batch_size: 10_485_760, # default is 1M
        # buffered messages again upon receiving a error from kafka
        # by default, brod_producer will try to retry 3 times before crashing
        # max_retries: 3,
        max_retries: 5,
        # By default, brod_producer will sleep for 0.5 second before trying to send
        # retry_backoff_ms: 500,
        # compression: :no_compression,
        # compression: :gzip,
        # min_compression_batch_size: 1024,
        # max_linger_ms: 0,
        # max_linger_count: 0,
      ]
    ]
  ]

config :setup,
  home: '.',
  log_dir: log_dir,
  data_dir: state_dir

config :logger,
  level: :debug

config :logger, :console,
  # level: :info,
  level: :debug,
  # format: "$metadata[$level] $levelpad$message\n",
  format: {BrodGroupSubscriberExample.LoggerFormatter, :format},
  # metadata: :all
  # metadata: [:pid, :application, :module, :function, :line]
  metadata: [:pid, :module, :function, :line]

# https://opentelemetry.io/docs/reference/specification/resource/semantic_conventions/
config :opentelemetry, :resource,
  [
    # In production service.name is set based on OS env vars from Erlang release
    service: [
      name: Mix.Project.config[:app],
      version: Mix.Project.config[:version]
    ]
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
