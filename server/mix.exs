defmodule MiniDiscord.MixProject do
  use Mix.Project

  def project do
    [app: :mini_discord, version: "0.1.0", elixir: "~> 1.14"]
  end

  def application do
    [mod: {MiniDiscord, []}, extra_applications: [:logger, :crypto]]
  end
end
