defmodule Solana.SPL.GovernanceTest do
  use ExUnit.Case, async: true

  import Solana.SPL.TestHelpers, only: [create_payer: 3, keypairs: 1]
  import Solana, only: [pubkey!: 1]

  alias Solana.{Key, RPC, Transaction, SPL.Governance, SPL.Token}

  setup_all do
    {:ok, tracker} = RPC.Tracker.start_link(network: "localhost", t: 100)
    client = RPC.client(network: "localhost")
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    program =
      Key.pair_from_file("deps/solana-program-library/target/deploy/spl_governance-keypair.json")
      |> elem(1)
      |> pubkey!()

    [tracker: tracker, client: client, payer: payer, program: program]
  end

  describe "create_realm/1" do
    test "creates a realm with a community mint", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint] = keypairs(1)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      create_realm_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Governance.create_realm(
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: realm,
            community_mint: pubkey!(community_mint),
            program: program,
            name: name,
            max_vote_weight_source: {:fraction, 10_000_000_000},
            minimum: 1
          )
        ],
        signers: [payer, community_mint],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          create_realm_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, _realm_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(realm, commitment: "confirmed")
               )
    end

    test "creates a realm with a community mint and council mint", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      mints = [community_mint, council_mint] = keypairs(2)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      create_realm_tx = %Transaction{
        instructions: [
          Enum.map(mints, fn new ->
            Token.Mint.init(
              balance: mint_balance,
              payer: pubkey!(payer),
              authority: pubkey!(payer),
              new: pubkey!(new),
              decimals: 0
            )
          end),
          Governance.create_realm(
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: realm,
            community_mint: pubkey!(community_mint),
            council_mint: pubkey!(council_mint),
            program: program,
            name: name,
            max_vote_weight_source: {:fraction, 10_000_000_000},
            minimum: 1
          )
        ],
        signers: [payer | mints],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          create_realm_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, _realm_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(realm, commitment: "confirmed")
               )
    end
  end
end