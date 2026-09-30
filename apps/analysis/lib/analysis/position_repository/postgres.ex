defmodule Analysis.PositionRepository.Postgres do
  @moduledoc """
  PostgreSQL persistence for canonical chess positions.

  Position identity is the complete deterministic binary produced by
  `Chess.PositionCodec`.

  `put/1` is idempotent. An already stored exact position returns its
  existing durable position ID without rewriting the row.
  """

  alias Chess.Position
  alias Chess.PositionCodec
  alias OpenChessLab.Repo

  @insert_sql """
  INSERT INTO positions (record)
  VALUES ($1)
  ON CONFLICT (record) DO NOTHING
  RETURNING id
  """

  @get_sql """
  SELECT record
  FROM positions
  WHERE id = $1
  """

  @find_sql """
  SELECT id
  FROM positions
  WHERE record = $1
  """

  @type position_id :: pos_integer()

  @spec put(Position.t()) ::
          {:ok, position_id()}
          | {:error, term()}
  def put(%Position{} = position) do
    record =
      PositionCodec.encode(position)

    case Repo.query(
           @insert_sql,
           [record]
         ) do
      {:ok, %{rows: [[position_id]]}} ->
        {:ok, position_id}

      {:ok, %{rows: []}} ->
        find_record(record)

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put(_position) do
    {:error, :invalid_position}
  end

  @spec get(position_id()) ::
          {:ok, Position.t()}
          | :not_found
          | {:error, term()}
  def get(position_id) when is_integer(position_id) and position_id > 0 do
    case Repo.query(
           @get_sql,
           [position_id]
         ) do
      {:ok, %{rows: [[record]]}} ->
        decode_record(record)

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get(_position_id) do
    :not_found
  end

  @spec find(Position.t()) ::
          {:ok, position_id()}
          | :not_found
          | {:error, term()}
  def find(%Position{} = position) do
    position
    |> PositionCodec.encode()
    |> find_record()
  end

  def find(_position) do
    {:error, :invalid_position}
  end

  defp find_record(record) do
    case Repo.query(
           @find_sql,
           [record]
         ) do
      {:ok, %{rows: [[position_id]]}} ->
        {:ok, position_id}

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp decode_record(record) do
    case PositionCodec.decode(record) do
      {:ok, %Position{} = position} ->
        {:ok, position}

      {:error, reason} ->
        {:error,
         {
           :invalid_position_record,
           reason
         }}
    end
  end
end
