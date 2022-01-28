defmodule Solana.SPL.GovernanceTest do
  use ExUnit.Case, async: true

  import Solana.SPL.TestHelpers, only: [create_payer: 3, keypairs: 1]
  import Solana, only: [pubkey!: 1]

  alias Solana.{Key, RPC, Transaction, SPL.Governance, SPL.Token, SPL.AssociatedToken}

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

  test "SPL.Governance can create a realm, governance, and proposal", %{
    client: client,
    payer: payer,
    tracker: tracker,
    program: program
  } do
    [mint] = keypairs(1)
    {:ok, token} = AssociatedToken.find_address(pubkey!(mint), pubkey!(payer))

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

    mint_to_ix =
      Token.mint_to(
        token: token,
        mint: pubkey!(mint),
        authority: pubkey!(payer),
        amount: 1
      )

    token_tx = %Transaction{
      instructions: [
        Token.Mint.init(
          balance: mint_balance,
          payer: pubkey!(payer),
          authority: pubkey!(payer),
          new: pubkey!(mint),
          decimals: 0
        ),
        AssociatedToken.create_account(
          payer: pubkey!(payer),
          owner: pubkey!(payer),
          new: token,
          mint: pubkey!(mint)
        ),
        mint_to_ix
      ],
      signers: [payer, mint],
      blockhash: blockhash,
      payer: pubkey!(payer)
    }

    {:ok, _signature} =
      RPC.send_and_confirm(client, tracker, token_tx, commitment: "confirmed", timeout: 1_000)

    name = "realm" <> String.slice(B58.encode58(pubkey!(mint)), 0..6)
    proposal_index = 0
    {:ok, realm} = Governance.find_realm_address(program, name)

    {:ok, owner_record} =
      Governance.find_owner_record_address(program, realm, pubkey!(mint), pubkey!(payer))

    {:ok, governance} = Governance.find_mint_governance_address(program, realm, pubkey!(mint))

    {:ok, proposal} =
      Governance.find_proposal_address(program, governance, pubkey!(mint), proposal_index)

    governance_tx = %Transaction{
      instructions: [
        Governance.create_realm(
          payer: pubkey!(payer),
          authority: pubkey!(payer),
          community_mint: pubkey!(mint),
          program: program,
          name: name,
          max_vote_weight_source: {:fraction, 10_000_000_000},
          minimum: 1
        ),
        Governance.deposit(
          payer: pubkey!(payer),
          owner: pubkey!(payer),
          authority: pubkey!(payer),
          realm: realm,
          mint: pubkey!(mint),
          from: token,
          amount: 1,
          program: program
        ),
        Governance.create_mint_governance(
          payer: pubkey!(payer),
          owner_record: owner_record,
          authority: pubkey!(payer),
          realm: realm,
          governed: pubkey!(mint),
          mint_authority: pubkey!(payer),
          program: program,
          config: [threshold: {:yes, 60}, duration: :timer.hours(3)]
        ),
        Governance.set_realm_authority(
          realm: realm,
          current: pubkey!(payer),
          new: governance,
          program: program
        ),
        Governance.create_proposal(
          payer: pubkey!(payer),
          owner: pubkey!(payer),
          authority: pubkey!(payer),
          mint: pubkey!(mint),
          governance: governance,
          realm: realm,
          program: program,
          name: "proposal 1",
          description: "",
          vote_type: :single,
          options: ["Approve"],
          index: proposal_index
        ),
        Governance.insert_instruction(
          governance: governance,
          proposal: proposal,
          index: proposal_index,
          owner_record: owner_record,
          authority: pubkey!(payer),
          payer: pubkey!(payer),
          instruction: mint_to_ix,
          program: program
        )
      ],
      signers: [payer],
      blockhash: blockhash,
      payer: pubkey!(payer)
    }

    assert {:ok, _signatures} =
             RPC.send_and_confirm(client, tracker, governance_tx,
               commitment: "confirmed",
               timeout: 1_000
             )
  end
end
