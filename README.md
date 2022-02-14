# brod_group_subscriber_example

## Installation

Kafka:

```shell
brew install kafka
brew services start zookeeper
brew services start kafka
```

## Generate a Kafka message from Elixir console:

```elixir
:brod.produce_sync_offset(:client1, "foo", :random, "the key", "the value")
```

## TODO

* Extract trace context from message kafka headers and use in dlc send
* Use link?
* service.name is wrong
  Set service.name in span?

      # {"service.name", @app},
      # {"peer.service", @app},

* Log time is wrong (very large)
* set_status is not working?

* Use retries for error handling
* Maybe sleep

```elixir
start_time = System.monotonic_time()
result = process_message(message, state)
processing_duration = System.monotonic_time() - start_time
```
