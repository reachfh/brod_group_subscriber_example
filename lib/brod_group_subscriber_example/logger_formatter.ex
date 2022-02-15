defmodule BrodGroupSubscriberExample.LoggerFormatter do
  @moduledoc """
  Logger formatter module with compact metadata.
  """

  @doc "Erlang logger filter which formats metadata more cleanly"
  @spec format_metadata(:logger.log_event(), :logger.filter_arg()) :: :logger.filter_return()
  def format_metadata(%{meta: meta} = event, _arg) do
    meta =
      meta
      |> Enum.map(&format_metadata/1)
      |> Enum.into(%{})

    %{event | meta: meta}
  end

  def format_metadata(event, _arg), do: event

  defp format_metadata({:uuid = key, value}) when is_binary(value), do: {key, to_charlist(value)}
  defp format_metadata({:id = key, value}) when is_binary(value), do: {key, to_charlist(value)}

  defp format_metadata({:mfa = key, {module, function, arity} = value}) do
    case to_string(module) do
      "Elixir." <> rest ->
        {key, {String.to_atom(rest), function, arity}}

      _ ->
        {key, value}
    end
  end

  defp format_metadata(pair), do: pair

  @doc "Format without time"
  def format(level, msg, _timestamp, metadata) do
    [_level(level), _metadata(metadata), msg, ?\n]
  end

  @doc "Format with time"
  def format_time(level, msg, timestamp, metadata) do
    [_time(timestamp), _level(level), _metadata(metadata), msg, ?\n]
  end

  @doc "Format with datetime"
  def format_datetime(level, msg, timestamp, metadata) do
    [_datetime(timestamp), _level(level), _metadata(metadata), msg, ?\n]
  end

  @doc "Format for journald"
  def format_journald(level, msg, _timestamp, metadata) do
    [_journald_level(level), _metadata(metadata), msg, ?\n]
  end

  # <7>This is a DEBUG level message
  # <6>This is an INFO level message
  # <5>This is a NOTICE level message
  # <4>This is a WARNING level message
  # <3>This is an ERR level message
  # <2>This is a CRIT level message
  # <1>This is an ALERT level message
  # <0>This is an EMERG level message
  defp _journald_level(level)
  defp _journald_level(:debug), do: "<7>"
  defp _journald_level(:info), do: "<6>"
  defp _journald_level(:notice), do: "<5>"
  defp _journald_level(:warn), do: "<4>"
  defp _journald_level(:warning), do: "<4>"
  defp _journald_level(:error), do: "<3>"

  # defp _msg(msg) do
  #   msg
  #   |> to_string()
  #   # |> String.replace(msg, "\n", "\t")
  # end

  defp _level(level) do
    [?[, Atom.to_string(level), ?], _levelpad(level)]
  end

  # Add spaces after level to make everything line up
  defp _levelpad(:debug), do: " "
  defp _levelpad(:info), do: "  "
  defp _levelpad(:notice), do: " "
  defp _levelpad(:warn), do: "  "
  defp _levelpad(:warning), do: " "
  defp _levelpad(:error), do: " "

  defp _time({_date, time}) do
    [Logger.Formatter.format_time(time), 32]
  end

  defp _datetime({date, time}) do
    [Logger.Formatter.format_date(date), 32, Logger.Formatter.format_time(time), 32]
  end

  defp _metadata(md) when is_list(md) do
    id = _id(md[:id] || md[:uuid] || md[:request_id])
    pid = _pid(md[:pid])
    source = _source(md[:application], md[:module], md[:function], md[:line])

    [pid, id, source]
  end

  defp _metadata(_), do: ""

  defp _id(nil), do: ""
  defp _id(value), do: [value, 32]

  # ?@
  defp _pid(pid) when is_pid(pid), do: [:erlang.pid_to_list(pid), 32]
  defp _pid(_), do: ""

  defp _source(application, module, function, line)
  defp _source(nil, nil, nil, nil), do: ""

  defp _source(application, module, function, line) do
    application = _default(application)
    # file = _default(md[:file])
    module = _module(module)
    function = _function(function)
    line = _line(line)
    [application, module, function, line, 32]
  end

  defp _default(nil), do: ""
  defp _default(value), do: [to_string(value), 32]

  defp _module(nil), do: ""
  defp _module(value) when is_atom(value), do: _module(to_string(value))
  defp _module("Elixir." <> value), do: [value, ?:]
  defp _module(value), do: [value, ?:]

  defp _function(nil), do: ""
  defp _function(""), do: ""

  defp _function(value) when is_binary(value) do
    [function, _arity] = String.split(value, "/")
    [function, ?:]
  end

  defp _line(line) when is_integer(line), do: Integer.to_string(line)
  defp _line(_), do: ""
end
