defmodule Emud.Command do
  @moduledoc """
  Command parser and dispatcher.

  ## Resolution order

  Given a word typed by the player:

  1. Exact match on a command name or any of its aliases.
  2. Unambiguous prefix match on the full command name only
     (e.g. "inv" matches "inventory" if nothing else starts with "inv").
  3. If two or more commands share the prefix → "Ambiguous command" error.
  4. No match → "Unknown command" error.

  ## Defining commands

  Each entry in `@commands` is a map with:

    * `:name`    – canonical name (used in help, error messages)
    * `:aliases` – explicit short forms (bypass prefix matching)
    * `:help`    – one-line description shown by `help`
    * `:handler` – `{Module, :function}` called as `fun.(session_state, args)`
                   and expected to return the (possibly updated) session state.

  Add a new command by appending to `@commands` and implementing the
  handler function — no other changes needed.

  ## Adding a command

      %{
        name:    "greet",
        aliases: ["gr"],
        help:    "Greet everyone in the room.",
        handler: {Emud.Commands.Social, :greet}
      }

  The handler receives `(state, args_string)` and returns `state`.
  """

  alias Emud.Commands

  # ─── Command table ────────────────────────────────────────────────────────
  # Entries are checked in order for alias matching; prefix matching is done
  # over :name fields only.

  @commands [
    # ── Movement ──────────────────────────────────────────────────────────
    %{name: "north",     aliases: ["n"],   help: "Move north.",              handler: {Commands.Movement, :north}},
    %{name: "south",     aliases: ["s"],   help: "Move south.",              handler: {Commands.Movement, :south}},
    %{name: "east",      aliases: ["e"],   help: "Move east.",               handler: {Commands.Movement, :east}},
    %{name: "west",      aliases: ["w"],   help: "Move west.",               handler: {Commands.Movement, :west}},
    %{name: "northeast", aliases: ["ne"],  help: "Move northeast.",          handler: {Commands.Movement, :northeast}},
    %{name: "northwest", aliases: ["nw"],  help: "Move northwest.",          handler: {Commands.Movement, :northwest}},
    %{name: "southeast", aliases: ["se"],  help: "Move southeast.",          handler: {Commands.Movement, :southeast}},
    %{name: "southwest", aliases: ["sw"],  help: "Move southwest.",          handler: {Commands.Movement, :southwest}},
    %{name: "up",        aliases: ["u"],   help: "Move up.",                 handler: {Commands.Movement, :up}},
    %{name: "down",      aliases: ["d"],   help: "Move down.",               handler: {Commands.Movement, :down}},

    # ── Information ───────────────────────────────────────────────────────
    %{name: "look",      aliases: ["l"],   help: "Look at your surroundings.", handler: {Commands.Info, :look}},
    %{name: "examine",   aliases: ["ex", "x"], help: "Examine something.",    handler: {Commands.Info, :examine}},
    %{name: "inventory", aliases: ["i", "inv"], help: "List your inventory.", handler: {Commands.Info, :inventory}},
    %{name: "score",     aliases: ["sc"],  help: "Show your character stats.", handler: {Commands.Info, :score}},
    %{name: "who",       aliases: [],      help: "List connected players.",   handler: {Commands.Info, :who}},

    # ── Communication ─────────────────────────────────────────────────────
    %{name: "say",       aliases: ["'"],   help: "Say something aloud.",      handler: {Commands.Comms, :say}},
    %{name: "yell",      aliases: ["y"],   help: "Yell across the area.",     handler: {Commands.Comms, :yell}},
    %{name: "tell",      aliases: ["t"],   help: "Send a private message.",   handler: {Commands.Comms, :tell}},

    # ── System ────────────────────────────────────────────────────────────
    %{name: "help",      aliases: ["?", "h"], help: "Show help.",             handler: {Commands.System, :help}},
    %{name: "quit",      aliases: ["q"],   help: "Disconnect from the game.", handler: {Commands.System, :quit}},
  ]

  # Build lookup structures at compile time for O(1) dispatch.
  # alias_map  :: %{string => command_map}
  # prefix_list :: [{name_string, command_map}]  – used for prefix scan

  @alias_map Enum.reduce(@commands, %{}, fn cmd, acc ->
    acc
    |> Map.put(cmd.name, cmd)
    |> then(fn m -> Enum.reduce(cmd.aliases, m, &Map.put(&2, &1, cmd)) end)
  end)

  @prefix_list Enum.map(@commands, fn cmd -> {cmd.name, cmd} end)

  # ─── Public API ───────────────────────────────────────────────────────────

  @doc """
  Parse and dispatch a raw input line.
  Returns the (possibly updated) session state.
  """
  @spec dispatch(session_state :: map(), input :: String.t()) :: map()
  def dispatch(state, ""), do: state

  def dispatch(state, input) do
    {word, args} = split_input(input)

    case resolve(word) do
      {:ok, cmd}            -> invoke(state, cmd, args)
      {:error, :ambiguous, matches} ->
        reply(state, "Ambiguous command '#{word}' — did you mean: #{Enum.join(matches, ", ")}?\r\n")
      {:error, :unknown}    ->
        reply(state, "Unknown command '#{word}'. Type 'help' for a list of commands.\r\n")
    end
  end

  @doc "Return the full command list (used by the help command)."
  def all_commands, do: @commands

  # ─── Resolution ───────────────────────────────────────────────────────────

  defp resolve(word) do
    # 1. Exact alias / name match
    case Map.fetch(@alias_map, word) do
      {:ok, cmd} -> {:ok, cmd}
      :error     -> prefix_match(word)
    end
  end

  defp prefix_match(word) do
    matches =
      Enum.filter(@prefix_list, fn {name, _cmd} ->
        String.starts_with?(name, word)
      end)

    case matches do
      []               -> {:error, :unknown}
      [{_name, cmd}]   -> {:ok, cmd}
      many             -> {:error, :ambiguous, Enum.map(many, &elem(&1, 0))}
    end
  end

  # ─── Invocation ───────────────────────────────────────────────────────────

  defp invoke(state, %{handler: {mod, fun}}, args) do
    apply(mod, fun, [state, args])
  end

  # ─── Helpers ──────────────────────────────────────────────────────────────

  # Split "look here" into {"look", "here"}, "look" into {"look", ""}
  defp split_input(input) do
    case String.split(input, " ", parts: 2) do
      [word]        -> {String.downcase(word), ""}
      [word, rest]  -> {String.downcase(word), String.trim(rest)}
    end
  end

  @doc false
  def reply(state, text) do
    Emud.Telnet.Connection.send_text(state.conn_pid, text)
    state
  end
end
