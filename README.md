# BrodGroupSubscriberExample

**TODO: Add description**

## Installation

If [available in Hex](https://hex.pm/docs/publish), the package can be installed
by adding `brod_group_subscriber_example` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:brod_group_subscriber_example, "~> 0.1.0"}
  ]
end
```

```shell
brew info kafka
brew services start kafka
```

Documentation can be generated with [ExDoc](https://github.com/elixir-lang/ex_doc)
and published on [HexDocs](https://hexdocs.pm). Once published, the docs can
be found at <https://hexdocs.pm/brod_group_subscriber_example>.

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
