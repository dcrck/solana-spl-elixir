# Solana.SPL

The unofficial Elixir package for interacting with the [Solana Program
Library](https://spl.solana.com).

> Note that this README refers to the master branch of `solana_spl`, not the latest
> released version on Hex. See [the documentation](https://hexdocs.pm/solana_spl)
> for the documentation of the version you're using.

## Installation

Add `solana_spl` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:solana_spl, "~> 0.1.0"}
  ]
end
```

## Usage Guidelines

TODO. For now, the [`solana` package docs](https://hexdocs.pm/solana) contain
everything you need to know to use `solana_spl`.

## List of Programs

This library implements instructions and tests for the following programs:

- [x] [Token Program](https://spl.solana.com/token): `Solana.SPL.Token`
- [x] [Associated Token Account
  Program](https://spl.solana.com/associated-token-account):
  `Solana.SPL.AssociatedToken`
- [x] [Token Swap Program](https://spl.solana.com/token): `Solana.SPL.TokenSwap`
- [ ] [Governance Program](https://github.com/solana-labs/solana-program-library/tree/master/governance): `Solana.SPL.Governance`
