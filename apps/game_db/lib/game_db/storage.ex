defmodule GameDB.Storage do
  @moduledoc """
  Physical storage contract for canonical games.

  A storage implementation owns:

    * stable game ID allocation
    * immutable game records
    * stable occurrence ID allocation
    * the ordered position occurrences of each game
    * sequential game scans

  Game records are identity-less payloads. Their durable identity
  is the game ID allocated by storage.

  Position IDs refer to positions owned by PositionDB. The first
  position ID is the game's initial position and therefore has
  ply zero.

  A game fingerprint is a candidate lookup key, not game identity.
  Multiple games may share the same fingerprint. The caller decides
  whether candidates represent the same canonical played game.
  """

  alias GameDB.Occurrence

  @type t :: term()
  @type game_record :: term()
  @type game_id :: pos_integer()
  @type occurrence_id :: Occurrence.id()
  @type position_id :: Occurrence.position_id()
  @type scan_state :: term()
  @type fingerprint :: binary()

  @callback append(
              t(),
              fingerprint(),
              game_record(),
              [position_id()]
            ) ::
              {:ok, t(), game_id()}
              | {:error, term()}

  @callback find_candidates(
              t(),
              fingerprint()
            ) ::
              {:ok, [game_id()]}
              | {:error, term()}

  @callback get(
              t(),
              game_id()
            ) ::
              {:ok, game_record()}
              | :not_found
              | {:error, term()}

  @callback occurrences(
              t(),
              game_id()
            ) ::
              {:ok, [Occurrence.t()]}
              | :not_found
              | {:error, term()}

  @callback get_occurrence(
              t(),
              occurrence_id()
            ) ::
              {:ok, Occurrence.t()}
              | :not_found
              | {:error, term()}

  @callback scan(t()) :: scan_state()

  @callback scan_next(scan_state()) ::
              {:ok, game_id(), scan_state()}
              | :done

  @callback cardinality(t()) ::
              non_neg_integer()
end
