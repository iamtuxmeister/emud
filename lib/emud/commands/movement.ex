defmodule Emud.Commands.Movement do
  @moduledoc """
  Movement commands: north, south, east, west, ne, nw, se, sw, up, down.

  Each handler receives `(state, args)` and returns the updated state.
  When the world/room system is built, replace the stub responses with
  real exit lookups against the room data.
  """

  import Emud.Command, only: [reply: 2]

  # ─── Handlers ─────────────────────────────────────────────────────────────

  def north(state, _args),     do: move(state, "north")
  def south(state, _args),     do: move(state, "south")
  def east(state, _args),      do: move(state, "east")
  def west(state, _args),      do: move(state, "west")
  def northeast(state, _args), do: move(state, "northeast")
  def northwest(state, _args), do: move(state, "northwest")
  def southeast(state, _args), do: move(state, "southeast")
  def southwest(state, _args), do: move(state, "southwest")
  def up(state, _args),        do: move(state, "up")
  def down(state, _args),      do: move(state, "down")

  # ─── Internal ─────────────────────────────────────────────────────────────

  defp move(state, direction) do
    # TODO: look up exit in room data; move player; send room description.
    # For now, stub out all exits as blocked.
    reply(state, "There is no exit to the #{direction}.\r\n")
  end
end
