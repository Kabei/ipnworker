defmodule Ipnworker.MixProject do
  use Mix.Project

  @app :ipnworker
  @version "0.5.1"
  @min_otp 25

  def project do
    [
      app: @app,
      version: @version,
      config_path: "config/config.exs",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def version, do: @version

  # Run "mix help compile.app" to learn about applications.
  def application do
    if System.otp_release() |> String.to_integer() < @min_otp,
      do: raise(RuntimeError, "OTP invalid version. Required minimum v#{@min_otp}")

    [
      extra_applications: [:crypto, :syntax_tools, :logger],
      mod: {Ipnworker.Application, []}
    ]
  end

  def package do
    [
      name: @app,
      maintainers: ["Kambei Sapote"],
      licenses: ["MIT"],
      files: ["lib/*", "mix.exs", "README*", "LICENSE*"]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:poolboy, "~> 1.5.2"},
      {:jason, "~> 1.4"},
      {:httpoison, "~> 2.0"},
      {:postgrex, "~> 0.17"},
      {:ecto, "~> 3.11"},
      {:ecto_sql, "~> 3.11"},
      {:bandit, "~> 1.4"},
      {:dnslib, git: "https://github.com/lateio/dnslib", branch: "master", override: true},
      {:phoenix_pubsub, "~> 2.1"},
      {:cafezinho, "~> 0.4.0"},
      {:ex_secp256k1, "~> 0.7.2"},
      {:blake3, git: "https://kabei@github.com/kabei/blake3.git", branch: "master"},
      {:exqlite, git: "https://kabei@github.com/kabei/exqlite.git", branch: "main"},
      {:falcon, git: "https://kabei@github.com/kabei/falcon.git", branch: "master"},
      {:ntrukem, git: "https://kabei@github.com/kabei/ntrukem.git", branch: "master"},
      {:fast64, git: "https://kabei@github.com/kabei/fast64_elixir.git", branch: "master"}
    ]
  end
end
