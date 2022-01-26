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
  Finds the realm address for the given `name`. Should have the seeds `['governance', name]`
  """
  @spec find_realm_address(program :: Key.t(), name :: String.t()) :: Key.t()
  def find_realm_address(program, name) do
    maybe_return_found_address(["governance", name], program)
  end

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
  Finds the vote record address for the given `proposal` and `owner_record`.
  Should have the seeds: `['governance', proposal, owner_record]`.
  """
  @spec find_vote_record_address(
          program :: Key.t(),
          proposal :: Key.t(),
          owner_record :: Key.t()
        ) :: Key.t()
  def find_vote_record_address(program, proposal, owner_record) do
    maybe_return_found_address(["governance", proposal, owner_record], program)
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

  @doc """
  Finds the `governance` proposal address for the given `mint` and `index`.
  Should have the seeds: `['governance', governance, mint, index]`.
  """
  @spec find_proposal_address(
          program :: Key.t(),
          governance :: Key.t(),
          mint :: Key.t(),
          index :: integer
        ) ::
          Key.t()
  def find_proposal_address(program, governance, mint, index) do
    maybe_return_found_address(["governance", governance, mint, <<index::size(32)>>], program)
  end

  @doc """
  Finds the `proposal`'s `signatory` record address. Should have the seeds:
  `['governance', proposal, signatory]`.
  """
  @spec find_signatory_record_address(
          program :: Key.t(),
          proposal :: Key.t(),
          signatory :: Key.t()
        ) :: Key.t()
  def find_signatory_record_address(program, proposal, signatory) do
    maybe_return_found_address(["governance", proposal, signatory], program)
  end

  @doc """
  Finds the `proposal`'s instruction address for index `index`. Should have the
  seeds: `['governance', proposal, index]`.
  """
  @spec find_instruction_address(
          program :: Key.t(),
          proposal :: Key.t(),
          index :: non_neg_integer
        ) :: Key.t()
  def find_instruction_address(program, proposal, index) do
    maybe_return_found_address(["governance", proposal, <<index::size(16)>>], program)
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
    community_mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Community token mint for the new realm."
    ],
    council_mint: [
      type: {:custom, Key, :check, []},
      doc: "Community token mint for the new realm."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    addin: [type: {:custom, Key, :check, []}, doc: "Community voter weight add-in program ID."],
    name: [type: :string, required: true, doc: "The name of the new realm."],
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
      {:ok, %{program: program, name: name} = params} ->
        realm = find_realm_address(program, name)

        %Instruction{
          program: program,
          accounts:
            List.flatten([
              create_realm_accounts(Map.pop(params, :council_mint), realm),
              %Account{key: find_realm_config_address(program, realm), writable?: true},
              voter_weight_addin_account(params)
            ]),
          data:
            Instruction.encode_data([0, {byte_size(name), 32}, name | realm_config_data(params)])
        }

      error ->
        error
    end
  end

  defp create_realm_accounts({nil, %{community_mint: mint} = params}, realm) do
    [
      %Account{key: realm, writable?: true},
      %Account{key: params.authority},
      %Account{key: mint},
      %Account{key: find_holding_address(params.program, realm, mint), writable?: true},
      %Account{key: params.payer, signer?: true},
      %Account{key: SystemProgram.id()},
      %Account{key: Token.id()},
      %Account{key: Solana.rent()}
    ]
  end

  defp create_realm_accounts({mint, params}, realm) do
    List.flatten([
      create_realm_accounts({nil, params}, realm),
      %Account{key: mint},
      %Account{key: find_holding_address(params.program, realm, mint), writable?: true}
    ])
  end

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
    record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The Token Owner Record account for which the `owner` wishes to delegate rights."
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
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: [
            %Account{key: params.owner, signer?: true},
            %Account{key: params.record, writable?: true}
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
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The address of the governing Token Owner Record."
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
      {:ok, %{program: program, realm: realm, governed: governed} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_account_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed},
            %Account{key: params.owner_record},
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
      doc: "The account which will pay for the new Program Governance account's creation."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The address of the governing Token Owner Record."
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
      {:ok, %{program: program, realm: realm, governed: governed} = params} ->
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
            %Account{key: params.owner_record},
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
                unary(params.transfer_upgrade_authority?)
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
      doc: "The account which will pay for the new Mint Governance account's creation."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The address of the governing Token Owner Record."
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
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The mint which will be goverened by the newly created governance."
    ],
    mint_authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current mint authority of the `mint` to be governed."
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
      {:ok, %{program: program, realm: realm, governed: mint} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_mint_governance_address(program, realm, mint),
              writable?: true
            },
            %Account{key: mint, writable?: true},
            %Account{key: params.mint_authority, signer?: true},
            %Account{key: params.owner_record},
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
                unary(params.transfer_mint_authority?)
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
      doc: "The account which will pay for the new Token Governance account's creation."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The address of the governing Token Owner Record."
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
    governed: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will be goverened by the newly created governance."
    ],
    owner: [
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
    transfer_ownership?: [
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
      {:ok, %{program: program, realm: realm, governed: governed} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_token_governance_address(program, realm, governed),
              writable?: true
            },
            %Account{key: governed, writable?: true},
            %Account{key: params.owner, signer?: true},
            %Account{key: params.owner_record},
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
                unary(params.transfer_ownership?)
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

  @create_proposal_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new Proposal account's creation."
    ],
    owner: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the token owner who is making the propsal."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority."
    ],
    mint: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The governing token mint."
    ],
    governance: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The governance account for which this proposal is made."
    ],
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the realm the created Governance belongs to."
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
    name: [type: :string, required: true, doc: "The proposal name."],
    description: [type: :string, required: true, doc: "The proposal explanation."],
    vote_type: [
      type: {:custom, __MODULE__, :validate_vote_type, []},
      required: true,
      doc: "The proposal's vote type."
    ],
    options: [type: {:list, :string}, required: true, doc: "Proposal options."],
    has_deny_option?: [
      type: :boolean,
      default: true,
      doc: """
      Indicates whether this proposal has a 'deny' option. Must be `true` if the
      proposal wants to include executable instructions.
      """
    ],
    index: [
      type: :non_neg_integer,
      required: true,
      doc: "The proposal index, i.e. this is the Nth proposal for this governance."
    ]
  ]
  @doc """
  Generates instructions which create a Proposal account.

  Proposals allow governance token owners to propose governance changes (i.e.
  instructions) to an account that will go into effect (i.e. be executed) at
  some point in the future.

  ## Options

  #{NimbleOptions.docs(@create_proposal_schema)}
  """
  def create_proposal(opts) do
    case validate(opts, @create_proposal_schema) do
      {:ok, %{vote_type: {:multiple, n}, options: options}} when n > length(options) ->
        {:error, "number of choices greater than options available"}

      {:ok, %{program: program, realm: realm, governance: governance, owner: owner} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{
              key: find_proposal_address(program, governance, params.mint, params.index),
              writable?: true
            },
            %Account{key: governance, writable?: true},
            %Account{
              key: find_owner_record_address(program, realm, params.mint, owner),
              writable?: true
            },
            %Account{key: params.mint},
            %Account{key: params.authority, signer?: true},
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: clock()}
            | voter_weight_accounts(params)
          ],
          data:
            Instruction.encode_data(
              List.flatten([
                6,
                encode_string(params.name),
                encode_string(params.description),
                encode_vote_type(params.vote_type),
                {length(params.options), 32},
                Enum.map(params.options, &encode_string/1),
                unary(params.has_deny_option?)
              ])
            )
        }

      error ->
        error
    end
  end

  def validate_vote_type(:single), do: {:ok, :single}
  def validate_vote_type({:multiple, n}) when is_integer(n) and n > 0, do: {:ok, {:multiple, n}}

  def validate_vote_type(other) do
    {:error, "expected :single or {:multiple, n}, got: #{inspect(other)}"}
  end

  # TODO replace with {str, "borsh"} once `solana` package is updated
  defp encode_string(str), do: [{byte_size(str), 32}, str]

  defp encode_vote_type(:single), do: [0]
  defp encode_vote_type({:multiple, n}), do: [1, {n, 16}]

  @add_signatory_schema [
    proposal: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "proposal account to add the `signatory` to."
    ],
    signatory: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "the signatory to add to the `proposal`."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the new signatory record's creation."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to add a `signatory` to the `proposal`.

  This means that the `proposal` can't leave Draft state until this `signatory`
  signs off on it.

  ## Options

  #{NimbleOptions.docs(@add_signatory_schema)}
  """
  def add_signatory(opts) do
    case validate(opts, @add_signatory_schema) do
      {:ok, %{program: program, proposal: proposal, signatory: signatory} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record},
            %Account{key: params.authority, signer?: true},
            %Account{
              key: find_signatory_record_address(program, proposal, signatory),
              writable?: true
            },
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()}
          ],
          data: Instruction.encode_data([7, signatory])
        }

      error ->
        error
    end
  end

  @remove_signatory_schema [
    proposal: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "proposal account to add the `signatory` to."
    ],
    signatory: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "the signatory to add to the `proposal`."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    beneficiary: [
      type: {:custom, Key, :check, []},
      required: true,
      doc:
        "Public key of the account to receive the disposed signatory record account's lamports."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to remove a `signatory` from the `proposal`.

  ## Options

  #{NimbleOptions.docs(@remove_signatory_schema)}
  """
  def remove_signatory(opts) do
    case validate(opts, @remove_signatory_schema) do
      {:ok, %{program: program, proposal: proposal, signatory: signatory} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record},
            %Account{key: params.authority, signer?: true},
            %Account{
              key: find_signatory_record_address(program, proposal, signatory),
              writable?: true
            },
            %Account{key: params.beneficiary, writable?: true}
          ],
          data: Instruction.encode_data([8, signatory])
        }

      error ->
        error
    end
  end

  @insert_instruction_schema [
    governance: [type: {:custom, Key, :check, []}, required: true, doc: "The governance account."],
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the ProposalInstruction account's creation."
    ],
    option: [
      type: :non_neg_integer,
      default: 0,
      doc: "The index of the option the instruction is for."
    ],
    index: [
      type: :non_neg_integer,
      required: true,
      doc: "The index where the `instruction` will be inserted."
    ],
    delay: [
      type: :non_neg_integer,
      default: 0,
      doc: """
      Wait time (in seconds) between the vote period ending and the
      `instruction` being eligible for execution.
      """
    ],
    instruction: [
      type: {:custom, __MODULE__, :validate_instruction, []},
      required: true,
      doc: "Data for the instruction to be executed"
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to insert an instruction into the proposal at the
  given `index`.

  New instructions must be inserted at the end of the range indicated by the
  proposal's `instruction_next_index` property. If an instruction replaces an
  existing Instruction at a given `index`, the old one must first be removed by
  calling `Solana.SPL.Governance.remove_instruction/1`.

  ## Options

  #{NimbleOptions.docs(@insert_instruction_schema)}
  """
  def insert_instruction(opts) do
    case validate(opts, @insert_instruction_schema) do
      {:ok, %{program: program, proposal: proposal, index: index} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: params.governance},
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record},
            %Account{key: params.authority, signer?: true},
            %Account{key: find_instruction_address(program, proposal, index), writable?: true},
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()}
          ],
          data:
            Instruction.encode_data([
              9,
              {params.option_index, 16},
              {index, 16},
              {params.delay, 32}
              | ix_data(params.instruction)
            ])
        }

      error ->
        error
    end
  end

  @doc false
  def validate_instruction(%Instruction{} = ix), do: {:ok, ix}

  def validate_instruction(other) do
    {:error, "expected a Solana.Instruction, got: #{inspect(other)}"}
  end

  defp ix_data(%Instruction{} = ix) do
    [
      ix.program,
      {length(ix.accounts), 32},
      Enum.map(ix.accounts, &account_data/1),
      {byte_size(ix.data), 32},
      ix.data
    ]
  end

  defp account_data(%Account{} = account) do
    [account.key, unary(account.signer?), unary(account.writable?)]
  end

  @remove_instruction_schema [
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    beneficiary: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the account to receive the disposed instruction account's lamports."
    ],
    index: [
      type: :non_neg_integer,
      required: true,
      doc: "The index indicating the instruction to remove."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to remove the Instruction data at the given `index`
  from the given `proposal`.

  ## Options

  #{NimbleOptions.docs(@remove_instruction_schema)}
  """
  def remove_instruction(opts) do
    case validate(opts, @remove_instruction_schema) do
      {:ok, %{program: program, proposal: proposal, index: index} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record},
            %Account{key: params.authority, signer?: true},
            %Account{key: find_instruction_address(program, proposal, index), writable?: true},
            %Account{key: params.beneficiary, writable?: true}
          ],
          data: Instruction.encode_data([10])
        }

      error ->
        error
    end
  end

  @cancel_proposal_schema [
    governance: [type: {:custom, Key, :check, []}, required: true, doc: "The governance account."],
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to cancel the given `proposal`.

  ## Options

  #{NimbleOptions.docs(@cancel_proposal_schema)}
  """
  def cancel_proposal(opts) do
    case validate(opts, @cancel_proposal_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: [
            %Account{key: params.proposal, writable?: true},
            %Account{key: params.owner_record, writable?: true},
            %Account{key: params.authority, signer?: true},
            %Account{key: clock()},
            %Account{key: params.governance}
          ],
          data: Instruction.encode_data([11])
        }

      error ->
        error
    end
  end

  @sign_off_proposal_schema [
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    signatory: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "the signatory signing off on the `proposal`."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions for a `signatory` to sign off on a `proposal`.

  This indicates the `signatory` approves of the `proposal`. When the last
  `signatory` signs off, the `proposal` moves to the Voting state.

  ## Options

  #{NimbleOptions.docs(@sign_off_proposal_schema)}
  """
  def sign_off_proposal(opts) do
    case validate(opts, @sign_off_proposal_schema) do
      {:ok, %{program: program, signatory: signatory, proposal: proposal}} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{
              key: find_signatory_record_address(program, proposal, signatory),
              writable?: true
            },
            %Account{key: signatory, signer?: true},
            %Account{key: clock()}
          ],
          data: Instruction.encode_data([12])
        }

      error ->
        error
    end
  end

  @cast_vote_schema [
    realm: [type: {:custom, Key, :check, []}, required: true, doc: "The realm account."],
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    governance: [type: {:custom, Key, :check, []}, required: true, doc: "The governance account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    mint: [type: {:custom, Key, :check, []}, required: true, doc: "The governing token mint."],
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for VoteRecord account's creation."
    ],
    voter_weight_record: [
      type: {:custom, Key, :check, []},
      doc: "Public key of the voter weight record account."
    ],
    voter: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the voter's governing token account."
    ],
    vote: [
      type: {:list, {:custom, __MODULE__, :validate_vote, []}},
      required: true,
      doc: "The user's vote. Passing an empty list indicates proposal rejection."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions for a token owner to cast a vote on the given
  `proposal`.

  By doing so, the owner indicates they approve or disapprove of running the
  `proposal`'s set of instructions.

  If this vote causes the proposal to reach a consensus, the instructions can be
  run after the configured `delay`.

  ## Options

  #{NimbleOptions.docs(@cast_vote_schema)}
  """
  def cast_vote(opts) do
    case validate(opts, @cast_vote_schema) do
      {:ok, %{program: program, mint: mint, realm: realm, proposal: proposal} = params} ->
        voter_record = find_owner_record_address(program, realm, mint, params.voter)

        %Instruction{
          program: program,
          accounts: [
            %Account{key: realm},
            %Account{key: params.governance},
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record, writable?: true},
            %Account{key: voter_record, writable?: true},
            %Account{key: params.authority, signer?: true},
            %Account{
              key: find_vote_record_address(program, proposal, voter_record),
              writable?: true
            },
            %Account{key: mint},
            %Account{key: params.payer, signer?: true},
            %Account{key: SystemProgram.id()},
            %Account{key: Solana.rent()},
            %Account{key: clock()}
            | voter_weight_accounts(params)
          ],
          data:
            Instruction.encode_data([
              13 | vote_data(params.vote)
            ])
        }

      error ->
        error
    end
  end

  @doc false
  def validate_vote({rank, weight} = vote) when rank in 0..255 and weight in 0..100,
    do: {:ok, vote}

  def validate_vote(other), do: {:error, "Expected a {rank, weight} tuple, got #{inspect(other)}"}

  defp vote_data([]), do: [1]

  defp vote_data(votes) do
    List.flatten([
      0,
      {length(votes), 32},
      Enum.map(votes, &Tuple.to_list/1)
    ])
  end

  @finalize_vote_schema [
    realm: [type: {:custom, Key, :check, []}, required: true, doc: "The realm account."],
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    governance: [type: {:custom, Key, :check, []}, required: true, doc: "The governance account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    mint: [type: {:custom, Key, :check, []}, required: true, doc: "The governing token mint."],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions to finalize a vote.

  This is available in case the vote was not automatically tipped with the
  proposal's `duration`.

  ## Options

  #{NimbleOptions.docs(@finalize_vote_schema)}
  """
  def finalize_vote(opts) do
    case validate(opts, @finalize_vote_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: [
            %Account{key: params.realm},
            %Account{key: params.governance},
            %Account{key: params.proposal, writable?: true},
            %Account{key: params.owner_record, writable?: true},
            %Account{key: params.mint},
            %Account{key: clock()}
          ],
          data: Instruction.encode_data([14])
        }

      error ->
        error
    end
  end

  @relinquish_vote_schema [
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    governance: [type: {:custom, Key, :check, []}, required: true, doc: "The governance account."],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the voter's governing Token Owner Record."
    ],
    mint: [type: {:custom, Key, :check, []}, required: true, doc: "The governing token mint."],
    authority: [
      type: {:custom, Key, :check, []},
      doc: """
      Public key of the governance authority (or its delegate). Only required if
      the proposal is still being voted on.
      """
    ],
    beneficiary: [
      type: {:custom, Key, :check, []},
      doc: """
      Public key of the account to receive the disposed vote record account's
      lamports. Only required if the proposal is still being voted on.
      """
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions to relinquish a voter's vote from a proposal.

  If the proposal is still being voted on, the voter's weight won't count toward
  the outcome. If the proposal is already decided, this instruction has no
  effect on the proposal, but allows voters to prune their outstanding votes in
  case they want to withdraw governing tokens from the realm.

  ## Options

  #{NimbleOptions.docs(@relinquish_vote_schema)}
  """
  def relinquish_vote(opts) do
    case validate(opts, @relinquish_vote_schema) do
      {:ok, %{program: program, proposal: proposal, owner_record: owner_record} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: params.governance},
            %Account{key: proposal, writable?: true},
            %Account{key: owner_record, writable?: true},
            %Account{
              key: find_vote_record_address(program, proposal, owner_record),
              writable?: true
            },
            %Account{key: params.mint}
            | optional_relinquish_accounts(params)
          ],
          data: Instruction.encode_data([15])
        }

      error ->
        error
    end
  end

  defp optional_relinquish_accounts(%{authority: authority, beneficiary: beneficiary}) do
    [%Account{key: authority, signer?: true}, %Account{key: beneficiary, writable?: true}]
  end

  defp optional_relinquish_accounts(_), do: []

  @execute_instruction_schema [
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    index: [
      type: :non_neg_integer,
      required: true,
      doc: "The index indicating the instruction to execute."
    ],
    accounts: [
      type: {:list, {:custom, __MODULE__, :validate_account, []}},
      doc: "Any extra accounts that are part of the instruction, in order."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates instructions to execute the instruction at index `index` in the
  proposal.

  Anybody can execute an instruction once the Proposal has been approved and the
  instruction's `delay` time has passed.

  The instruction being executed will be signed by the Governance PDA the
  proposal belongs to, e.g. the Program Governance PDA for program upgrade
  instructions.

  ## Options

  #{NimbleOptions.docs(@execute_instruction_schema)}
  """
  def execute_instruction(opts) do
    case validate(opts, @execute_instruction_schema) do
      {:ok, %{program: program, proposal: proposal, index: index} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{key: find_instruction_address(program, proposal, index), writable?: true},
            %Account{key: clock()}
            | params.accounts
          ],
          data: Instruction.encode_data([16])
        }

      error ->
        error
    end
  end

  @doc false
  def validate_account(%Account{} = account), do: {:ok, account}

  def validate_account(other) do
    {:error, "expected a Solana.Account, got #{inspect(other)}"}
  end

  @set_governance_config_schema [
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The realm account the `governance` belongs to."
    ],
    governance: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The governance account to receive the new `config`."
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
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Generates the instructions to set a governance's config.

  ## Options

  #{NimbleOptions.docs(@set_governance_config_schema)}
  """
  def set_governance_config(opts) do
    case validate(opts, @set_governance_config_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: [
            %Account{key: params.realm},
            %Account{key: params.governance, writable?: true, signer?: true}
          ],
          data: Instruction.encode_data([19 | serialize_config(params.config)])
        }

      error ->
        error
    end
  end

  @flag_instruction_error_schema [
    proposal: [type: {:custom, Key, :check, []}, required: true, doc: "The proposal account."],
    index: [
      type: :non_neg_integer,
      required: true,
      doc: "The index indicating the instruction to flag."
    ],
    authority: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance authority (or its delegate)."
    ],
    owner_record: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the `proposal` owner's Token Owner Record account."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ]
  ]
  @doc """
  Flag an instruction and its parent proposal with "error" status.

  ## Options

  #{NimbleOptions.docs(@flag_instruction_error_schema)}
  """
  def flag_instruction_error(opts) do
    case validate(opts, @flag_instruction_error_schema) do
      {:ok, %{program: program, proposal: proposal, index: index} = params} ->
        %Instruction{
          program: program,
          accounts: [
            %Account{key: proposal, writable?: true},
            %Account{key: params.owner_record},
            %Account{key: params.authority, signer?: true},
            %Account{key: find_instruction_address(program, proposal, index), writable?: true},
            %Account{key: clock()}
          ],
          data: Instruction.encode_data([20])
        }

      error ->
        error
    end
  end

  @set_realm_authority_schema [
    realm: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The realm account to assign a new authority."
    ],
    current: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The current realm authority."
    ],
    new: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The new realm authority. Must be one of the realm governances."
    ],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
    ],
    remove_authority?: [
      type: :boolean,
      default: false,
      doc: "Whether or not to remove the realm authority."
    ]
  ]
  @doc """
  Generates the instructions to set a new realm authority.

  ## Options

  #{NimbleOptions.docs(@set_realm_authority_schema)}
  """
  def set_realm_authority(opts) do
    case validate(opts, @set_realm_authority_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: [
            %Account{key: params.realm, writable?: true},
            %Account{key: params.current, signer?: true},
            %Account{key: params.new}
          ],
          data: Instruction.encode_data([21, unary(params.remove_authority?)])
        }

      error ->
        error
    end
  end

  @set_realm_config_schema [
    realm: [type: {:custom, Key, :check, []}, required: true, doc: "The realm account."],
    authority: [type: {:custom, Key, :check, []}, required: true, doc: "The realm authority."],
    council_mint: [type: {:custom, Key, :check, []}, doc: "The realm's council token mint."],
    payer: [
      type: {:custom, Key, :check, []},
      doc: "The account which will pay for Realm Config account's creation."
    ],
    addin: [type: {:custom, Key, :check, []}, doc: "Community voter weight add-in program ID."],
    program: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "Public key of the governance program instance to use."
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
  Generates instructions to set the realm config.

  ## Options

  #{NimbleOptions.docs(@set_realm_config_schema)}
  """
  def set_realm_config(opts) do
    case validate(opts, @set_realm_config_schema) do
      {:ok, %{program: program, realm: realm} = params} ->
        %Instruction{
          program: program,
          accounts:
            List.flatten([
              %Account{key: realm, writable?: true},
              %Account{key: params.authority, signer?: true},
              council_accounts(params),
              %Account{key: SystemProgram.id()},
              %Account{key: find_realm_config_address(program, realm), writable?: true},
              payer_account(params),
              voter_weight_addin_account(params)
            ]),
          data: Instruction.encode_data([22 | realm_config_data(params)])
        }

      error ->
        error
    end
  end

  defp payer_account(%{payer: payer}), do: [%Account{key: payer, signer?: true}]
  defp payer_account(_), do: []

  defp council_accounts(%{council_mint: mint, realm: realm, program: program}) do
    [
      %Account{key: mint},
      %Account{key: find_holding_address(program, realm, mint), writable?: true}
    ]
  end

  defp council_accounts(_), do: []

  defp voter_weight_addin_account(%{addin: addin}), do: [%Account{key: addin}]
  defp voter_weight_addin_account(_), do: []

  @doc false
  def validate_max_vote_weight_source({type, value})
      when type in @max_vote_weight_sources and is_integer(value) and value > 0 do
    {:ok, {type, value}}
  end

  def validate_max_vote_weight_source(_), do: {:error, "invalid max vote weight source"}

  defp realm_config_data(params) do
    [
      unary(Map.has_key?(params, :council_mint)),
      {params.minimum, 64},
      Enum.find_index(
        @max_vote_weight_sources,
        &(&1 == elem(params.max_vote_weight_source, 0))
      ),
      {elem(params.max_vote_weight_source, 1), 64},
      unary(Map.has_key?(params, :addin))
    ]
  end

  # @create_owner_record_schema [
  #   program: [
  #     type: {:custom, Key, :check, []},
  #     required: true,
  #     doc: "Public key of the governance program instance to use."
  #   ]
  # ]
  # @doc """

  # ## Options

  # #{NimbleOptions.docs(@create_owner_record_schema)}
  # """
  # def create_owner_record(opts) do
  #   case validate(opts, @create_owner_record_schema) do
  #     {:ok, params} ->
  #       %Instruction{
  #       }
  #     error ->
  #       error
  #   end
  # end

  # @update_program_metadata_schema [
  #   program: [
  #     type: {:custom, Key, :check, []},
  #     required: true,
  #     doc: "Public key of the governance program instance to use."
  #   ]
  # ]
  # @doc """

  # ## Options

  # #{NimbleOptions.docs(@update_program_metadata_schema)}
  # """
  # def update_program_metadata(opts) do
  #   case validate(opts, @update_program_metadata_schema) do
  #     {:ok, params} ->
  #       %Instruction{
  #       }
  #     error ->
  #       error
  #   end
  # end

  # @create_native_treasury_schema [
  #   program: [
  #     type: {:custom, Key, :check, []},
  #     required: true,
  #     doc: "Public key of the governance program instance to use."
  #   ]
  # ]
  # @doc """

  # ## Options

  # #{NimbleOptions.docs(@create_native_treasury_schema)}
  # """
  # def create_native_treasury(opts) do
  #   case validate(opts, @create_native_treasury_schema) do
  #     {:ok, params} ->
  #       %Instruction{
  #       }
  #     error ->
  #       error
  #   end
  # end

  # TODO replace with with Solana.clock() once `solana` package is updated
  defp clock(), do: Solana.pubkey!("SysvarC1ock11111111111111111111111111111111")

  defp unary(condition), do: if(condition, do: 1, else: 0)

  defp voter_weight_accounts(%{voter_weight_record: record, realm: realm, program: program}) do
    [%Account{key: find_realm_config_address(program, realm)}, %Account{key: record}]
  end

  defp voter_weight_accounts(_), do: []
end
