defmodule ElixirMud.Telnet.Options do
  @moduledoc """
  Telnet byte constants (RFC 854 and MUD extensions).

  Every option negotiation goes through WILL / WONT / DO / DONT.
  Subnegotiation data is framed with SB … SE.

  Protocol references
  -------------------
  RFC 854  — Telnet Protocol Specification
  RFC 855  — Telnet Option Specifications
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
  def iac,  do: 255   # Interpret As Command
  def se,   do: 240   # Subnegotiation End
  def nop,  do: 241   # No Operation
  def dm,   do: 242   # Data Mark
  def brk,  do: 243   # Break
  def ip,   do: 244   # Interrupt Process
  def ao,   do: 245   # Abort Output
  def ayt,  do: 246   # Are You There
  def ec,   do: 247   # Erase Character
  def el,   do: 248   # Erase Line
  def ga,   do: 249   # Go Ahead
  def sb,   do: 250   # Subnegotiation Begin
  def will, do: 251
  def wont, do: 252
  def do_,  do: 253
  def dont, do: 254

  # ─── Telnet options ────────────────────────────────────────────────────────
  def opt_echo,              do:   1   # RFC 857
  def opt_suppress_go_ahead, do:   3   # RFC 858
  def opt_status,            do:   5   # RFC 859
  def opt_ttype,             do:  24   # RFC 1091 — Terminal Type
  def opt_naws,              do:  31   # RFC 1073 — Window size
  def opt_charset,           do:  42   # RFC 2066
  def opt_msdp,              do:  69   # MSDP
  def opt_mccp1,             do:  85   # MCCP v1  (deprecated — never advertise)
  def opt_mccp2,             do:  86   # MCCP v2  (zlib deflate)
  def opt_gmcp,              do: 201   # GMCP

  # ─── MSDP value types (used inside SB MSDP … SE) ─────────────────────────
  def msdp_var,         do: 1
  def msdp_val,         do: 2
  def msdp_table_open,  do: 3
  def msdp_table_close, do: 4
  def msdp_array_open,  do: 5
  def msdp_array_close, do: 6

  # ─── Convenience builders ─────────────────────────────────────────────────

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
