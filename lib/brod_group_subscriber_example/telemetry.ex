defmodule BrodGroupSubscriberExample.Telemetry do
  @moduledoc """
  Telemetry integration.

  Unless specified, all times are in `:native` units.

  Description of all events:
  """
  @app Mix.Project.config[:app]

  @doc false
  # emits a `start` telemetry event and returns the the start time
  def start(event, meta \\ %{}, extra_measurements \\ %{}) do
    start_time = System.monotonic_time()

    :telemetry.execute(
      [@app, event, :start],
      Map.merge(extra_measurements, %{system_time: System.system_time()}),
      meta
    )

    start_time
  end

  @doc false
  # Emits a stop event.
  def stop(event, start_time, meta \\ %{}, extra_measurements \\ %{}) do
    end_time = System.monotonic_time()
    measurements = Map.merge(extra_measurements, %{duration: end_time - start_time})

    :telemetry.execute(
      [@app, event, :stop],
      measurements,
      meta
    )
  end

  @doc false
  def exception(event, start_time, kind, reason, stack, meta \\ %{}, extra_measurements \\ %{}) do
    end_time = System.monotonic_time()
    measurements = Map.merge(extra_measurements, %{duration: end_time - start_time})

    meta =
      meta
      |> Map.put(:kind, kind)
      |> Map.put(:error, reason)
      |> Map.put(:stacktrace, stack)

    :telemetry.execute([@app, event, :exception], measurements, meta)
  end

  @doc false
  # Used for reporting generic events
  def event(event, measurements, meta) do
    :telemetry.execute([@app, event], measurements, meta)
  end
end
