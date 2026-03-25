defmodule Emud.Telnet.MSDP do
  @moduledoc """
  MSDP — MUD Server Data Protocol  (option 69).

  Binary key-value encoding inside telnet subnegotiation.
  See http://tintin.sourceforge.net/msdp/ for the full spec.
  """

  require Logger
  require Emud.Telnet.Options, as: O

  @type value  :: String.t() | map() | list()
  @type varmap :: %{String.t() => value()}
  @type state  :: %{enabled: boolean(), reported: list(String.t()), variables: varmap()}

  def new, do: %{enabled: false, reported: [], variables: %{}}
  def enable(state), do: %{state | enabled: true}

  # ─── Sending ──────────────────────────────────────────────────────────────

  @spec build_message(varmap() | [{String.t(), value()}]) :: binary()
  def build_message(vars) when is_map(vars) or is_list(vars) do
    payload = vars |> Enum.map(fn {k, v} -> encode_var(k, v) end) |> IO.iodata_to_binary()
    O.subneg(O.opt_msdp(), payload)
  end

  def reportable_variables(var_names) when is_list(var_names) do
    build_message(%{"REPORTABLE_VARIABLES" => var_names})
  end

  # ─── Receiving ────────────────────────────────────────────────────────────

  @spec handle_subneg(state(), binary()) :: {state(), list()}
  def handle_subneg(state, payload) do
    vars = decode_payload(payload)
    Enum.reduce(vars, {state, []}, fn {var, value}, {st, acts} ->
      {st2, new_acts} = handle_var(st, var, value)
      {st2, acts ++ new_acts}
    end)
  end

  # ─── Variable handlers ────────────────────────────────────────────────────

  defp handle_var(state, "LIST", "REPORTABLE_VARIABLES") do
    {state, [{:send, reportable_variables(Map.keys(state.variables))}]}
  end

  defp handle_var(state, "REPORT", var) do
    reported = Enum.uniq([var | state.reported])
    actions  = case Map.fetch(state.variables, var) do
      {:ok, val} -> [{:send, build_message(%{var => val})}]
      :error     -> []
    end
    {%{state | reported: reported}, actions}
  end

  defp handle_var(state, "UNREPORT", var) do
    {%{state | reported: List.delete(state.reported, var)}, []}
  end

  defp handle_var(state, "SEND", var) do
    actions = case Map.fetch(state.variables, var) do
      {:ok, val} -> [{:send, build_message(%{var => val})}]
      :error     -> []
    end
    {state, actions}
  end

  defp handle_var(state, var, value) do
    Logger.debug("MSDP unhandled: #{var}=#{inspect(value)}")
    {state, [{:event, {:msdp, var, value}}]}
  end

  # ─── Encoding ─────────────────────────────────────────────────────────────

  defp encode_var(name, value) when is_binary(value) or is_number(value) do
    [O.msdp_var(), to_string(name), O.msdp_val(), to_string(value)]
  end

  defp encode_var(name, values) when is_list(values) do
    inner = Enum.map(values, fn v -> [O.msdp_val(), to_string(v)] end)
    [O.msdp_var(), to_string(name), O.msdp_val(),
     O.msdp_array_open(), inner, O.msdp_array_close()]
  end

  defp encode_var(name, values) when is_map(values) do
    inner = Enum.map(values, fn {k, v} ->
      [O.msdp_var(), to_string(k), O.msdp_val(), to_string(v)]
    end)
    [O.msdp_var(), to_string(name), O.msdp_val(),
     O.msdp_table_open(), inner, O.msdp_table_close()]
  end

  # ─── Decoding ─────────────────────────────────────────────────────────────

  defp decode_payload(bin), do: decode_vars(bin, [])

  defp decode_vars(<<>>, acc), do: Enum.reverse(acc)

  defp decode_vars(<<O.msdp_var()::8, rest::binary>>, acc) do
    case split_on(rest, O.msdp_val()) do
      {name, <<O.msdp_table_open()::8, rest2::binary>>} ->
        {table, rest3} = decode_table(rest2, %{})
        decode_vars(rest3, [{name, table} | acc])
      {name, <<O.msdp_array_open()::8, rest2::binary>>} ->
        {arr, rest3} = decode_array(rest2, [])
        decode_vars(rest3, [{name, arr} | acc])
      {name, rest2} ->
        {val, rest3} = split_on_or_end(rest2, O.msdp_var())
        decode_vars(rest3, [{name, val} | acc])
      :error -> []
    end
  end

  defp decode_vars(<<_::8, rest::binary>>, acc), do: decode_vars(rest, acc)

  defp decode_table(<<O.msdp_table_close()::8, rest::binary>>, table), do: {table, rest}
  defp decode_table(<<O.msdp_var()::8, rest::binary>>, table) do
    case split_on(rest, O.msdp_val()) do
      {k, rest2} ->
        {v, rest3} = split_on_or_end(rest2, O.msdp_var())
        decode_table(rest3, Map.put(table, k, v))
      :error -> {table, <<>>}
    end
  end
  defp decode_table(<<_::8, rest::binary>>, table), do: decode_table(rest, table)

  defp decode_array(<<O.msdp_array_close()::8, rest::binary>>, arr),
    do: {Enum.reverse(arr), rest}
  defp decode_array(<<O.msdp_val()::8, rest::binary>>, arr) do
    {v, rest2} = split_on_or_end(rest, O.msdp_val())
    decode_array(rest2, [v | arr])
  end
  defp decode_array(<<_::8, rest::binary>>, arr), do: decode_array(rest, arr)

  defp split_on(bin, byte) do
    case :binary.split(bin, <<byte::8>>) do
      [before, rest] -> {before, rest}
      _              -> :error
    end
  end

  defp split_on_or_end(bin, byte) do
    case :binary.split(bin, <<byte::8>>) do
      [before, rest] -> {before, <<byte::8, rest::binary>>}
      [before]       -> {before, <<>>}
    end
  end
end
