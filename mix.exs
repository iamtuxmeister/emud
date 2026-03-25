defmodule Emud.MixProject do
  use Mix.Project

  def project do
    [
      app: :emud,
      version: "0.1.0",
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: "An OTP-based MUD server with MCCP2/GMCP/MSDP support"
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {Emud.Application, []}
    ]
  end

  defp deps do
    [
      {:ranch, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:dialyxir, "~> 1.4", only: [:dev], runtime: false},
      {:ex_doc,   "~> 0.34", only: :dev,  runtime: false}
    ]
  end
end
