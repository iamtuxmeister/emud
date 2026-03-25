defmodule Emud.Telnet.Options do
  @moduledoc """
  Telnet byte constants (RFC 854 and MUD extensions).

  All zero-argument constants are `defmacro` so they expand to integer
  literals at compile time and can be used in pattern-match heads and
  binary specifiers. Any module using them in patterns must `require` this
  module (not just `alias`):

      require Emud.Telnet.Options, as: O

  Protocol references
  -------------------
  RFC 854  — Telnet Protocol Specification
  RFC 857  — Echo option
  RFC 858  — Suppress Go-Ahead option
  RFC 1073 — NAWS (Negotiate About Window Size)
  RFC 1091 — Terminal-Type option
  RFC 2066 — CHARSET option
  MCCP2    — http://www.mudbytes.net/index.php?a=articles&s=mccp
  GMCP     — https://www.gammon.com.au/gmcp
  MSDP     — http://tintin.sourceforge.net/msdp/
  """

  # ─── Core telnet commands ──────────────────────────────────────────────────
  defmacro iac,  do: 255
  defmacro se,   do: 240
  defmacro nop,  do: 241
  defmacro dm,   do: 242
  defmacro brk,  do: 243
  defmacro ip,   do: 244
  defmacro ao,   do: 245
  defmacro ayt,  do: 246
  defmacro ec,   do: 247
  defmacro el,   do: 248
  defmacro ga,   do: 249
  defmacro sb,   do: 250
  defmacro will, do: 251
  defmacro wont, do: 252
  defmacro do_,  do: 253
  defmacro dont, do: 254

  # ─── Telnet options ────────────────────────────────────────────────────────
  defmacro opt_echo,              do:   1
  defmacro opt_suppress_go_ahead, do:   3
  defmacro opt_status,            do:   5
  defmacro opt_ttype,             do:  24
  defmacro opt_naws,              do:  31
  defmacro opt_charset,           do:  42
  defmacro opt_msdp,              do:  69
  defmacro opt_mccp1,             do:  85   # deprecated — never advertise
  defmacro opt_mccp2,             do:  86
  defmacro opt_gmcp,              do: 201

  # ─── MSDP value types ─────────────────────────────────────────────────────
  defmacro msdp_var,         do: 1
  defmacro msdp_val,         do: 2
  defmacro msdp_table_open,  do: 3
  defmacro msdp_table_close, do: 4
  defmacro msdp_array_open,  do: 5
  defmacro msdp_array_close, do: 6

  # ─── Convenience builders (regular functions — take arguments) ─────────────

  @doc "Build a WILL <option> sequence."
  def will(opt),  do: <<iac()::8, will()::8, opt::8>>

  @doc "Build a WONT <option> sequence."
  def wont(opt),  do: <<iac()::8, wont()::8, opt::8>>

  @doc "Build a DO <option> sequence."
  def do_(opt),   do: <<iac()::8, do_()::8,  opt::8>>

  @doc "Build a DONT <option> sequence."
  def dont(opt),  do: <<iac()::8, dont()::8, opt::8>>

  @doc "Wrap payload in IAC SB <option> … IAC SE."
  def subneg(opt, payload) do
    <<iac()::8, sb()::8, opt::8, payload::binary, iac()::8, se()::8>>
  end
end
