defmodule Analysis.GameRepository do
  @moduledoc """
  Persistence contract for canonical chess games.

  A game fingerprint is an index key only. Implementations must establish
  canonical game identity by comparing the complete `Analysis.GameContent`.

  Implementations also own stable occurrence identity and bounded occurrence
  paging for canonical positions.
  """

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameOccurrence
  alias Analysis.PositionStore

  @type game_id :: pos_integer()
  @type fingerprint :: GameFingerprint.t()
  @type position_id :: PositionStore.position_id()
  @type occurrence_id :: GameOccurrence.id()
  @type occurrence_cursor :: term()

  @type occurrence_page ::
          {:ok, [GameOccurrence.t()], :done | occurrence_cursor()}
          | {:error, term()}

  @callback ready?() :: boolean()

  @callback put(
              fingerprint(),
              GameContent.t(),
              [position_id()]
            ) ::
              {:ok, game_id()}
              | {:error, term()}

  @callback find(
              fingerprint(),
              GameContent.t()
            ) ::
              {:ok, game_id()}
              | :not_found
              | {:error, term()}

  @callback get(game_id()) ::
              {:ok, GameContent.t()}
              | :not_found
              | {:error, term()}

  @callback occurrences(game_id()) ::
              {:ok, [GameOccurrence.t()]}
              | :not_found
              | {:error, term()}

  @callback occurrences_page(
              position_id(),
              pos_integer()
            ) :: occurrence_page()

  @callback next_occurrences_page(
              occurrence_cursor(),
              pos_integer()
            ) :: occurrence_page()

  @callback close_occurrences(occurrence_cursor()) :: :ok

  @callback get_occurrence(occurrence_id()) ::
              {:ok, GameOccurrence.t()}
              | :not_found
              | {:error, term()}
end
