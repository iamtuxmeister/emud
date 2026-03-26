defmodule Emud.Commands.Comms do
  @moduledoc """
  Communication commands: say, yell, tell.
  """

  import Emud.Command, only: [reply: 2]

  # ─── say ──────────────────────────────────────────────────────────────────

  def say(state, "") do
    reply(state, "Say what?\r\n")
  end

  def say(state, message) do
    # TODO: broadcast to all players in the same room
    reply(state, "You say, \"#{message}\"\r\n")
  end

  # ─── yell ─────────────────────────────────────────────────────────────────

  def yell(state, "") do
    reply(state, "Yell what?\r\n")
  end

  def yell(state, message) do
    # TODO: broadcast to all players in the same area/zone
    reply(state, "You yell, \"#{message}\"\r\n")
  end

  # ─── tell ─────────────────────────────────────────────────────────────────

  def tell(state, "") do
    reply(state, "Tell whom what? Usage: tell <player> <message>\r\n")
  end

  def tell(state, args) do
    case String.split(args, " ", parts: 2) do
      [_target] ->
        reply(state, "Tell #{args} what?\r\n")

      [target, message] ->
        case Registry.lookup(Emud.Session.Registry, target) do
          [{pid, _}] ->
            Emud.Session.send_output(pid, "#{state.player_name} tells you, \"#{message}\"\r\n")
            reply(state, "You tell #{target}, \"#{message}\"\r\n")

          [] ->
            reply(state, "There is no player named '#{target}' online.\r\n")
        end
    end
  end
end
