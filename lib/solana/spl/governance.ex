defmodule Solana.SPL.Governance do
  @moduledoc """
  Functions for interacting with the [SPL Governance
  program](https://github.com/solana-labs/solana-program-library/tree/master/governance#readme).

  The governance program aims to provide core building blocks for creating
  Decentralized Autonomous Organizations (DAOs).
  """
  alias Solana.{SPL.Token, Key, Instruction, Account, SystemProgram}
  import Solana.Helpers

  @mint_max_vote_weight_sources [:fraction, :absolute]

  @doc """
  The Governance program's default instance ID. Organizations can also deploy
  their own custom instance if they wish.
  """
  def id(), do: Solana.pubkey!("GovER5Lthms3bLBqWub97yVrMmEogzX7xNjdXpPPCVZw")

  @doc """
  The governance program's test instance ID. This can be used to set up test DAOs.
  """
  def test_id(), do: Solana.pubkey!("GTesTBiEWE32WHXXE2S4XbZvA5CrEc4xs6ZgRe895dP")

  @doc """
  Finds a token holding address for the given community/council `mint`. Should
  have the seeds: `['governance', realm, mint]`.
  """
  @spec find_holding_address(program :: Key.t(), realm :: Key.t(), mint :: Key.t()) :: Key.t()
  def find_holding_address(program, realm, mint) do
    case Key.find_address(["governance", realm, mint], program) do
      {:ok, address, _} -> address
      error -> error
    end
  end

  @doc """
  Finds the realm config address for the given `realm`. Should have the seeds:
  `['realm-config', realm]`.
  """
  @spec find_realm_config_address(program :: Key.t(), realm :: Key.t()) :: Key.t()
  def find_realm_config_address(program, realm) do
    case Key.find_address(["realm-config", realm], program) do
      {:ok, address, _} -> address
      error -> error
    end
  end

  @doc """
  Finds the token owner record address for the given `realm`, `mint`, and
  `owner`. Should have the seeds: `['governance', realm, mint, owner]`.
  """
  @spec find_owner_record_address(
          program :: Key.t(),
          realm :: Key.t(),
          mint :: Key.t(),
          owner :: Key.t()
        ) :: Key.t()
  def find_owner_record_address(program, realm, mint, owner) do
    case Key.find_address(["governance", realm, mint, owner], program) do
      {:ok, address, _} -> address
      error -> error
    end
  end

  @create_realm_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the `new` realm account's creation."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the authority account for the `new` realm."
    ],
    new: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: """
      Public key of the newly-created realm account. Should be a program-derived
      address with the seeds `['governance', name]`.
      """
    ],
    community_mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Community token mint for the `new` realm."
    ],
    council_mint: [
      type: {:custom, Key, :check, []},
      doc: "Community token mint for the `new` realm."
    ],
    addin: [
      type: {:custom, Key, :check, []},
      doc: "Community voter weight add-in program ID."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    name: [
      type: :string,
      required: true,
      doc: "The name of the `new` realm to create."
    ],
    max_vote_weight_source: [
      type: {:custom, __MODULE__, :validate_vote_weight_source, []},
      required: true,
      doc: """
      The source of max vote weight used for voting. Values below 100%
      mint supply can be used when the governing token is fully minted but not
      distributed yet.
      """
    ],
    minimum: [
      type: :non_neg_integer,
      required: true,
      doc: "Minimum number of community tokens a user must hold to create a governance."
    ]
  ]
  @doc """
  Generates instructions which create a new realm.

  ## Options

  #{NimbleOptions.docs(@create_realm_schema)}
  """
  def create_realm(opts) do
    case validate(opts, @create_realm_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts:
            List.flatten([
              create_realm_accounts(Map.pop(params, :council_mint)),
              %Account{
                key: find_realm_config_address(params.program, params.new),
                writable?: true
              }
              | maybe_add_voter_weight_addin(params)
            ]),
          data:
            Instruction.encode_data([
              0,
              {byte_size(params.name), 32},
              params.name,
              if(Map.has_key?(params, :council_mint), do: 1, else: 0),
              {params.minimum, 64},
              Enum.find_index(
                @mint_max_vote_weight_sources,
                &(&1 == elem(params.max_vote_weight_source, 0))
              ),
              {elem(params.max_vote_weight_source, 1), 64},
              if(Map.has_key?(params, :addin), do: 1, else: 0)
            ])
        }

      error ->
        error
    end
  end

  defp create_realm_accounts({nil, %{new: new, community_mint: mint} = params}) do
    [
      %Account{key: new, writable?: true},
      %Account{key: params.authority},
      %Account{key: mint},
      %Account{key: find_holding_address(params.program, new, mint), writable?: true},
      %Account{key: params.payer, signer?: true},
      %Account{key: SystemProgram.id()},
      %Account{key: Token.id()},
      %Account{key: Solana.rent()}
    ]
  end

  defp create_realm_accounts({mint, params}) do
    List.flatten([
      create_realm_accounts({nil, params}),
      %Account{key: mint},
      %Account{key: find_holding_address(params.program, params.new, mint), writable?: true}
    ])
  end

  defp maybe_add_voter_weight_addin(%{addin: addin}) do
    [%Account{key: addin}]
  end

  defp maybe_add_voter_weight_addin(_), do: []

  def validate_vote_weight_source({type, value})
      when type in @mint_max_vote_weight_sources and is_integer(value) and value > 0 do
    {:ok, {type, value}}
  end

  def validate_vote_weight_source(_), do: {:error, "invalid max vote weight source"}

  @deposit_schema [
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The `from` token account's owner."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The `from` token account's transfer authority."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm to deposit user tokens into."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the user wishes to deposit."
    ],
    from: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The user's token account."
    ],
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: """
      The account which will pay to create the user's token owner record account
      (if necessary).
      """
    ],
    amount: [
      type: :pos_integer,
      required: true,
      doc: "The number of tokens to transfer."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions which deposit governing tokens -- community or council
  -- to the given `realm`. This establishes a user's voter weight to be used when
  voting within the `realm`.

  Note: If a subsequent (top up) deposit is made, the user's vote weights on
  active proposals *won't* be updated automatically. To do this, the user must
  relinquish their votes and vote again.

  ## Options

  #{NimbleOptions.docs(@deposit_schema)}
  """
  def deposit(opts) do
    case validate(opts, @deposit_schema) do
      {:ok, %{program: program, realm: realm, mint: mint, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{key: find_holding_address(program, realm, mint), writable?: true},
            %Account{key: params.from, writable?: true},
            %Account{key: owner, signer?: true},
            %Account{key: params.authority, signer?: true},
            %Account{
              key: find_owner_record_address(program, realm, mint, owner),
              writable?: true
            },
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Token.id()},
            %Account{key: Solana.rent()}
          ],
          data: Instruction.encode_data([1, {params.amount, 64}])
        }

      error ->
        error
    end
  end

  @withdraw_schema [
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The `to` token account's owner."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm to withdraw user tokens from."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the user wishes to withdraw."
    ],
    to: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The user's token account. All tokens will be transferred to this account."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions which withdraw governing tokens -- community or council
  -- from the given `realm`. This downgrades a user's voter weight within the
  `realm`.

  Note: It's only possible to withdraw tokens if the user doesn't have any
  outstanding active votes. Otherwise, the user needs to relinquish those
  votes before withdrawing their tokens.

  ## Options

  #{NimbleOptions.docs(@withdraw_schema)}
  """
  def withdraw(opts) do
    case validate(opts, @withdraw_schema) do
      {:ok, %{program: program, realm: realm, mint: mint, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{key: find_holding_address(program, realm, mint), writable?: true},
            %Account{key: params.to, writable?: true},
            %Account{key: owner, signer?: true},
            %Account{
              key: find_owner_record_address(program, realm, mint, owner),
              writable?: true
            },
            %Account{key: Token.id()}
          ],
          data: Instruction.encode_data([2])
        }

      error ->
        error
    end
  end
end
