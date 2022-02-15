defmodule BrodGroupSubscriberExample.MixProject do
  use Mix.Project

  @version "0.1.0"
  @app :brod_group_subscriber_example

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      erlc_options: erlc_options(),
      deps: deps(),
      default_release: :prod,
      releases: releases(),
      dialyzer: [
        # plt_add_deps: :project,
        # plt_add_apps: [:ssl, :mnesia, :compiler, :xmerl, :inets],
        # plt_add_deps: true,
        # flags: ["-Werror_handling", "-Wrace_conditions"],
        # flags: ["-Wunmatched_returns", :error_handling, :race_conditions, :underspecs],
        # ignore_warnings: "dialyzer.ignore-warnings"
      ],
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications:
        [
          :logger,
          :runtime_tools,
          :gproc,
          :tls_certificate_check,
          :hackney
        ] ++ extra_applications(Mix.env()),
      mod: {BrodGroupSubscriberExample.Application, []}
    ]
  end

  def extra_applications(:test), do: [:tools]
  def extra_applications(:dev), do: [:tools]
  def extra_applications(_), do: []

  defp erlc_options do
    includes = Path.wildcard(Path.join(Mix.Project.deps_path(), "*/include"))

    [
      :debug_info,
      :warnings_as_errors,
      :warn_export_all,
      :warn_export_vars,
      :warn_shadow_vars,
      :warn_obsolete_guard
    ] ++
      Enum.map(includes, fn path -> {:i, path} end)
  end

  defp releases do
    [
      prod: [
        version: @version,
        include_executables_for: [:unix]
        # applications: [:runtime_tools :permanent, :opentelemetry_exporter :load, :opentelemetry :temporary, @app :permanent]
        # Don't need to tar if we are just going to copy it
        # steps: [:assemble, :tar]
      ]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ace, "~> 0.19.0"},
      {:avro_schema, "~> 0.3.0"},
      {:brod, "~> 3.16"},
      {:confluent_schema_registry, "~> 0.1.0"},
      {:coverex, "~> 1.5", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.5", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.10", only: :test},
      {:exometer_core, "~> 1.6"},
      {:hackney, "~> 1.16"},
      {:jason, "~> 1.2"},
      {:mix_audit, "~> 1.0.0", only: [:dev, :test], runtime: false},
      {:observer_cli, "~> 1.6"},
      {:opentelemetry, "~> 1.0", override: true},
      {:opentelemetry_api, "~> 1.0", override: true},
      {:opentelemetry_exporter, "~> 1.0"},
      {:prometheus_exometer, "~> 0.2"},
      {:retry, "~> 0.13"},
      {:sobelow, "~> 0.11.0", only: [:dev, :test], runtime: false},
      {:telemetry, "~> 0.4.3", override: true},
      {:telemetry_metrics, "~> 0.6"},
      {:telemetry_poller, "~> 1.0"},
      {:timex, "~> 3.6"}
    ]
  end
end
