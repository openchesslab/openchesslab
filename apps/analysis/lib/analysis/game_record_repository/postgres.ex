defmodule Analysis.GameRecordRepository.Postgres do
  @moduledoc """
  PostgreSQL persistence for concrete played-game records.

  Logical record identity is stored in `record_id`. PostgreSQL owns an
  independent monotonic row ID used internally for efficient keyset paging.

  Record paging is stateless and captures the maximum visible row ID when a
  scan starts. Records inserted after that point are therefore excluded from
  the already-open scan.
  """

  @behaviour Analysis.GameRecordRepository

  alias Analysis.GameRecord
  alias Analysis.GameRecordQuery
  alias Analysis.GameStart
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :game_id,
      :query,
      :maximum_row_id,
      :last_row_id
    ]

    defstruct [
      :game_id,
      :query,
      :maximum_row_id,
      :last_row_id
    ]

    @type t :: %__MODULE__{
            game_id: pos_integer(),
            query: GameRecordQuery.t(),
            maximum_row_id: non_neg_integer(),
            last_row_id: pos_integer()
          }
  end

  defmodule QueryCursor do
    @moduledoc false

    @enforce_keys [
      :query,
      :maximum_row_id,
      :last_row_id
    ]

    defstruct [
      :query,
      :maximum_row_id,
      :last_row_id
    ]

    @type t :: %__MODULE__{
            query: GameRecordQuery.t(),
            maximum_row_id: non_neg_integer(),
            last_row_id: pos_integer()
          }
  end

  @type record_cursor :: Cursor.t()
  @type query_cursor :: QueryCursor.t()

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

  @maximum_row_id_sql """
  SELECT COALESCE(max(id), 0)
  FROM game_records
  WHERE game_id = $1
  """

  @records_page_sql """
  SELECT
    id,
    record_id,
    game_id,
    fullmove_number,
    metadata
  FROM game_records
  WHERE game_id = $1
    AND id > $2
    AND id <= $3
  ORDER BY id
  LIMIT $4
  """
  @records_metadata_page_sql """
  SELECT
    id,
    record_id,
    game_id,
    fullmove_number,
    metadata
  FROM game_records
  WHERE game_id = $1
    AND id > $2
    AND id <= $3
    AND metadata @> $4::jsonb
  ORDER BY id
  LIMIT $5
  """

  @maximum_query_row_id_sql """
  SELECT COALESCE(max(id), 0)
  FROM game_records
  """

  @query_all_sql """
  SELECT
    id,
    record_id,
    game_id,
    fullmove_number,
    metadata
  FROM game_records
  WHERE id > $1
    AND id <= $2
  ORDER BY id
  LIMIT $3
  """

  @query_metadata_contains_sql """
  SELECT
    id,
    record_id,
    game_id,
    fullmove_number,
    metadata
  FROM game_records
  WHERE id > $1
    AND id <= $2
    AND metadata @> $3::jsonb
  ORDER BY id
  LIMIT $4
  """

  @impl Analysis.GameRecordRepository
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

  @impl Analysis.GameRecordRepository
  @spec insert(GameRecord.t()) ::
          :ok
          | {:error, term()}
  def insert(%GameRecord{} = record) do
    with :ok <- validate_record(record) do
      do_insert(record)
    end
  end

  def insert(_record) do
    {:error, :invalid_game_record}
  end

  @impl Analysis.GameRecordRepository
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

  @impl Analysis.GameRecordRepository
  @spec records_page_by_game_id(
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}
  def records_page_by_game_id(game_id, page_size) do
    records_page_by_game_id(
      game_id,
      GameRecordQuery.match_all(),
      page_size
    )
  end

  @impl Analysis.GameRecordRepository
  @spec records_page_by_game_id(
          pos_integer(),
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}
  def records_page_by_game_id(game_id, false, page_size)
      when is_integer(game_id) and game_id > 0 and is_integer(page_size) and page_size > 0 do
    {
      :ok,
      [],
      :done
    }
  end

  def records_page_by_game_id(game_id, query, page_size)
      when is_integer(game_id) and game_id > 0 and is_integer(page_size) and page_size > 0 do
    with :ok <-
           validate_query(query),
         {:ok, maximum_row_id} <-
           maximum_row_id(game_id) do
      records_page(
        query,
        game_id,
        0,
        maximum_row_id,
        page_size
      )
    end
  end

  def records_page_by_game_id(_game_id, _query, _page_size) do
    {:error, :invalid_record_page}
  end

  @impl Analysis.GameRecordRepository
  @spec next_records_page(
          record_cursor(),
          pos_integer()
        ) ::
          {:ok, [GameRecord.t()], :done | record_cursor()}
          | {:error, term()}
  def next_records_page(
        %Cursor{
          game_id: game_id,
          query: query,
          maximum_row_id: maximum_row_id,
          last_row_id: last_row_id
        },
        page_size
      )
      when is_integer(page_size) and page_size > 0 do
    records_page(
      query,
      game_id,
      last_row_id,
      maximum_row_id,
      page_size
    )
  end

  def next_records_page(_cursor, _page_size) do
    {:error, :cursor_not_found}
  end

  @impl Analysis.GameRecordRepository
  def close_records(%Cursor{}) do
    :ok
  end

  def close_records(_cursor) do
    :ok
  end

  @impl Analysis.GameRecordRepository
  @spec query_page(
          GameRecordQuery.t(),
          pos_integer()
        ) ::
          {:ok, [GameRecord.t()], :done | query_cursor()}
          | {:error, term()}
  def query_page(false, page_size) when is_integer(page_size) and page_size > 0 do
    {
      :ok,
      [],
      :done
    }
  end

  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    with :ok <-
           validate_query(query),
         {:ok, maximum_row_id} <-
           maximum_query_row_id() do
      query_records_page(
        query,
        0,
        maximum_row_id,
        page_size
      )
    end
  end

  def query_page(_query, _page_size) do
    {:error, :invalid_record_query}
  end

  @impl Analysis.GameRecordRepository
  @spec next_query_page(
          query_cursor(),
          pos_integer()
        ) ::
          {:ok, [GameRecord.t()], :done | query_cursor()}
          | {:error, term()}
  def next_query_page(
        %QueryCursor{query: query, maximum_row_id: maximum_row_id, last_row_id: last_row_id},
        page_size
      )
      when is_integer(page_size) and page_size > 0 do
    query_records_page(
      query,
      last_row_id,
      maximum_row_id,
      page_size
    )
  end

  def next_query_page(_cursor, _page_size) do
    {:error, :cursor_not_found}
  end

  @impl Analysis.GameRecordRepository
  def close_query(%QueryCursor{}) do
    :ok
  end

  def close_query(_cursor) do
    :ok
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

  defp records_page(true, game_id, after_row_id, maximum_row_id, page_size) do
    requested_rows =
      page_size + 1

    case Repo.query(
           @records_page_sql,
           [
             game_id,
             after_row_id,
             maximum_row_id,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        build_page(
          true,
          game_id,
          maximum_row_id,
          rows,
          page_size
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp records_page(
         {:metadata_contains, metadata} = query,
         game_id,
         after_row_id,
         maximum_row_id,
         page_size
       ) do
    requested_rows =
      page_size + 1

    case Repo.query(
           @records_metadata_page_sql,
           [
             game_id,
             after_row_id,
             maximum_row_id,
             metadata,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        build_page(
          query,
          game_id,
          maximum_row_id,
          rows,
          page_size
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_page(_query, _game_id, _maximum_row_id, rows, page_size)
       when length(rows) <= page_size do
    {
      :ok,
      Enum.map(
        rows,
        &record_from_page_row/1
      ),
      :done
    }
  end

  defp build_page(query, game_id, maximum_row_id, rows, page_size) do
    {
      page_rows,
      _remaining_rows
    } =
      Enum.split(
        rows,
        page_size
      )

    last_row_id =
      page_rows
      |> List.last()
      |> hd()

    {
      :ok,
      Enum.map(
        page_rows,
        &record_from_page_row/1
      ),
      %Cursor{
        game_id: game_id,
        query: query,
        maximum_row_id: maximum_row_id,
        last_row_id: last_row_id
      }
    }
  end

  defp maximum_row_id(game_id) do
    case Repo.query(
           @maximum_row_id_sql,
           [game_id]
         ) do
      {:ok, %{rows: [[maximum_row_id]]}} ->
        {:ok, maximum_row_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp record_from_page_row([_row_id, record_id, game_id, fullmove_number, metadata]) do
    build_record(
      record_id,
      game_id,
      fullmove_number,
      metadata
    )
  end

  defp record_from_row([record_id, game_id, fullmove_number, metadata]) do
    build_record(
      record_id,
      game_id,
      fullmove_number,
      metadata
    )
  end

  defp build_record(record_id, game_id, fullmove_number, metadata) do
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
    with :ok <- validate_record_id(record_id),
         :ok <- validate_game_id(game_id),
         :ok <- validate_fullmove_number(fullmove_number) do
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

  defp validate_query(true) do
    :ok
  end

  defp validate_query(false) do
    :ok
  end

  defp validate_query({:metadata_contains, metadata}) do
    if GameRecord.valid_metadata?(metadata) do
      :ok
    else
      {:error, :invalid_record_query}
    end
  end

  defp validate_query(_query) do
    {:error, :invalid_record_query}
  end

  defp maximum_query_row_id do
    case Repo.query(
           @maximum_query_row_id_sql,
           []
         ) do
      {:ok, %{rows: [[maximum_row_id]]}} ->
        {:ok, maximum_row_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_records_page(true, after_row_id, maximum_row_id, page_size) do
    requested_rows =
      page_size + 1

    case Repo.query(
           @query_all_sql,
           [
             after_row_id,
             maximum_row_id,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        build_query_page(
          true,
          maximum_row_id,
          rows,
          page_size
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_records_page(
         {:metadata_contains, metadata} = query,
         after_row_id,
         maximum_row_id,
         page_size
       ) do
    requested_rows =
      page_size + 1

    case Repo.query(
           @query_metadata_contains_sql,
           [
             after_row_id,
             maximum_row_id,
             metadata,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        build_query_page(
          query,
          maximum_row_id,
          rows,
          page_size
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_query_page(_query, _maximum_row_id, rows, page_size)
       when length(rows) <= page_size do
    {
      :ok,
      Enum.map(
        rows,
        &record_from_page_row/1
      ),
      :done
    }
  end

  defp build_query_page(query, maximum_row_id, rows, page_size) do
    {
      page_rows,
      _remaining_rows
    } =
      Enum.split(
        rows,
        page_size
      )

    last_row_id =
      page_rows
      |> List.last()
      |> hd()

    {
      :ok,
      Enum.map(
        page_rows,
        &record_from_page_row/1
      ),
      %QueryCursor{
        query: query,
        maximum_row_id: maximum_row_id,
        last_row_id: last_row_id
      }
    }
  end
end
