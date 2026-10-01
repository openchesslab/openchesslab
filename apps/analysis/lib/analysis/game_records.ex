defmodule Analysis.GameRecords do
  @moduledoc """
  Application service for concrete played games.

  A played game consists of canonical chess content stored through
  GameStore and a durable concrete GameRecord stored through
  GameRecordStore.
  """

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameOccurrence, as: Occurrence
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameReplay
  alias Analysis.GameRepository
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionStore

  defmodule OccurrenceCursor do
    @moduledoc false

    @enforce_keys [:occurrence_cursor]

    defstruct occurrence_cursor: :done,
              current_occurrence: nil,
              record_cursor: nil
  end

  @type create_error ::
          :already_exists
          | {:invalid_game, term()}
          | {:position_store, term()}
          | {:game_store, term()}
          | {:game_record_store, term()}

  @type load_error ::
          {:game_not_found, GameRepository.game_id()}
          | {:game_store, term()}
          | {:game_record_store, term()}

  @type occurrence_match ::
          {GameRecord.t(), Occurrence.t()}

  @type occurrence_query_error ::
          {:game_store, term()}
          | {:game_record_store, term()}

  @opaque occurrence_cursor :: %OccurrenceCursor{
            occurrence_cursor:
              :done
              | GameStore.occurrence_cursor(),
            current_occurrence:
              Occurrence.t()
              | nil,
            record_cursor:
              GameRecordStore.record_cursor()
              | nil
          }

  @type occurrence_page ::
          {:ok, [occurrence_match()], :done | occurrence_cursor()}
          | {:error, occurrence_query_error()}

  @spec create(
          GameRecord.id(),
          GameContent.t(),
          GameStart.t(),
          map()
        ) ::
          {:ok, GameRecord.t()}
          | {:error, create_error()}
  def create(record_id, %GameContent{} = content, %GameStart{} = start, metadata)
      when is_map(metadata) do
    case GameRecordStore.get(record_id) do
      {:ok, _record} ->
        {:error, :already_exists}

      :not_found ->
        do_create(
          record_id,
          content,
          start,
          metadata
        )

      {:error, reason} ->
        {:error,
         {
           :game_record_store,
           reason
         }}
    end
  end

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
          | {:error, term()}
  def get(record_id) do
    GameRecordStore.get(record_id)
  end

  @spec load(GameRecord.id()) ::
          {:ok, GameRecord.t(), GameContent.t(), [Occurrence.t()]}
          | :not_found
          | {:error, load_error()}
  def load(record_id) do
    case GameRecordStore.get(record_id) do
      {:ok, %GameRecord{} = record} ->
        load_record(record)

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error,
         {
           :game_record_store,
           reason
         }}
    end
  end

  @spec occurrences_page_by_position_id(
          GameRepository.position_id(),
          pos_integer()
        ) ::
          occurrence_page()
  def occurrences_page_by_position_id(position_id, page_size)
      when is_integer(page_size) and page_size > 0 do
    case GameStore.occurrences_page(
           position_id,
           1
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
        [
          %Occurrence{} = occurrence
        ],
        occurrence_cursor
      } ->
        take_occurrence_matches_page(
          %OccurrenceCursor{
            occurrence_cursor: occurrence_cursor,
            current_occurrence: occurrence
          },
          page_size
        )

      {:error, reason} ->
        {
          :error,
          {
            :game_store,
            reason
          }
        }
    end
  end

  @spec next_occurrences_page(
          occurrence_cursor(),
          pos_integer()
        ) ::
          occurrence_page()
  def next_occurrences_page(%OccurrenceCursor{} = cursor, page_size)
      when is_integer(page_size) and page_size > 0 do
    take_occurrence_matches_page(
      cursor,
      page_size
    )
  end

  @spec close_occurrences(occurrence_cursor()) ::
          :ok
  def close_occurrences(%OccurrenceCursor{} = cursor) do
    close_record_cursor(cursor.record_cursor)
    close_occurrence_cursor(cursor.occurrence_cursor)

    :ok
  end

  defp take_occurrence_matches_page(cursor, page_size) do
    take_occurrence_matches_page(
      cursor,
      page_size,
      []
    )
  end

  defp take_occurrence_matches_page(cursor, 0, reversed_matches) do
    if occurrence_cursor_finished?(cursor) do
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

  defp take_occurrence_matches_page(cursor, remaining, reversed_matches) do
    case next_occurrence_match(cursor) do
      {
        :ok,
        match,
        cursor
      } ->
        take_occurrence_matches_page(
          cursor,
          remaining - 1,
          [
            match
            | reversed_matches
          ]
        )

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

  defp next_occurrence_match(%OccurrenceCursor{current_occurrence: nil, occurrence_cursor: :done}) do
    :done
  end

  defp next_occurrence_match(
         %OccurrenceCursor{current_occurrence: nil, occurrence_cursor: occurrence_cursor} = cursor
       ) do
    case GameStore.next_occurrences_page(
           occurrence_cursor,
           1
         ) do
      {
        :ok,
        [
          %Occurrence{} = occurrence
        ],
        next_occurrence_cursor
      } ->
        next_occurrence_match(%{
          cursor
          | occurrence_cursor: next_occurrence_cursor,
            current_occurrence: occurrence
        })

      {
        :ok,
        [],
        :done
      } ->
        :done

      {:error, reason} ->
        close_record_cursor(cursor.record_cursor)

        {
          :error,
          {
            :game_store,
            reason
          }
        }
    end
  end

  defp next_occurrence_match(
         %OccurrenceCursor{current_occurrence: %Occurrence{} = occurrence, record_cursor: nil} =
           cursor
       ) do
    case GameRecordStore.records_page_by_game_id(
           occurrence.game_id,
           1
         ) do
      {
        :ok,
        [
          %GameRecord{} = record
        ],
        :done
      } ->
        {
          :ok,
          {
            record,
            occurrence
          },
          %{
            cursor
            | current_occurrence: nil
          }
        }

      {
        :ok,
        [
          %GameRecord{} = record
        ],
        record_cursor
      } ->
        {
          :ok,
          {
            record,
            occurrence
          },
          %{
            cursor
            | record_cursor: record_cursor
          }
        }

      {
        :ok,
        [],
        :done
      } ->
        next_occurrence_match(%{
          cursor
          | current_occurrence: nil
        })

      {:error, reason} ->
        close_occurrence_cursor(cursor.occurrence_cursor)

        {
          :error,
          {
            :game_record_store,
            reason
          }
        }
    end
  end

  defp next_occurrence_match(
         %OccurrenceCursor{
           current_occurrence: %Occurrence{} = occurrence,
           record_cursor: record_cursor
         } = cursor
       ) do
    case GameRecordStore.next_records_page(
           record_cursor,
           1
         ) do
      {
        :ok,
        [
          %GameRecord{} = record
        ],
        :done
      } ->
        {
          :ok,
          {
            record,
            occurrence
          },
          %{
            cursor
            | current_occurrence: nil,
              record_cursor: nil
          }
        }

      {
        :ok,
        [
          %GameRecord{} = record
        ],
        next_record_cursor
      } ->
        {
          :ok,
          {
            record,
            occurrence
          },
          %{
            cursor
            | record_cursor: next_record_cursor
          }
        }

      {
        :ok,
        [],
        :done
      } ->
        next_occurrence_match(%{
          cursor
          | current_occurrence: nil,
            record_cursor: nil
        })

      {:error, reason} ->
        close_occurrence_cursor(cursor.occurrence_cursor)

        {
          :error,
          {
            :game_record_store,
            reason
          }
        }
    end
  end

  defp occurrence_cursor_finished?(%OccurrenceCursor{
         occurrence_cursor: :done,
         current_occurrence: nil,
         record_cursor: nil
       }) do
    true
  end

  defp occurrence_cursor_finished?(%OccurrenceCursor{}) do
    false
  end

  defp close_occurrence_cursor(:done) do
    :ok
  end

  defp close_occurrence_cursor(cursor) do
    GameStore.close_occurrence_scan(cursor)
  end

  defp close_record_cursor(nil) do
    :ok
  end

  defp close_record_cursor(cursor) do
    GameRecordStore.close_record_scan(cursor)
  end

  defp do_create(record_id, content, start, metadata) do
    with {:ok, fingerprint} <-
           fingerprint(content),
         {:ok, replay} <-
           replay(content),
         {:ok, position_ids} <-
           append_replay_positions(
             content,
             replay
           ),
         {:ok, game_id} <-
           store_canonical_game(
             fingerprint,
             content,
             position_ids
           ) do
      record =
        GameRecord.new(
          record_id,
          game_id,
          start,
          metadata
        )

      case GameRecordStore.insert(record) do
        :ok ->
          {:ok, record}

        {:error, :already_exists} ->
          {:error, :already_exists}

        {:error, reason} ->
          {:error,
           {
             :game_record_store,
             reason
           }}
      end
    end
  end

  defp load_record(record) do
    game_id =
      GameRecord.game_id(record)

    case GameStore.load(game_id) do
      {
        :ok,
        %GameContent{} = content,
        occurrences
      } ->
        {
          :ok,
          record,
          content,
          occurrences
        }

      :not_found ->
        {:error,
         {
           :game_not_found,
           game_id
         }}

      {:error, reason} ->
        {:error,
         {
           :game_store,
           reason
         }}
    end
  end

  defp fingerprint(content) do
    case GameFingerprint.for_content(content) do
      {:ok, fingerprint} ->
        {:ok, fingerprint}

      {:error, reason} ->
        {:error,
         {
           :invalid_game,
           reason
         }}
    end
  end

  defp replay(content) do
    case GameReplay.replay(
           content,
           &get_position/1
         ) do
      {:ok, replay} ->
        {:ok, replay}

      {:error,
       {
         :position_not_found,
         position_id
       }} ->
        {:error,
         {
           :invalid_game,
           {
             :position_not_found,
             position_id
           }
         }}

      {:error,
       {
         :illegal_move,
         ply
       }} ->
        {:error,
         {
           :invalid_game,
           {
             :illegal_move,
             ply
           }
         }}

      {:error,
       {
         :position_store,
         _reason
       }} = error ->
        error

      {:error, reason} ->
        {:error,
         {
           :invalid_game,
           reason
         }}
    end
  end

  defp append_replay_positions(content, replay) do
    initial_position_id =
      GameContent.initial_position_id(content)

    replay
    |> Enum.reduce_while(
      {
        :ok,
        [initial_position_id]
      },
      fn {_move, position}, {:ok, reversed_position_ids} ->
        case append_position(position) do
          {:ok, position_id} ->
            {:cont,
             {
               :ok,
               [
                 position_id
                 | reversed_position_ids
               ]
             }}

          {:error, _reason} = error ->
            {:halt, error}
        end
      end
    )
    |> case do
      {
        :ok,
        reversed_position_ids
      } ->
        {:ok, Enum.reverse(reversed_position_ids)}

      {:error, _reason} = error ->
        error
    end
  end

  defp store_canonical_game(fingerprint, content, position_ids) do
    case GameStore.put(
           fingerprint,
           content,
           position_ids
         ) do
      {:ok, game_id} ->
        {:ok, game_id}

      {:error, reason} ->
        {:error,
         {
           :game_store,
           reason
         }}
    end
  end

  defp append_position(position) do
    case PositionStore.append(position) do
      position_id
      when is_integer(position_id) and
             position_id > 0 ->
        {:ok, position_id}

      {:error, reason} ->
        {:error,
         {
           :position_store,
           reason
         }}
    end
  end

  defp get_position(position_id) do
    case PositionStore.get(position_id) do
      {:ok, position} ->
        {:ok, position}

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error,
         {
           :position_store,
           reason
         }}
    end
  end
end
