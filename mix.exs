defmodule ElixirMud.MixProject do
  use Mix.Project

  def project do
    [
      app: :elixir_mud,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      dialyzer: [plt_add_apps: [:ranch]],
      description: "An OTP-based MUD server with MCCP2/GMCP/MSDP support"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {ElixirMud.Application, []}
    ]
  end

  defp deps do
    [
      # TCP acceptor pool — battle-tested in Erlang/OTP land
      {:ranch, "~> 2.1"},
      # JSON codec used by GMCP
      {:jason, "~> 1.4"},
      # Optional: dialyzer type-checking
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      # Optional: test helpers
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end
end
