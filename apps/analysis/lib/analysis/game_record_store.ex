defmodule Analysis.GameRecordStore do
  @moduledoc """
  PostgreSQL persistence for concrete played-game records.

  Logical record identity is stored in `record_id`. PostgreSQL owns an
  independent monotonic row ID used internally for relational identity
  and indexing.
  """

  alias Analysis.GameRecord
  alias Analysis.GameStart
  alias OpenChessLab.Repo

  @insert_sql """
  INSERT INTO game_records (
    record_id,
    game_id,
    fullmove_number,
    metadata
  )
  VALUES (
    $1,
    $2,
    $3,
    $4
  )
  RETURNING id
  """

  @get_sql """
  SELECT
    record_id,
    game_id,
    fullmove_number,
    metadata
  FROM game_records
  WHERE record_id = $1
  """

  @spec ready?() :: boolean()
  def ready? do
    case Repo.query(
           "SELECT 1",
           []
         ) do
      {:ok, _result} ->
        true

      {:error, _reason} ->
        false
    end
  rescue
    _error ->
      false
  catch
    :exit, _reason ->
      false
  end

  @spec insert(GameRecord.t()) ::
          :ok
          | {:error, term()}
  def insert(%GameRecord{} = record) do
    with :ok <-
           validate_record(record) do
      do_insert(record)
    end
  end

  def insert(_record) do
    {:error, :invalid_game_record}
  end

  @spec get(GameRecord.id()) ::
          {:ok, GameRecord.t()}
          | :not_found
          | {:error, term()}
  def get(record_id) when is_binary(record_id) and byte_size(record_id) > 0 do
    case Repo.query(
           @get_sql,
           [record_id]
         ) do
      {:ok, %{rows: [row]}} ->
        {:ok, record_from_row(row)}

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get(_record_id) do
    :not_found
  end

  defp do_insert(%GameRecord{} = record) do
    start =
      GameRecord.start(record)

    case Repo.query(
           @insert_sql,
           [
             GameRecord.id(record),
             GameRecord.game_id(record),
             GameStart.fullmove_number(start),
             GameRecord.metadata(record)
           ]
         ) do
      {:ok, %{rows: [[_row_id]]}} ->
        :ok

      {:error,
       %Postgrex.Error{
         postgres: %{
           code: :unique_violation,
           constraint: "game_records_record_id_unique"
         }
       }} ->
        {:error, :already_exists}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_from_row([record_id, game_id, fullmove_number, metadata]) do
    GameRecord.new(
      record_id,
      game_id,
      GameStart.new(fullmove_number),
      metadata
    )
  end

  defp validate_record(%GameRecord{
         id: record_id,
         game_id: game_id,
         start: %GameStart{fullmove_number: fullmove_number},
         metadata: metadata
       }) do
    with :ok <-
           validate_record_id(record_id),
         :ok <-
           validate_game_id(game_id),
         :ok <-
           validate_fullmove_number(fullmove_number) do
      validate_metadata(metadata)
    end
  end

  defp validate_record(_record) do
    {:error, :invalid_game_record}
  end

  defp validate_record_id(record_id) when is_binary(record_id) and byte_size(record_id) > 0 do
    :ok
  end

  defp validate_record_id(_record_id) do
    {:error, :invalid_record_id}
  end

  defp validate_game_id(game_id) when is_integer(game_id) and game_id > 0 do
    :ok
  end

  defp validate_game_id(_game_id) do
    {:error, :invalid_game_id}
  end

  defp validate_fullmove_number(fullmove_number)
       when is_integer(fullmove_number) and fullmove_number > 0 do
    :ok
  end

  defp validate_fullmove_number(_fullmove_number) do
    {:error, :invalid_fullmove_number}
  end

  defp validate_metadata(metadata) do
    if GameRecord.valid_metadata?(metadata) do
      :ok
    else
      {:error, :invalid_metadata}
    end
  end
end
