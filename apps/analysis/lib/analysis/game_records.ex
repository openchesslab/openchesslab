defmodule Analysis.GameRecords do
  @moduledoc """
  Application service for concrete played games.

  A played game consists of canonical chess content stored in
  GameStore and a concrete GameRecord stored in GameRecordStore.
  """

  alias Analysis.GameContent
  alias Analysis.GameFingerprint
  alias Analysis.GameRecord
  alias Analysis.GameRecordStore
  alias Analysis.GameReplay
  alias Analysis.GameStart
  alias Analysis.GameStore
  alias Analysis.PositionStore

  @type create_error ::
          :already_exists
          | {:invalid_game, term()}
          | {:position_store, term()}
          | {:game_store, term()}

  @type load_error ::
          {:game_not_found, GameDB.game_id()}
          | {:game_store, term()}

  @spec create(
          GameRecord.id(),
          GameContent.t(),
          GameStart.t(),
          map()
        ) ::
          {:ok, GameRecord.t()}
          | {:error, create_error()}
  def create(
        record_id,
        %GameContent{} = content,
        %GameStart{} = start,
        metadata
      )
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
    end
  end

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
  def get(record_id) do
    GameRecordStore.get(record_id)
  end

  @spec load(GameRecord.id()) ::
          {:ok, GameRecord.t(), GameContent.t(), [GameDB.Occurrence.t()]}
          | :not_found
          | {:error, load_error()}
  def load(record_id) do
    case GameRecordStore.get(record_id) do
      {:ok, %GameRecord{} = record} ->
        load_record(record)

      :not_found ->
        :not_found
    end
  end

  @spec list() ::
          [GameRecord.t()]
  def list do
    GameRecordStore.list()
  end

  @spec list_by_game_id(GameDB.game_id()) ::
          [GameRecord.t()]
  def list_by_game_id(game_id) do
    GameRecordStore.list_by_game_id(game_id)
  end

  defp do_create(
         record_id,
         content,
         start,
         metadata
       ) do
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

  defp append_replay_positions(
         content,
         replay
       ) do
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

  defp store_canonical_game(
         fingerprint,
         content,
         position_ids
       ) do
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
