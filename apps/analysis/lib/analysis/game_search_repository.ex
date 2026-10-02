defmodule Analysis.GameSearchRepository do
  @moduledoc """
  Persistence contract for bounded searches across positions, game
  occurrences and concrete game records.
  """

  alias Analysis.GameOccurrence
  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.PositionQuery

  @type occurrence_match ::
          {GameRecord.t(), GameOccurrence.t()}

  @type query_cursor :: term()

  @type query_page ::
          {:ok, [occurrence_match()], :done | query_cursor()}
          | {:error, term()}

  @callback query_page(
              PositionQuery.t(),
              GameRecordQuery.t(),
              pos_integer()
            ) ::
              query_page()

  @callback next_query_page(
              query_cursor(),
              pos_integer()
            ) ::
              query_page()

  @callback close_query(query_cursor()) ::
              :ok
end
