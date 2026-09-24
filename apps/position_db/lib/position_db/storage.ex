defmodule PositionDB.Storage do
  @moduledoc """
  Physical storage contract for positions.

  A storage implementation owns:

    * position ID allocation
    * position records
    * exact-key lookup
    * exact-position deduplication
    * sequential scans

  Position IDs returned by storage are durable identities.
  """

  @type t :: term()
  @type key :: term()
  @type position :: term()
  @type position_id :: non_neg_integer()
  @type scan_state :: term()

  @callback put(t(), key(), position()) ::
              {:ok, t(), position_id()}
              | {:error, term()}

  @callback get(t(), position_id()) ::
              {:ok, position()} | :not_found

  @callback find(t(), key(), position()) ::
              {:ok, position_id()} | :not_found

  @callback scan(t()) :: scan_state()

  @callback scan_next(scan_state()) ::
              {:ok, position_id(), scan_state()}
              | :done

  @callback cardinality(t()) ::
              non_neg_integer()
end
