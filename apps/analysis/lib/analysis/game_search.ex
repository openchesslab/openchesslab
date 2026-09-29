defmodule Analysis.GameSearch do
  @moduledoc """
  Bounded game search across position queries and concrete game occurrences.

  PositionDB queries are consumed in bounded pages. Matching positions are
  expanded to concrete game-record occurrences through GameRecords without
  materializing the complete result set.
  """

  alias Analysis.GameRecords
  alias Analysis.PositionStore
  alias PositionDB.Query

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [:position_cursor]

    defstruct position_cursor: :done,
              position_ids: [],
              current_position_id: nil,
              occurrence_cursor: nil
  end

  @type query_error ::
          {:position_store, term()}
          | {:game_records, GameRecords.occurrence_query_error()}

  @opaque query_cursor :: %Cursor{
            position_cursor:
              :done
              | PositionStore.query_cursor(),
            position_ids: [PositionDB.position_id()],
            current_position_id:
              PositionDB.position_id()
              | nil,
            occurrence_cursor:
              GameRecords.occurrence_cursor()
              | nil
          }

  @type query_page ::
          {:ok, [GameRecords.occurrence_match()], :done | query_cursor()}
          | {:error, query_error()}

  @spec query_page(
          Query.t(),
          pos_integer()
        ) ::
          query_page()
  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    case PositionStore.query_page(
           query,
           page_size
         ) do
      {
        :ok,
        [],
        :done
      } ->
        {
          :ok,
          [],
          :done
        }

      {
        :ok,
        position_ids,
        position_cursor
      } ->
        take_query_page(
          %Cursor{position_cursor: position_cursor, position_ids: position_ids},
          page_size
        )

      {:error, reason} ->
        {
          :error,
          {
            :position_store,
            reason
          }
        }
    end
  end

  @spec next_query_page(
          query_cursor(),
          pos_integer()
        ) ::
          query_page()
  def next_query_page(%Cursor{} = cursor, page_size)
      when is_integer(page_size) and page_size > 0 do
    case prepare_next_position_page(
           cursor,
           page_size
         ) do
      {:ok, cursor} ->
        take_query_page(
          cursor,
          page_size
        )

      :done ->
        {
          :ok,
          [],
          :done
        }

      {:error, _reason} = error ->
        error
    end
  end

  @spec close_query(query_cursor()) ::
          :ok
  def close_query(%Cursor{} = cursor) do
    close_occurrence_cursor(cursor.occurrence_cursor)

    close_position_cursor(cursor.position_cursor)

    :ok
  end

  defp prepare_next_position_page(
         %Cursor{
           position_cursor: :done,
           position_ids: [],
           current_position_id: nil,
           occurrence_cursor: nil
         },
         _page_size
       ) do
    :done
  end

  defp prepare_next_position_page(
         %Cursor{
           position_ids: [],
           current_position_id: nil,
           occurrence_cursor: nil,
           position_cursor: position_cursor
         } = cursor,
         page_size
       ) do
    case PositionStore.next_query_page(
           position_cursor,
           page_size
         ) do
      {
        :ok,
        [],
        :done
      } ->
        :done

      {
        :ok,
        position_ids,
        next_position_cursor
      } ->
        {:ok,
         %{
           cursor
           | position_cursor: next_position_cursor,
             position_ids: position_ids
         }}

      {:error, reason} ->
        {
          :error,
          {
            :position_store,
            reason
          }
        }
    end
  end

  defp prepare_next_position_page(%Cursor{} = cursor, _page_size) do
    {:ok, cursor}
  end

  defp take_query_page(cursor, page_size) do
    take_query_page(
      cursor,
      page_size,
      []
    )
  end

  defp take_query_page(cursor, 0, reversed_matches) do
    if query_finished?(cursor) do
      {
        :ok,
        Enum.reverse(reversed_matches),
        :done
      }
    else
      {
        :ok,
        Enum.reverse(reversed_matches),
        cursor
      }
    end
  end

  defp take_query_page(cursor, remaining, reversed_matches) do
    case next_match(cursor) do
      {
        :ok,
        match,
        cursor
      } ->
        take_query_page(
          cursor,
          remaining - 1,
          [
            match
            | reversed_matches
          ]
        )

      {
        :position_page_done,
        cursor
      } ->
        {
          :ok,
          Enum.reverse(reversed_matches),
          cursor
        }

      :done ->
        {
          :ok,
          Enum.reverse(reversed_matches),
          :done
        }

      {:error, _reason} = error ->
        error
    end
  end

  defp next_match(
         %Cursor{current_position_id: nil, position_ids: [position_id | remaining_position_ids]} =
           cursor
       ) do
    next_match(%{
      cursor
      | current_position_id: position_id,
        position_ids: remaining_position_ids
    })
  end

  defp next_match(%Cursor{
         current_position_id: nil,
         occurrence_cursor: nil,
         position_ids: [],
         position_cursor: :done
       }) do
    :done
  end

  defp next_match(
         %Cursor{current_position_id: nil, occurrence_cursor: nil, position_ids: []} = cursor
       ) do
    {
      :position_page_done,
      cursor
    }
  end

  defp next_match(%Cursor{current_position_id: position_id, occurrence_cursor: nil} = cursor) do
    case GameRecords.occurrences_page_by_position_id(
           position_id,
           1
         ) do
      {
        :ok,
        [
          match
        ],
        :done
      } ->
        {
          :ok,
          match,
          %{
            cursor
            | current_position_id: nil
          }
        }

      {
        :ok,
        [
          match
        ],
        occurrence_cursor
      } ->
        {
          :ok,
          match,
          %{
            cursor
            | occurrence_cursor: occurrence_cursor
          }
        }

      {
        :ok,
        [],
        :done
      } ->
        next_match(%{
          cursor
          | current_position_id: nil
        })

      {:error, reason} ->
        close_position_cursor(cursor.position_cursor)

        {
          :error,
          {
            :game_records,
            reason
          }
        }
    end
  end

  defp next_match(%Cursor{occurrence_cursor: occurrence_cursor} = cursor) do
    case GameRecords.next_occurrences_page(
           occurrence_cursor,
           1
         ) do
      {
        :ok,
        [
          match
        ],
        :done
      } ->
        {
          :ok,
          match,
          %{
            cursor
            | current_position_id: nil,
              occurrence_cursor: nil
          }
        }

      {
        :ok,
        [
          match
        ],
        next_occurrence_cursor
      } ->
        {
          :ok,
          match,
          %{
            cursor
            | occurrence_cursor: next_occurrence_cursor
          }
        }

      {
        :ok,
        [],
        :done
      } ->
        next_match(%{
          cursor
          | current_position_id: nil,
            occurrence_cursor: nil
        })

      {:error, reason} ->
        close_occurrence_cursor(occurrence_cursor)

        close_position_cursor(cursor.position_cursor)

        {
          :error,
          {
            :game_records,
            reason
          }
        }
    end
  end

  defp query_finished?(%Cursor{
         position_cursor: :done,
         position_ids: [],
         current_position_id: nil,
         occurrence_cursor: nil
       }) do
    true
  end

  defp query_finished?(%Cursor{}) do
    false
  end

  defp close_position_cursor(:done) do
    :ok
  end

  defp close_position_cursor(cursor) do
    PositionStore.close_query(cursor)
  end

  defp close_occurrence_cursor(nil) do
    :ok
  end

  defp close_occurrence_cursor(cursor) do
    GameRecords.close_occurrences(cursor)
  end
end
