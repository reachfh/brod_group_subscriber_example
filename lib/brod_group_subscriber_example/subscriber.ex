defmodule BrodGroupSubscriberExample.Subscriber do
  @moduledoc """
  Kafka consumer group subscriber example.

  """
  @app Mix.Project.config()[:app]

  require Logger

  alias BrodGroupSubscriberExample.SubscriberBase

  use SubscriberBase

  use Retry

  # result =
  #   retry with: linear_backoff(backoff, 2) |> Stream.take(max_tries) do
  #     Elastix.Bulk.post_raw(elastic_url, data, elastix_options)
  #   after
  #     result -> result
  #   else
  #     error ->
  #       Logger.debug("Error: #{inspect(error)}")
  #       error
  #   end

  @impl SubscriberBase
  def process_message(message, state) do
    Logger.info("#{@app} message: #{inspect(message)} #{inspect(state)}")

    value = message[:value]

    case parse_value(value) do
      # {:error, reason} ->
      #   {:error, reason, state}
      {:ok, _parsed} ->
        {:ok, state}
    end
  end

  defp parse_value(value) do
    {:ok, value}
  end
end
