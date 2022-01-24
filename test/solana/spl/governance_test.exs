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

      # TODO add more assertions
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

      # TODO add more assertions
    end
  end

  describe "deposit/1" do
    test "deposits community tokens into the realm", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token] = keypairs(2)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      deposit_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(community_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(community_mint),
            authority: pubkey!(payer),
            amount: 1
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          )
        ],
        signers: [payer, community_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          deposit_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, token_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(token),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %Token{amount: 0} = Token.from_account_info(token_info)
    end

    test "deposits council tokens into the realm", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, council_mint, token] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      deposit_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(council_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(council_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(council_mint),
            authority: pubkey!(payer),
            amount: 1
          ),
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(council_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          )
        ],
        signers: [payer, community_mint, council_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          deposit_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, token_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(token),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %Token{amount: 0} = Token.from_account_info(token_info)
    end
  end

  describe "withdraw/1" do
    test "withdraws community tokens from the realm", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token] = keypairs(2)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      withdraw_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(community_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(community_mint),
            authority: pubkey!(payer),
            amount: 1
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.withdraw(
            owner: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            to: pubkey!(token),
            program: program
          )
        ],
        signers: [payer, community_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          withdraw_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, token_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(token),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %Token{amount: 1} = Token.from_account_info(token_info)
    end

    test "withdraws council tokens from the realm", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, council_mint, token] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      withdraw_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(council_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(council_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(council_mint),
            authority: pubkey!(payer),
            amount: 1
          ),
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(council_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.withdraw(
            owner: pubkey!(payer),
            realm: realm,
            mint: pubkey!(council_mint),
            to: pubkey!(token),
            program: program
          )
        ],
        signers: [payer, community_mint, council_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          withdraw_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, token_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(token),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %Token{amount: 1} = Token.from_account_info(token_info)
    end
  end

  describe "delegate/1" do
    test "delegates voting rights for community tokens", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token, delegate] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      delegate_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(community_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(community_mint),
            authority: pubkey!(payer),
            amount: 1
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.delegate(
            owner: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            to: pubkey!(delegate),
            program: program
          )
        ],
        signers: [payer, community_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      assert {:ok, _signatures} =
               RPC.send_and_confirm(
                 client,
                 tracker,
                 delegate_tx,
                 commitment: "confirmed",
                 timeout: 1_000
               )

      # TODO add more assertions
    end

    test "delegates voting rights for council tokens", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, council_mint, token, delegate] = keypairs(4)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      delegate_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(council_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(council_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(council_mint),
            authority: pubkey!(payer),
            amount: 1
          ),
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(council_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.delegate(
            owner: pubkey!(payer),
            realm: realm,
            mint: pubkey!(council_mint),
            to: pubkey!(delegate),
            program: program
          )
        ],
        signers: [payer, community_mint, council_mint, token],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      assert {:ok, _signatures} =
               RPC.send_and_confirm(
                 client,
                 tracker,
                 delegate_tx,
                 commitment: "confirmed",
                 timeout: 1_000
               )

      # TODO add more assertions
    end
  end

  describe "create_account_governance/1" do
    test "creates an account governance", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token, governed] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      deposit_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Enum.map([token, governed], fn tk ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                owner: pubkey!(payer),
                new: pubkey!(tk),
                mint: pubkey!(community_mint)
              ),
              Token.mint_to(
                token: pubkey!(tk),
                mint: pubkey!(community_mint),
                authority: pubkey!(payer),
                amount: 1
              )
            ]
          end),
          Governance.create_realm(
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: realm,
            community_mint: pubkey!(community_mint),
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
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.create_account_governance(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            governed: pubkey!(governed),
            program: program,
            config: [threshold: {:yes, 60}, duration: :timer.hours(3)]
          )
        ],
        signers: [payer, community_mint, token, governed],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          deposit_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      # TODO add assertions here
    end
  end

  describe "create_mint_governance/1" do
    test "creates a token mint governance", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token, governed] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      deposit_tx = %Transaction{
        instructions: [
          Enum.map([community_mint, governed], fn pair ->
            Token.Mint.init(
              balance: mint_balance,
              payer: pubkey!(payer),
              authority: pubkey!(payer),
              new: pubkey!(pair),
              decimals: 0
            )
          end),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            new: pubkey!(token),
            mint: pubkey!(community_mint)
          ),
          Token.mint_to(
            token: pubkey!(token),
            mint: pubkey!(community_mint),
            authority: pubkey!(payer),
            amount: 1
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
          ),
          Governance.deposit(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.create_mint_governance(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            governed: pubkey!(governed),
            mint_authority: pubkey!(payer),
            program: program,
            config: [threshold: {:yes, 60}, duration: :timer.hours(3)]
          )
        ],
        signers: [payer, community_mint, token, governed],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          deposit_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      # TODO add assertions here
    end
  end

  describe "create_token_governance/1" do
    test "creates a token governance", %{
      client: client,
      payer: payer,
      tracker: tracker,
      program: program
    } do
      [community_mint, token, governed] = keypairs(3)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed"),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.byte_size(),
          commitment: "confirmed"
        ),
        RPC.Request.get_minimum_balance_for_rent_exemption(Token.Mint.byte_size(),
          commitment: "confirmed"
        )
      ]

      [%{"blockhash" => blockhash}, token_balance, mint_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      name = "realm" <> String.slice(B58.encode58(pubkey!(community_mint)), 0..6)
      {:ok, realm, _} = Key.find_address(["governance", name], program)

      deposit_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: pubkey!(community_mint),
            decimals: 0
          ),
          Enum.map([token, governed], fn tk ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                owner: pubkey!(payer),
                new: pubkey!(tk),
                mint: pubkey!(community_mint)
              ),
              Token.mint_to(
                token: pubkey!(tk),
                mint: pubkey!(community_mint),
                authority: pubkey!(payer),
                amount: 1
              )
            ]
          end),
          Governance.create_realm(
            payer: pubkey!(payer),
            authority: pubkey!(payer),
            new: realm,
            community_mint: pubkey!(community_mint),
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
            mint: pubkey!(community_mint),
            from: pubkey!(token),
            amount: 1,
            program: program
          ),
          Governance.create_token_governance(
            payer: pubkey!(payer),
            owner: pubkey!(payer),
            authority: pubkey!(payer),
            realm: realm,
            mint: pubkey!(community_mint),
            governed: pubkey!(governed),
            token_owner: pubkey!(payer),
            program: program,
            config: [threshold: {:yes, 60}, duration: :timer.hours(3)]
          )
        ],
        signers: [payer, community_mint, token, governed],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          deposit_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      # TODO add assertions here
    end
  end
end
