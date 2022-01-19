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
  @spec find_holding_address(program :: Key.t, realm :: Key.t, mint :: Key.t) :: Key.t
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
  @spec find_realm_config_address(program :: Key.t, realm :: Key.t) :: Key.t
  def find_realm_config_address(program, realm) do
    case Key.find_address(["realm-config", realm], program) do
      {:ok, address, _} -> address
      error -> error
    end
  end

  @create_realm_schema [
    payer: [
      type: {:custom, Key, :check, []},
      required: true,
      doc: "The account which will pay for the `new` realm account's creation"
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
  Creates instructions which create a new realm.

  ## Options

  #{NimbleOptions.docs(@create_realm_schema)}
  """
  def create_realm(opts) do
    case validate(opts, @create_realm_schema) do
      {:ok, params} ->
        %Instruction{
          program: params.program,
          accounts: List.flatten([
            create_realm_accounts(Map.pop(params, :council_mint)),
            %Account{key: find_realm_config_address(params.program, params.new), writable?: true}
            | maybe_add_voter_weight_addin(params)
          ]),
          data: Instruction.encode_data([
            {params.name, "str"},
            if(Map.has_key?(params, :council_mint), do: 1, else: 0),
            {params.minimum, 64},
            Enum.find_index(@mint_max_vote_weight_sources, elem(params.max_vote_weight_source, 0)),
            {elem(params.max_vote_weight_source, 1), 64},
            if(Map.has_key?(params, :addin), do: 1, else: 0),
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
      %Account{key: Solana.rent()},
    ]
  end

  defp create_realm_accounts({mint, params}) do
    List.flatten([
      create_realm_accounts({nil, params}),
      %Account{key: mint},
      %Account{key: find_holding_address(params.program, params.new, mint), writable?: true},
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
end
