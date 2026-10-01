defmodule GameDB.Storage do
  @moduledoc """
  Physical storage contract for canonical games.

  A storage implementation owns:

    * stable game ID allocation
    * immutable game records
    * stable occurrence ID allocation
    * the ordered position occurrences of each game
    * lookup and scanning of occurrences for a canonical position
    * sequential game scans

  Game records are identity-less payloads. Their durable identity
  is the game ID allocated by storage.

  Position IDs refer to canonical positions owned by the application
  position repository. The first position ID is the game's initial
  position and therefore has ply zero.

  A game fingerprint is an index key, not game identity.
  Multiple distinct games may share the same fingerprint.

  Exact canonical game identity is established by comparing the
  complete game record. Storing an already existing exact game
  returns its existing durable game ID.
  """

  alias GameDB.Occurrence

  @type t :: term()
  @type game_record :: term()
  @type game_id :: pos_integer()
  @type occurrence_id :: Occurrence.id()
  @type occurrence_scan_state :: term()
  @type position_id :: Occurrence.position_id()
  @type scan_state :: term()
  @type fingerprint :: binary()

  @callback put(
              t(),
              fingerprint(),
              game_record(),
              [position_id()]
            ) ::
              {:ok, t(), game_id()}
              | {:error, term()}

  @callback find(
              t(),
              fingerprint(),
              game_record()
            ) ::
              {:ok, game_id()}
              | :not_found
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

  @callback occurrences_by_position_id(
              t(),
              position_id()
            ) ::
              {:ok, [Occurrence.t()]}
              | {:error, term()}

  @callback scan_occurrences(
              t(),
              position_id()
            ) ::
              occurrence_scan_state()

  @callback scan_occurrences_next(occurrence_scan_state()) ::
              {:ok, Occurrence.t(), occurrence_scan_state()}
              | :done
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
