defmodule Emud.Commands.Info do
  @moduledoc """
  Informational commands: look, examine, inventory, score, who.
  """

  import Emud.Command, only: [reply: 2]

  # ─── look ─────────────────────────────────────────────────────────────────

  def look(state, "") do
    # TODO: fetch real room data from world system
    reply(state, room_description(state.room_id))
  end

  def look(state, target) do
    # TODO: look at specific target in room or inventory
    reply(state, "You look at #{target}.\r\nYou see nothing special.\r\n")
  end

  # ─── examine ──────────────────────────────────────────────────────────────

  def examine(state, "") do
    reply(state, "Examine what?\r\n")
  end

  def examine(state, target) do
    # TODO: detailed object inspection
    reply(state, "You examine #{target} closely.\r\nYou notice nothing out of the ordinary.\r\n")
  end

  # ─── inventory ────────────────────────────────────────────────────────────

  def inventory(state, _args) do
    # TODO: list items from character inventory
    reply(state, "You are carrying nothing.\r\n")
  end

  # ─── score ────────────────────────────────────────────────────────────────

  def score(state, _args) do
    char = state.character
    text = """
    \r
    ─────────────────── Character ───────────────────\r
    Name   : #{state.player_name}\r
    HP     : #{char.hp} / #{char.max_hp}\r
    MP     : #{char.mp} / #{char.max_mp}\r
    ─────────────────────────────────────────────────\r
    \r
    """
    reply(state, text)
  end

  # ─── who ──────────────────────────────────────────────────────────────────

  def who(state, _args) do
    players =
      Emud.Session.Registry
      |> Registry.select([{{:"$1", :_, :_}, [], [:"$1"]}])
      |> Enum.sort()

    lines =
      players
      |> Enum.map_join("\r\n", fn name -> "  #{name}" end)

    count = length(players)
    noun  = if count == 1, do: "player", else: "players"

    text = "\r\nConnected (#{count} #{noun}):\r\n#{lines}\r\n\r\n"
    reply(state, text)
  end

  # ─── Room description stub ────────────────────────────────────────────────

  defp room_description(:limbo) do
    "\r\n[ The Void ]\r\n" <>
    "An infinite grey expanse stretches in every direction.\r\n" <>
    "There are no exits.\r\n\r\n"
  end

  defp room_description(id) do
    "\r\n[ Room #{inspect(id)} ]\r\nYou are somewhere.\r\n\r\n"
  end
end
