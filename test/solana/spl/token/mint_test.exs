defmodule Solana.SPL.Token.MintTest do
  use ExUnit.Case, async: true

  import Solana.SPL.TestHelpers, only: [create_payer: 3]

  alias Solana.{Transaction, RPC, SPL.Token}

  setup_all do
    {:ok, tracker} = RPC.Tracker.start_link(network: "localhost", t: 100)
    client = RPC.client(network: "localhost")
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "init/1" do
    test "initializes a new mint, with and without a freeze_authority", global do
      new = Solana.keypair()
      freeze = Solana.keypair()
      {_, auth_pk} = Solana.keypair()
      opts = [commitment: "confirmed"]
      space = Token.Mint.byte_size()

      tx_reqs = [
        RPC.Request.get_minimum_balance_for_rent_exemption(space, opts),
        RPC.Request.get_recent_blockhash(opts)
      ]

      [{:ok, lamports}, {:ok, %{"blockhash" => blockhash}}] = RPC.send(global.client, tx_reqs)

      tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: lamports,
            payer: Solana.pubkey!(global.payer),
            authority: auth_pk,
            new: Solana.pubkey!(new),
            decimals: 0
          ),
          Token.Mint.init(
            balance: lamports,
            payer: Solana.pubkey!(global.payer),
            authority: auth_pk,
            freeze_authority: auth_pk,
            new: Solana.pubkey!(freeze),
            decimals: 0
          )
        ],
        signers: [global.payer, new, freeze],
        blockhash: blockhash,
        payer: Solana.pubkey!(global.payer)
      }

      opts = [commitment: "confirmed", timeout: 1_000]
      {:ok, _signatures} = RPC.send_and_confirm(global.client, global.tracker, tx, opts)
      opts = [commitment: "confirmed", encoding: "jsonParsed"]

      assert {:ok, mint} =
               RPC.send(global.client, RPC.Request.get_account_info(Solana.pubkey!(new), opts))

      assert %Token.Mint{
               decimals: 0,
               authority: ^auth_pk,
               initialized?: true,
               freeze_authority: nil,
               supply: 0
             } = Token.Mint.from_account_info(mint)

      assert {:ok, freeze_mint} =
               RPC.send(global.client, RPC.Request.get_account_info(Solana.pubkey!(freeze), opts))

      assert %Token.Mint{
               decimals: 0,
               authority: ^auth_pk,
               initialized?: true,
               freeze_authority: ^auth_pk,
               supply: 0
             } = Token.Mint.from_account_info(freeze_mint)
    end
  end
end
