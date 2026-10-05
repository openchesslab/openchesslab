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

  Unlike `create/4`, this function does not resolve the initial position or
  apply the canonical moves again. The caller must have produced the replay
  while validating exactly the moves in the supplied game content.

  The replay is still checked structurally against the canonical move list so
  mismatched content and replay data cannot accidentally be persisted.
  """
  @spec create_replayed(
          GameRecord.id(),
          GameContent.t(),
          GameStart.t(),
          GameRecord.metadata(),
          [GameReplay.occurrence()]
        ) ::
          {:ok, GameRecord.t()}
          | {:error, create_error()}
  def create_replayed(record_id, %GameContent{} = content, %GameStart{} = start, metadata, replay)
      when is_binary(record_id) and byte_size(record_id) > 0 and is_map(metadata) and
             is_list(replay) do
    if GameRecord.valid_metadata?(metadata) do
      do_create_replayed(
        record_id,
        content,
        start,
        metadata,
        replay
      )
    else
      {:error, :invalid_metadata}
    end
  end

  def create_replayed(_record_id, %GameContent{}, %GameStart{}, metadata, replay)
      when is_map(metadata) and is_list(replay) do
    {:error, :invalid_record_id}
  end

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

  defp do_create_replayed(record_id, content, start, metadata, replay) do
    with {:ok, fingerprint} <-
           fingerprint(content),
         :ok <-
           validate_replay(
             content,
             replay
           ) do
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

  defp validate_replay(content, replay) do
    validate_replay_moves(
      GameContent.moves(content),
      replay
    )
  end

  defp validate_replay_moves([], []) do
    :ok
  end

  defp validate_replay_moves([move | moves], [{replay_move, %Position{}} | replay])
       when replay_move == move do
    validate_replay_moves(
      moves,
      replay
    )
  end

  defp validate_replay_moves(_moves, _replay) do
    {:error,
     {
       :invalid_game,
       :invalid_replay
     }}
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
