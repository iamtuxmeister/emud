defmodule Emud.Commands.System do
  @moduledoc """
  System commands: help, quit.
  """

  import Emud.Command, only: [reply: 2]

  # ─── help ─────────────────────────────────────────────────────────────────

  def help(state, "") do
    lines =
      Emud.Command.all_commands()
      |> Enum.map_join("\r\n", fn cmd ->
        aliases =
          case cmd.aliases do
            []  -> ""
            als -> "  [#{Enum.join(als, ", ")}]"
          end
        name_col = String.pad_trailing(cmd.name, 12)
        "  #{name_col}#{aliases}\r\n      #{cmd.help}"
      end)

    text = "\r\nAvailable commands:\r\n\r\n#{lines}\r\n\r\n" <>
           "You can abbreviate commands. For example, 'l' for 'look'.\r\n" <>
           "Unambiguous prefixes also work: 'inv' for 'inventory'.\r\n\r\n"
    reply(state, text)
  end

  def help(state, topic) do
    case Enum.find(Emud.Command.all_commands(), fn cmd ->
           cmd.name == topic or topic in cmd.aliases
         end) do
      nil ->
        reply(state, "No help available for '#{topic}'.\r\n")

      cmd ->
        aliases =
          case cmd.aliases do
            []  -> "none"
            als -> Enum.join(als, ", ")
          end
        text = "\r\n#{cmd.name}\r\n  Aliases : #{aliases}\r\n  #{cmd.help}\r\n\r\n"
        reply(state, text)
    end
  end

  # ─── quit ─────────────────────────────────────────────────────────────────

  def quit(state, _args) do
    # Send the farewell, then ask the connection process to close the socket.
    # The cast is async so the goodbye text has time to flush before teardown.
    state = reply(state, "Goodbye!\r\n")
    Emud.Telnet.Connection.disconnect(state.conn_pid)
    state
  end
end
