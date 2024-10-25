defmodule MspOsd.MixProject do
  use Mix.Project

  def project do
    [
      app: :msp_osd,
      version: "0.1.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {MspOsd.Application, []}
    ]
  end

  defp deps do
    [
      {:circuits_uart, "~> 1.5"}
    ]
  end
end
