defmodule Solana.SPL.TokenSwapTest do
  use ExUnit.Case, async: true

  import Solana.SPL.TestHelpers, only: [create_payer: 3, keypairs: 1]
  import Solana, only: [pubkey!: 1]

  alias Solana.{Key, RPC, Transaction, SPL.Token, SPL.TokenSwap}

  @fees [
    trade_fee: {25, 10000},
    owner_trade_fee: {5, 10000},
    owner_withdraw_fee: {1, 6},
    host_fee: {2, 10}
  ]

  setup_all do
    {:ok, tracker} = RPC.Tracker.start_link(network: "localhost", t: 100)
    client = RPC.client(network: "localhost")
    {:ok, payer} = create_payer(tracker, client, commitment: "confirmed")

    [tracker: tracker, client: client, payer: payer]
  end

  describe "init/1" do
    test "initializes a token swap account", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, nonce} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = [mint_a, mint_b] = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          )
        ],
        signers: [payer, pool_mint, fee_account, pool],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: 1_000_000
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      # setup is done, now create the swap
      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: {:price, 1}
            )
          )
        ],
        signers: [payer, swap],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      assert {:ok, swap_info} =
               RPC.send(
                 client,
                 RPC.Request.get_account_info(pubkey!(swap),
                   commitment: "confirmed",
                   encoding: "jsonParsed"
                 )
               )

      assert %{
               token_a: pubkey!(token_a),
               token_b: pubkey!(token_b),
               trade_fee: @fees[:trade_fee],
               owner_trade_fee: @fees[:owner_trade_fee],
               owner_withdraw_fee: @fees[:owner_withdraw_fee],
               host_fee: @fees[:host_fee],
               pool_mint: pubkey!(pool_mint),
               mint_a: pubkey!(mint_a),
               mint_b: pubkey!(mint_b),
               fee_account: pubkey!(fee_account),
               version: 1,
               initialized?: true,
               bump_seed: nonce,
               curve: {:price, 1}
             } == TokenSwap.from_account_info(swap_info)
    end
  end

  describe "deposit_all/1" do
    test "can deposit both `A` and `B` tokens", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, _} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)
      [user_authority, user_a, user_b, user_pool] = keypairs(4)

      amount_to_mint = 1_000_000
      amount_to_deposit = 10_000
      expected_pool_amount = 10_000_000

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(user_pool)
          )
        ],
        signers: [payer, pool_mint, fee_account, pool, user_pool],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_mint
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      user_tokens_tx = %Transaction{
        instructions:
          Enum.map(Enum.zip(mints, [user_a, user_b]), fn {mint, user} ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: pubkey!(owner),
                new: pubkey!(user)
              ),
              Token.mint_to(
                token: pubkey!(user),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_deposit
              ),
              Token.approve(
                source: pubkey!(user),
                delegate: pubkey!(user_authority),
                owner: pubkey!(owner),
                amount: amount_to_deposit
              )
            ]
          end),
        signers: [payer, owner, user_a, user_b],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, user_tokens_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: :product
            )
          ),
          TokenSwap.deposit_all(
            swap: pubkey!(swap),
            authority: authority,
            user_a: pubkey!(user_a),
            user_b: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            amount_a: amount_to_deposit,
            amount_b: amount_to_deposit,
            amount_pool: expected_pool_amount
          )
        ],
        signers: [payer, swap, user_authority],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      check_requests =
        [user_a, user_b, user_pool, token_a, token_b]
        |> Enum.map(fn pair ->
          RPC.Request.get_account_info(pubkey!(pair),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        end)

      [user_a_info, user_b_info, user_pool_info, token_a_info, token_b_info] =
        client
        |> RPC.send(check_requests)
        |> Enum.map(fn {:ok, info} -> Token.from_account_info(info) end)

      Enum.each([user_a_info, user_b_info], &assert(&1.amount == 0))

      Enum.each(
        [token_a_info, token_b_info],
        &assert(&1.amount == amount_to_mint + amount_to_deposit)
      )

      assert user_pool_info.amount == expected_pool_amount
    end
  end

  describe "withdraw_all/1" do
    test "can withdraw both `A` and `B` tokens", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, _} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)
      [user_authority, user_a, user_b, user_pool] = keypairs(4)

      amount_to_mint = 1_000_000
      amount_to_deposit = 10_000
      expected_pool_amount = 10_000_000
      # withdraw fee is 1/6
      fee_amount = div(expected_pool_amount, 6)
      expected_withdraw_fee_amount = div(amount_to_deposit, 6) + 1
      amount_to_withdraw = div(amount_to_deposit * 5, 6)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(user_pool)
          ),
          Token.approve(
            source: pubkey!(user_pool),
            delegate: pubkey!(user_authority),
            owner: pubkey!(owner),
            amount: expected_pool_amount
          )
        ],
        signers: [payer, pool_mint, fee_account, pool, user_pool, owner],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_mint
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      user_tokens_tx = %Transaction{
        instructions:
          Enum.map(Enum.zip(mints, [user_a, user_b]), fn {mint, user} ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: pubkey!(owner),
                new: pubkey!(user)
              ),
              Token.mint_to(
                token: pubkey!(user),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_deposit
              ),
              Token.approve(
                source: pubkey!(user),
                delegate: pubkey!(user_authority),
                owner: pubkey!(owner),
                amount: amount_to_deposit
              )
            ]
          end),
        signers: [payer, owner, user_a, user_b],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, user_tokens_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: :product
            )
          ),
          TokenSwap.deposit_all(
            swap: pubkey!(swap),
            authority: authority,
            user_a: pubkey!(user_a),
            user_b: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            amount_a: amount_to_deposit,
            amount_b: amount_to_deposit,
            amount_pool: expected_pool_amount
          ),
          TokenSwap.withdraw_all(
            swap: pubkey!(swap),
            authority: authority,
            user_a: pubkey!(user_a),
            user_b: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            fee_account: pubkey!(fee_account),
            amount_a: amount_to_withdraw,
            amount_b: amount_to_withdraw,
            amount_pool: expected_pool_amount
          )
        ],
        signers: [payer, swap, user_authority],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      check_requests =
        [fee_account, user_a, user_b, user_pool, token_a, token_b]
        |> Enum.map(fn pair ->
          RPC.Request.get_account_info(pubkey!(pair),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        end)

      [fee_info, user_a_info, user_b_info, user_pool_info, token_a_info, token_b_info] =
        client
        |> RPC.send(check_requests)
        |> Enum.map(fn {:ok, info} -> Token.from_account_info(info) end)

      Enum.each([user_a_info, user_b_info], &assert(&1.amount == amount_to_withdraw))

      Enum.each([token_a_info, token_b_info], fn %{amount: amount} ->
        assert amount == amount_to_mint + expected_withdraw_fee_amount
      end)

      assert user_pool_info.amount == 0
      assert fee_info.amount == fee_amount
    end
  end

  describe "swap/1" do
    test "can swap `A` and `B` tokens", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, _} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)
      [user_authority, user_a, user_b, user_pool] = keypairs(4)

      amount_to_mint = 1_000_000
      swap_in = 100_000

      # https://github.com/solana-labs/solana-program-library/blob/287c3bedaf5ee5b49983495fd2826e84d35bc561/token-swap/js/cli/token-swap-test.ts#L56-L60
      swap_out = 90_661
      swap_fee = 22_273

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(user_pool)
          )
        ],
        signers: [payer, pool_mint, fee_account, pool, user_pool],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_mint
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      user_tokens_tx = %Transaction{
        instructions:
          Enum.map(Enum.zip(mints, [user_a, user_b]), fn {mint, user} ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: pubkey!(owner),
                new: pubkey!(user)
              ),
              Token.mint_to(
                token: pubkey!(user),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: swap_in
              ),
              Token.approve(
                source: pubkey!(user),
                delegate: pubkey!(user_authority),
                owner: pubkey!(owner),
                amount: swap_in
              )
            ]
          end),
        signers: [payer, owner, user_a, user_b],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, user_tokens_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: :product
            )
          ),
          TokenSwap.swap(
            swap: pubkey!(swap),
            authority: authority,
            user_source: pubkey!(user_a),
            swap_source: pubkey!(token_a),
            user_destination: pubkey!(user_b),
            swap_destination: pubkey!(token_b),
            pool_mint: pubkey!(pool_mint),
            fee_account: pubkey!(fee_account),
            user_authority: pubkey!(user_authority),
            amount: swap_in,
            minimum_return: 90_000
          )
        ],
        signers: [payer, swap, user_authority],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      check_requests =
        [user_a, user_b, token_a, token_b, fee_account]
        |> Enum.map(fn pair ->
          RPC.Request.get_account_info(pubkey!(pair),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        end)

      [user_a_info, user_b_info, token_a_info, token_b_info, fee_info] =
        client
        |> RPC.send(check_requests)
        |> Enum.map(fn {:ok, info} -> Token.from_account_info(info) end)

      assert user_a_info.amount == 0
      assert user_b_info.amount == swap_in + swap_out
      assert token_a_info.amount == amount_to_mint + swap_in
      assert token_b_info.amount == amount_to_mint - swap_out
      assert fee_info.amount == swap_fee
    end
  end

  defp trade_to_pool(source, swap, pool) do
    {n, d} = @fees[:trade_fee]
    fee = source / 2 * n / d
    root = :math.sqrt((source - fee) / swap + 1)
    trunc(pool * (root - 1))
  end

  describe "deposit/1" do
    test "can deposit `A` or `B` tokens", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, _} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)
      [user_authority, user_a, user_b, user_pool] = keypairs(4)

      pool_supply = 1_000_000_000
      amount_to_mint = 1_000_000
      amount_to_deposit = 10_000
      expected_pool_amount = trade_to_pool(amount_to_deposit, amount_to_mint, pool_supply)

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(user_pool)
          )
        ],
        signers: [payer, pool_mint, fee_account, pool, user_pool],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_mint
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      user_tokens_tx = %Transaction{
        instructions:
          Enum.map(Enum.zip(mints, [user_a, user_b]), fn {mint, user} ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: pubkey!(owner),
                new: pubkey!(user)
              ),
              Token.mint_to(
                token: pubkey!(user),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_deposit
              ),
              Token.approve(
                source: pubkey!(user),
                delegate: pubkey!(user_authority),
                owner: pubkey!(owner),
                amount: amount_to_deposit
              )
            ]
          end),
        signers: [payer, owner, user_a, user_b],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, user_tokens_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: :product
            )
          ),
          TokenSwap.deposit(
            swap: pubkey!(swap),
            authority: authority,
            user_token: pubkey!(user_a),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            amount: amount_to_deposit,
            amount_pool: expected_pool_amount
          ),
          TokenSwap.deposit(
            swap: pubkey!(swap),
            authority: authority,
            user_token: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            amount: amount_to_deposit,
            amount_pool: expected_pool_amount
          )
        ],
        signers: [payer, swap, user_authority],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      check_requests =
        [user_a, user_b, user_pool, token_a, token_b]
        |> Enum.map(fn pair ->
          RPC.Request.get_account_info(pubkey!(pair),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        end)

      [user_a_info, user_b_info, user_pool_info, token_a_info, token_b_info] =
        client
        |> RPC.send(check_requests)
        |> Enum.map(fn {:ok, info} -> Token.from_account_info(info) end)

      Enum.each([user_a_info, user_b_info], &assert(&1.amount == 0))

      Enum.each(
        [token_a_info, token_b_info],
        &assert(&1.amount == amount_to_mint + amount_to_deposit)
      )

      assert user_pool_info.amount >= expected_pool_amount * 2
    end
  end

  describe "withdraw/1" do
    test "can withdraw `A` or `B` tokens", %{client: client, payer: payer, tracker: tracker} do
      [swap, owner, pool_mint, pool, fee_account] = keypairs(5)
      {:ok, authority, _} = Key.find_address([pubkey!(swap)], TokenSwap.id())
      mints = keypairs(2)
      tokens = [token_a, token_b] = keypairs(2)
      [user_authority, user_a, user_b, user_pool] = keypairs(4)

      pool_supply = 1_000_000_000
      amount_to_mint = 1_000_000
      amount_to_deposit = 10_000
      amount_to_withdraw = 5_000
      expected_pool_amount = 10_000_000
      # withdraw fee is 1/6
      expected_pool_withdraw =
        div(
          trade_to_pool(amount_to_withdraw, amount_to_mint - amount_to_withdraw, pool_supply) * 7,
          6
        )

      tx_reqs = [
        RPC.Request.get_recent_blockhash(commitment: "confirmed")
        | Enum.map([Token.Mint, Token, TokenSwap], fn mod ->
            RPC.Request.get_minimum_balance_for_rent_exemption(mod.byte_size(),
              commitment: "confirmed"
            )
          end)
      ]

      [%{"blockhash" => blockhash}, mint_balance, token_balance, swap_balance] =
        client
        |> RPC.send(tx_reqs)
        |> Enum.map(fn {:ok, result} -> result end)

      create_pool_accounts_tx = %Transaction{
        instructions: [
          Token.Mint.init(
            balance: mint_balance,
            payer: pubkey!(payer),
            authority: authority,
            new: pubkey!(pool_mint),
            decimals: 0
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(pool)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(fee_account)
          ),
          Token.init(
            balance: token_balance,
            payer: pubkey!(payer),
            mint: pubkey!(pool_mint),
            owner: pubkey!(owner),
            new: pubkey!(user_pool)
          ),
          Token.approve(
            source: pubkey!(user_pool),
            delegate: pubkey!(user_authority),
            owner: pubkey!(owner),
            amount: expected_pool_withdraw * 2
          )
        ],
        signers: [payer, pool_mint, fee_account, pool, user_pool, owner],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      pairs = Enum.zip(mints, tokens)

      create_tokens_tx = %Transaction{
        instructions:
          Enum.map(pairs, fn {mint, token} ->
            [
              Token.Mint.init(
                balance: mint_balance,
                payer: pubkey!(payer),
                authority: pubkey!(owner),
                new: pubkey!(mint),
                decimals: 0
              ),
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: authority,
                new: pubkey!(token)
              ),
              Token.mint_to(
                token: pubkey!(token),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_mint
              )
            ]
          end),
        signers: List.flatten([payer, owner, mints, tokens]),
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signatures} =
        RPC.send_and_confirm(
          client,
          tracker,
          [create_pool_accounts_tx, create_tokens_tx],
          commitment: "confirmed",
          timeout: 1_000
        )

      user_tokens_tx = %Transaction{
        instructions:
          Enum.map(Enum.zip(mints, [user_a, user_b]), fn {mint, user} ->
            [
              Token.init(
                balance: token_balance,
                payer: pubkey!(payer),
                mint: pubkey!(mint),
                owner: pubkey!(owner),
                new: pubkey!(user)
              ),
              Token.mint_to(
                token: pubkey!(user),
                mint: pubkey!(mint),
                authority: pubkey!(owner),
                amount: amount_to_deposit
              ),
              Token.approve(
                source: pubkey!(user),
                delegate: pubkey!(user_authority),
                owner: pubkey!(owner),
                amount: amount_to_deposit
              )
            ]
          end),
        signers: [payer, owner, user_a, user_b],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, user_tokens_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      swap_tx = %Transaction{
        instructions: [
          TokenSwap.init(
            Keyword.merge(@fees,
              payer: pubkey!(payer),
              balance: swap_balance,
              authority: authority,
              new: pubkey!(swap),
              token_a: pubkey!(token_a),
              token_b: pubkey!(token_b),
              pool: pubkey!(pool),
              pool_mint: pubkey!(pool_mint),
              fee_account: pubkey!(fee_account),
              curve: :product
            )
          ),
          TokenSwap.deposit_all(
            swap: pubkey!(swap),
            authority: authority,
            user_a: pubkey!(user_a),
            user_b: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            amount_a: amount_to_deposit,
            amount_b: amount_to_deposit,
            amount_pool: expected_pool_amount
          ),
          TokenSwap.withdraw(
            swap: pubkey!(swap),
            authority: authority,
            user_token: pubkey!(user_a),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            fee_account: pubkey!(fee_account),
            amount: amount_to_withdraw,
            amount_pool: expected_pool_withdraw
          ),
          TokenSwap.withdraw(
            swap: pubkey!(swap),
            authority: authority,
            user_token: pubkey!(user_b),
            swap_a: pubkey!(token_a),
            swap_b: pubkey!(token_b),
            user_pool: pubkey!(user_pool),
            pool_mint: pubkey!(pool_mint),
            user_authority: pubkey!(user_authority),
            fee_account: pubkey!(fee_account),
            amount: amount_to_withdraw,
            amount_pool: expected_pool_withdraw
          )
        ],
        signers: [payer, swap, user_authority],
        blockhash: blockhash,
        payer: pubkey!(payer)
      }

      {:ok, _signature} =
        RPC.send_and_confirm(client, tracker, swap_tx,
          commitment: "confirmed",
          timeout: 1_000
        )

      check_requests =
        [user_a, user_b, user_pool, token_a, token_b]
        |> Enum.map(fn pair ->
          RPC.Request.get_account_info(pubkey!(pair),
            commitment: "confirmed",
            encoding: "jsonParsed"
          )
        end)

      [user_a_info, user_b_info, user_pool_info, token_a_info, token_b_info] =
        client
        |> RPC.send(check_requests)
        |> Enum.map(fn {:ok, info} -> Token.from_account_info(info) end)

      Enum.each([user_a_info, user_b_info], &assert(&1.amount == amount_to_withdraw))

      Enum.each([token_a_info, token_b_info], fn %{amount: amount} ->
        assert amount == amount_to_mint + amount_to_deposit - amount_to_withdraw
      end)

      assert user_pool_info.amount >= expected_pool_amount - expected_pool_withdraw * 2
    end
  end
end
