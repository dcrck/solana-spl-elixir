defmodule Solana.SPL.MixProject do
  use Mix.Project

  @source_url "https://git.sr.ht/~dcrck/solana-spl"

  def project do
    [
      app: :solana_spl,
      description: description(),
      version: "0.1.0",
      elixir: "~> 1.12",
      package: package(),
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      name: "Solana.SPL",
      source_url: @source_url,
      homepage_url: @source_url,
      deps: deps(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  def elixirc_paths(:test), do: ["lib", "test/support"]
  def elixirc_paths(_), do: ["lib"]

  defp description do
    "A library for interacting with the Solana Program Library's programs."
  end

  defp package do
    [
      maintainers: ["Derek Meer"],
      licenses: ["MIT"],
      links: %{"SourceHut" => "https://git.sr.ht/~dcrck/solana-spl"}
    ]
  end

  defp deps do
    [
      # base solana interface
      {:solana, "~> 0.1.0"},
      # docs and testing
      {:ex_doc, "~> 0.25.5", only: :dev, runtime: false},
      {:dialyxir, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_url: @source_url,
      extras: ["README.md", "LICENSE"],
      groups_for_modules: [
        "Associated Token": [
          Solana.SPL.AssociatedToken,
        ],
        Token: [
          Solana.SPL.Token,
          Solana.SPL.Token.Mint,
          Solana.SPL.Token.MultiSig
        ]
      ],
      nest_modules_by_prefix: [
        Solana.SPL.Token
      ]
    ]
  end
end
