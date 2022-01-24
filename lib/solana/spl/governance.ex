defmodule Solana.SPL.Governance do
  @moduledoc """
  Functions for interacting with the [SPL Governance
  program](https://github.com/solana-labs/solana-program-library/tree/master/governance#readme).

  The governance program aims to provide core building blocks for creating
  Decentralized Autonomous Organizations (DAOs).
  """
  alias Solana.{SPL.Token, Key, Instruction, Account, SystemProgram}
  import Solana.Helpers

  @max_vote_weight_sources [:fraction, :absolute]
  @vote_weight_sources [:deposit, :snapshot]
  @vote_thresholds [:yes, :quorum]

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
    maybe_return_found_address(["governance", realm, mint], program)
  end

  @doc """
  Finds the realm config address for the given `realm`. Should have the seeds:
  `['realm-config', realm]`.
  """
  @spec find_realm_config_address(program :: Key.t(), realm :: Key.t()) :: Key.t()
  def find_realm_config_address(program, realm) do
    maybe_return_found_address(["realm-config", realm], program)
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
    maybe_return_found_address(["governance", realm, mint, owner], program)
  end

  @doc """
  Finds the account governance address for the given `realm` and `account`.
  Should have the seeds: `['account-governance', realm, account]`.
  """
  @spec find_account_governance_address(program :: Key.t(), realm :: Key.t(), account :: Key.t()) ::
          Key.t()
  def find_account_governance_address(program, realm, account) do
    maybe_return_found_address(["account-governance", realm, account], program)
  end

  @doc """
  Finds the program governance address for the given `realm` and `governed`
  program. Should have the seeds: `['program-governance', realm, governed]`.
  """
  @spec find_program_governance_address(program :: Key.t(), realm :: Key.t(), governed :: Key.t()) ::
          Key.t()
  def find_program_governance_address(program, realm, governed) do
    maybe_return_found_address(["program-governance", realm, governed], program)
  end

  @doc """
  Finds the mint governance address for the given `realm` and `mint`.
  Should have the seeds: `['mint-governance', realm, mint]`.
  """
  @spec find_mint_governance_address(program :: Key.t(), realm :: Key.t(), mint :: Key.t()) ::
          Key.t()
  def find_mint_governance_address(program, realm, mint) do
    maybe_return_found_address(["mint-governance", realm, mint], program)
  end

  @doc """
  Finds the token governance address for the given `realm` and `token`.
  Should have the seeds: `['token-governance', realm, token]`.
  """
  @spec find_token_governance_address(program :: Key.t(), realm :: Key.t(), token :: Key.t()) ::
          Key.t()
  def find_token_governance_address(program, realm, token) do
    maybe_return_found_address(["token-governance", realm, token], program)
  end

  defp maybe_return_found_address(seeds, program) do
    case Key.find_address(seeds, program) do
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
      type: {:custom, __MODULE__, :validate_max_vote_weight_source, []},
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
                @max_vote_weight_sources,
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

  @doc false
  def validate_max_vote_weight_source({type, value})
      when type in @max_vote_weight_sources and is_integer(value) and value > 0 do
    {:ok, {type, value}}
  end

  def validate_max_vote_weight_source(_), do: {:error, "invalid max vote weight source"}

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
  -- to the given `realm`.

  This establishes a user's voter weight to be used when voting within the
  `realm`.

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
  -- from the given `realm`.

  This downgrades a user's voter weight within the `realm`.

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

  @delegate_schema [
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current non-delegated holder of voting rights within the `realm`."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm for which the `owner` will delegate voter rights."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token for which the `owner` will delegate voter rights."
    ],
    to: [
      type: {:custom, Key, :check, []},
      doc: """
      The account which will receive voter rights from the `owner` in the given
      `realm`. **Not including this argument will rescind the current delegate's
      voting rights.**
      """
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions which set the new governance delegate for an ownership
  account within the given `realm` and `mint`.

  The delegate can vote or create Proposals on behalf of the `owner`.

  Note: Delegating voting rights doesn't take them away from the original owner.

  ## Options

  #{NimbleOptions.docs(@delegate_schema)}
  """
  def delegate(opts) do
    case validate(opts, @delegate_schema) do
      {:ok, %{program: program, realm: realm, mint: mint, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: owner, signer?: true},
            %Account{
              key: find_owner_record_address(program, realm, mint, owner),
              writable?: true
            }
          ],
          data: Instruction.encode_data([3 | delegate_data(params)])
        }

      error ->
        error
    end
  end

  defp delegate_data(%{to: delegate}), do: [1, delegate]
  defp delegate_data(_), do: [0]

  @governance_config_schema [
    threshold: [
      type: {:custom, __MODULE__, :validate_threshold, []},
      required: true,
      doc: "The type of vote threshold used to resolve a Proposal vote."
    ],
    vote_weight_source: [
      type: {:in, @vote_weight_sources},
      default: :deposit,
      doc: "The source of vote weight for voters."
    ],
    minimum_community: [
      type: :non_neg_integer,
      default: 1,
      doc: "The minimum number of community tokens an owner must have to create a proposal."
    ],
    minimum_council: [
      type: :non_neg_integer,
      default: 1,
      doc: "The minimum number of council tokens an owner must have to create a proposal."
    ],
    duration: [
      type: :non_neg_integer,
      required: true,
      doc: "Time limit (in seconds) for a proposal to be open for voting."
    ],
    cooldown: [
      type: :non_neg_integer,
      default: 0,
      doc: """
      The time period (in seconds) within which a proposal can still be cancelled after voting has
      ended.
      """
    ],
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: """
      Minimum wait time (in seconds) after a proposal has been voted on before an instruction can
      be executed.
      """
    ]
  ]

  @doc false
  def validate_threshold({type, pct}) when type in @vote_thresholds and pct in 1..100 do
    {:ok, {type, pct}}
  end

  def validate_threshold(threshold) do
    {:error, "expected {:yes, percentage} or {:quorum, percentage}, got: #{inspect(threshold)}"}
  end

  @create_account_governance_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new Account Governance account's creation."
    ],
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the token owner which will govern the account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm the created Governance belongs to."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the `owner` will use to create the governance account."
    ],
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will be goverened by the newly created governance."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    voter_weight_record: [
      type: {:custom, Key, :check, []},
      doc: "Public key of the voter weight record account."
    ],
    config: [
      type: {:custom, Solana.Helpers, :validate, [@governance_config_schema]},
      required: true,
      doc: """
      The desired governance configuration.

      ### Options

      #{NimbleOptions.docs(@governance_config_schema)}
      """
    ]
  ]
  @doc """
  Generates instructions which create an Account Governance account, used to
  govern an arbitrary account.

  ## Options

  #{NimbleOptions.docs(@create_account_governance_schema)}
  """
  def create_account_governance(opts) do
    case validate(opts, @create_account_governance_schema) do
      {:ok, %{program: program, realm: realm, governed: governed, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_account_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed},
            %Account{key: find_owner_record_address(program, realm, params.mint, owner)},
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: params.authority, signer?: true}
            | voter_weight_accounts(params)
          ],
          data: Instruction.encode_data([4 | serialize_config(params.config)])
        }

      error ->
        error
    end
  end

  @create_program_governance_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new Account Governance account's creation."
    ],
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the token owner which will govern the account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm the created Governance belongs to."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the `owner` will use to create the governance account."
    ],
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The program which will be goverened by the newly created governance."
    ],
    upgrade_authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current upgrade authority of the `goverened` program."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    voter_weight_record: [
      type: {:custom, Key, :check, []},
      doc: "Public key of the voter weight record account."
    ],
    transfer_upgrade_authority?: [
      type: :boolean,
      default: false,
      doc: """
      Whether or not the `governed` program's upgrade authority should be
      transferred to the governance PDA. This can also be done later.
      """
    ],
    config: [
      type: {:custom, Solana.Helpers, :validate, [@governance_config_schema]},
      required: true,
      doc: """
      The desired governance configuration.

      ### Options

      #{NimbleOptions.docs(@governance_config_schema)}
      """
    ]
  ]
  @doc """
  Generates instructions which create an Program Governance account, used to
  govern an upgradable Solana program.

  ## Options

  #{NimbleOptions.docs(@create_program_governance_schema)}
  """
  def create_program_governance(opts) do
    case validate(opts, @create_program_governance_schema) do
      {:ok, %{program: program, realm: realm, governed: governed, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_program_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed},
            %Account{key: find_program_data(program), writable?: true},
            %Account{key: params.upgrade_authority, signer?: true},
            %Account{key: find_owner_record_address(program, realm, params.mint, owner)},
            %Account{key: params.payer, signer?: true},
            %Account{key: bpf_loader()},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: params.authority, signer?: true}
            | voter_weight_accounts(params)
          ],
          data:
            Instruction.encode_data(
              List.flatten([
                5,
                serialize_config(params.config),
                if(params.transfer_upgrade_authority?, do: 1, else: 0)
              ])
            )
        }

      error ->
        error
    end
  end

  defp bpf_loader(), do: Solana.pubkey!("BPFLoaderUpgradeab1e11111111111111111111111")
  defp find_program_data(program), do: maybe_return_found_address([program], bpf_loader())

  @create_mint_governance_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new Account Governance account's creation."
    ],
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the token owner which will govern the account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm the created Governance belongs to."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the `owner` will use to create the governance account."
    ],
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint which will be goverened by the newly created governance."
    ],
    mint_authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current mint authority of the `goverened` mint."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    voter_weight_record: [
      type: {:custom, Key, :check, []},
      doc: "Public key of the voter weight record account."
    ],
    config: [
      type: {:custom, Solana.Helpers, :validate, [@governance_config_schema]},
      required: true,
      doc: """
      The desired governance configuration.

      ### Options

      #{NimbleOptions.docs(@governance_config_schema)}
      """
    ],
    transfer_mint_authority?: [
      type: :boolean,
      default: false,
      doc: """
      Whether or not the `governed` mint's authority should be transferred to
      the governance PDA. This can also be done later.
      """
    ]
  ]
  @doc """
  Generates instructions which create an Mint Governance account, used to
  govern a token mint.

  ## Options

  #{NimbleOptions.docs(@create_mint_governance_schema)}
  """
  def create_mint_governance(opts) do
    case validate(opts, @create_mint_governance_schema) do
      {:ok, %{program: program, realm: realm, governed: governed, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_mint_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed, writable?: true},
            %Account{key: params.mint_authority, signer?: true},
            %Account{key: find_owner_record_address(program, realm, params.mint, owner)},
            %Account{key: params.payer, signer?: true},
            %Account{key: Token.id()},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: params.authority, signer?: true}
            | voter_weight_accounts(params)
          ],
          data:
            Instruction.encode_data(
              List.flatten([
                17,
                serialize_config(params.config),
                if(params.transfer_mint_authority?, do: 1, else: 0)
              ])
            )
        }
      error ->
        error
    end
  end

  @create_token_governance_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new Account Governance account's creation."
    ],
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the token owner which will govern the account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm the created Governance belongs to."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint for the token the `owner` will use to create the governance account."
    ],
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will be goverened by the newly created governance."
    ],
    token_owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current owner of the `goverened` token account."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    voter_weight_record: [
      type: {:custom, Key, :check, []},
      doc: "Public key of the voter weight record account."
    ],
    config: [
      type: {:custom, Solana.Helpers, :validate, [@governance_config_schema]},
      required: true,
      doc: """
      The desired governance configuration.

      ### Options

      #{NimbleOptions.docs(@governance_config_schema)}
      """
    ],
    transfer_token_owner?: [
      type: :boolean,
      default: false,
      doc: """
      Whether or not the `governed` token's ownership should be transferred to
      the governance PDA. This can also be done later.
      """
    ]
  ]
  @doc """
  Generates instructions which create a Token Governance account, used to
  govern a token account.

  ## Options

  #{NimbleOptions.docs(@create_token_governance_schema)}
  """
  def create_token_governance(opts) do
    case validate(opts, @create_token_governance_schema) do
      {:ok, %{program: program, realm: realm, governed: governed, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_token_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed, writable?: true},
            %Account{key: params.token_owner, signer?: true},
            %Account{key: find_owner_record_address(program, realm, params.mint, owner)},
            %Account{key: params.payer, signer?: true},
            %Account{key: Token.id()},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: params.authority, signer?: true}
            | voter_weight_accounts(params)
          ],
          data:
            Instruction.encode_data(
              List.flatten([
                18,
                serialize_config(params.config),
                if(params.transfer_token_owner?, do: 1, else: 0)
              ])
            )
        }
      error ->
        error
    end
  end

  defp serialize_config(config) do
    [
      Enum.find_index(@vote_thresholds, &(&1 == elem(config.threshold, 0))),
      elem(config.threshold, 1),
      {config.minimum_community, 64},
      {config.delay, 32},
      {config.duration, 32},
      Enum.find_index(@vote_weight_sources, &(&1 == config.vote_weight_source)),
      {config.cooldown, 32},
      {config.minimum_council, 64}
    ]
  end

  defp voter_weight_accounts(%{voter_weight_record: record, realm: realm, program: program}) do
    [%Account{key: find_realm_config_address(program, realm)}, %Account{key: record}]
  end

  defp voter_weight_accounts(_), do: []
end
