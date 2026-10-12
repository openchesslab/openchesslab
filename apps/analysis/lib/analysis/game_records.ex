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
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionStore
  alias Chess.Move
  alias Chess.Position
  alias OpenChessLab.Repo

  @type create_error ::
          :already_exists
          | :invalid_record_id
          | :invalid_metadata
          | {:invalid_game, term()}
          | {:position_store, term()}
          | {:game_store, term()}
          | {:game_record_store, term()}

  @type load_error ::
          {:game_not_found, GameStore.game_id()}
          | {:game_store, term()}
          | {:game_record_store, term()}

  @spec create(
          GameRecord.id(),
          GameContent.t(),
          GameStart.t(),
          GameRecord.metadata()
        ) ::
          {:ok, GameRecord.t()}
          | {:error, create_error()}
  def create(record_id, %GameContent{} = content, %GameStart{} = start, metadata)
      when is_binary(record_id) and byte_size(record_id) > 0 and is_map(metadata) do
    if GameRecord.valid_metadata?(metadata) do
      do_create(
        record_id,
        content,
        start,
        metadata
      )
    else
      {:error, :invalid_metadata}
    end
  end

  def create(_record_id, %GameContent{}, %GameStart{}, metadata) when is_map(metadata) do
    {:error, :invalid_record_id}
  end

  @doc """
  Creates a durable game record from a replay that has already been validated.

  Unlike `create/4`, this boundary does not resolve the initial position or
  apply the moves again. It verifies that the supplied replay contains exactly
  the supplied canonical moves and then persists the initial and replay
  positions as one PostgreSQL position batch.
  """
  @spec create_replayed(
          GameRecord.id(),
          Position.t(),
          [Move.t()],
          GameStart.t(),
          GameRecord.metadata(),
          [GameReplay.occurrence()]
        ) ::
          {:ok, GameRecord.t()}
          | {:error, create_error()}
  def create_replayed(
        record_id,
        %Position{} = initial_position,
        moves,
        %GameStart{} = start,
        metadata,
        replay
      )
      when is_binary(record_id) and byte_size(record_id) > 0 and is_list(moves) and
             is_map(metadata) and is_list(replay) do
    if GameRecord.valid_metadata?(metadata) do
      with {:ok, replay_positions} <-
             validate_replay(
               moves,
               replay
             ) do
        do_create_replayed(
          record_id,
          initial_position,
          moves,
          replay_positions,
          start,
          metadata
        )
      end
    else
      {:error, :invalid_metadata}
    end
  end

  def create_replayed(_record_id, %Position{}, moves, %GameStart{}, metadata, replay)
      when is_list(moves) and is_map(metadata) and is_list(replay) do
    {:error, :invalid_record_id}
  end

  @type replayed_batch_entry ::
          {GameRecord.id(), Position.t(), [Move.t()], GameStart.t(), GameRecord.metadata(),
           [GameReplay.occurrence()]}

  @doc """
  Atomically persists a bounded group of already-validated game replays.

  Each entry has the same six arguments as `create_replayed/6`, packaged in a
  tuple. All positions are inserted in one shared batch, then canonical games
  and concrete records are written in input order in the same transaction.

  The return order matches the input order. Failures associated with an entry
  are returned as `{:error, {one_based_index, reason}}` and roll back the entire
  group. A shared position-batch failure is returned without an entry index.
  This is a different transaction boundary from `create_replayed/6`.
  """
  @spec create_replayed_many([replayed_batch_entry()]) ::
          {:ok, [GameRecord.t()]} | {:error, term()}
  def create_replayed_many([]), do: {:ok, []}

  def create_replayed_many(entries) when is_list(entries) do
    with {:ok, prepared} <- prepare_replayed_batch(entries) do
      Repo.transaction(fn -> persist_replayed_batch!(prepared) end)
    end
  end

  def create_replayed_many(_entries), do: {:error, :invalid_batch}

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
          | {:error, term()}
  def get(record_id) do
    GameRecordStore.get(record_id)
  end

  @spec page(keyword()) ::
          GameRecordStore.page_result()
  def page(options) do
    GameRecordStore.page(options)
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

  defp prepare_replayed_batch(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.reduce_while({:ok, MapSet.new(), []}, fn {entry, index}, {:ok, seen_ids, prepared} ->
      case prepare_replayed_entry(entry) do
        {:ok, %{record_id: record_id} = item} ->
          if MapSet.member?(seen_ids, record_id) do
            {:halt, {:error, {index, :duplicate_record_id}}}
          else
            {:cont, {:ok, MapSet.put(seen_ids, record_id), [item | prepared]}}
          end

        {:error, reason} ->
          {:halt, {:error, {index, reason}}}
      end
    end)
    |> case do
      {:ok, _seen_ids, prepared} -> {:ok, Enum.reverse(prepared)}
      {:error, _reason} = error -> error
    end
  end

  defp prepare_replayed_entry(
         {record_id, %Position{} = initial_position, moves, %GameStart{} = start, metadata,
          replay}
       )
       when is_list(moves) and is_list(replay) do
    cond do
      not (is_binary(record_id) and byte_size(record_id) > 0) ->
        {:error, :invalid_record_id}

      not GameRecord.valid_metadata?(metadata) ->
        {:error, :invalid_metadata}

      true ->
        case validate_replay(moves, replay) do
          {:ok, replay_positions} ->
            {:ok,
             %{
               record_id: record_id,
               moves: moves,
               start: start,
               metadata: metadata,
               positions: [initial_position | replay_positions]
             }}

          {:error, _reason} = error ->
            error
        end
    end
  end

  defp prepare_replayed_entry(_entry), do: {:error, :invalid_replayed_game}

  defp persist_replayed_batch!(prepared) do
    positions = Enum.flat_map(prepared, & &1.positions)

    case append_positions(positions) do
      {:ok, position_ids} ->
        {records, remaining_ids} =
          prepared
          |> Enum.with_index(1)
          |> Enum.map_reduce(position_ids, fn {entry, index}, remaining_ids ->
            expected_count = length(entry.positions)
            {ids, rest} = Enum.split(remaining_ids, expected_count)

            if length(ids) != expected_count do
              Repo.rollback({index, :unexpected_position_count})
            end

            [initial_id | _] = ids
            content = GameContent.new(initial_id, entry.moves)

            result =
              with {:ok, fingerprint} <- fingerprint(content),
                   {:ok, game_id} <- store_canonical_game(fingerprint, content, ids) do
                store_game_record(entry.record_id, game_id, entry.start, entry.metadata)
              end

            case result do
              {:ok, record} -> {record, rest}
              {:error, reason} -> Repo.rollback({index, reason})
            end
          end)

        if remaining_ids != [] do
          Repo.rollback({:unexpected_position_count, length(remaining_ids)})
        end

        records

      {:error, reason} ->
        Repo.rollback(reason)
    end
  end

  defp do_create(record_id, content, start, metadata) do
    with {:ok, fingerprint} <-
           fingerprint(content),
         {:ok, replay} <-
           replay(content) do
      persist(
        record_id,
        content,
        start,
        metadata,
        fingerprint,
        replay
      )
    end
  end

  defp do_create_replayed(record_id, initial_position, moves, replay_positions, start, metadata) do
    transact(fn ->
      positions =
        [
          initial_position
          | replay_positions
        ]

      with {:ok,
            [
              initial_position_id
              | _remaining_position_ids
            ] = position_ids} <-
             append_positions(positions),
           content =
             GameContent.new(
               initial_position_id,
               moves
             ),
           {:ok, fingerprint} <-
             fingerprint(content),
           {:ok, game_id} <-
             store_canonical_game(
               fingerprint,
               content,
               position_ids
             ) do
        store_game_record(
          record_id,
          game_id,
          start,
          metadata
        )
      end
    end)
  end

  defp persist(record_id, content, start, metadata, fingerprint, replay) do
    transact(fn ->
      with {:ok, position_ids} <-
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
        store_game_record(
          record_id,
          game_id,
          start,
          metadata
        )
      end
    end)
  end

  defp store_game_record(record_id, game_id, start, metadata) do
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

  defp validate_replay(moves, replay) do
    validate_replay_moves(
      moves,
      replay,
      []
    )
  end

  defp validate_replay_moves([], [], reversed_positions) do
    {:ok, Enum.reverse(reversed_positions)}
  end

  defp validate_replay_moves(
         [%Move{} = move | moves],
         [{%Move{} = replay_move, %Position{} = position} | replay],
         reversed_positions
       )
       when replay_move == move do
    validate_replay_moves(
      moves,
      replay,
      [
        position
        | reversed_positions
      ]
    )
  end

  defp validate_replay_moves(_moves, _replay, _reversed_positions) do
    {:error,
     {
       :invalid_game,
       :invalid_replay
     }}
  end

  defp append_positions(positions) do
    case PositionStore.append_many(positions) do
      {:ok, position_ids} ->
        {:ok, position_ids}

      {:error, reason} ->
        {:error,
         {
           :position_store,
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

  defp transact(fun) when is_function(fun, 0) do
    if Repo.in_transaction?() do
      fun.()
    else
      Repo.transact(fun)
    end
  end
end
