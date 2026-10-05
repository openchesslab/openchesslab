defmodule Analysis.GameRecordStore do
  @moduledoc """
  PostgreSQL persistence for concrete played-game records.

  Logical record identity is stored in `record_id`. PostgreSQL owns an
  independent monotonic row ID used internally for relational identity,
  indexing and keyset paging.

  Record listing uses stateless keyset paging. The first page captures
  a high-water row ID in the same PostgreSQL statement as the page,
  excluding records inserted after the scan starts.
  """

  alias Analysis.GameRecord
  alias Analysis.GameStart
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :maximum_record_row_id,
      :last_record_row_id
    ]

    defstruct [
      :maximum_record_row_id,
      :last_record_row_id
    ]

    @type t :: %__MODULE__{
            maximum_record_row_id: non_neg_integer(),
            last_record_row_id: pos_integer()
          }
  end

  defmodule Page do
    @moduledoc false

    @enforce_keys [
      :entries
    ]

    defstruct entries: [],
              next: nil

    @type t :: %__MODULE__{
            entries: [GameRecord.t()],
            next:
              Analysis.GameRecordStore.cursor()
              | nil
          }
  end

  @opaque cursor :: Cursor.t()

  @type page_result ::
          {:ok, Page.t()}
          | {:error, term()}

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

  @first_page_sql """
  SELECT
    COALESCE(
      (
        SELECT max(id)
        FROM game_records
      ),
      0
    )::bigint AS maximum_record_row_id,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM game_records AS gr
  ORDER BY
    gr.id
  LIMIT $1::bigint
  """

  @next_page_sql """
  SELECT
    $1::bigint AS maximum_record_row_id,
    gr.id,
    gr.record_id,
    gr.game_id,
    gr.fullmove_number,
    gr.metadata
  FROM game_records AS gr
  WHERE
    gr.id > $2::bigint
    AND gr.id <= $1::bigint
  ORDER BY
    gr.id
  LIMIT $3::bigint
  """

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

  @spec page(keyword()) ::
          page_result()
  def page(options) when is_list(options) do
    with {:ok, limit} <-
           fetch_limit(options),
         {:ok, cursor} <-
           fetch_cursor(options) do
      do_page(
        limit,
        cursor
      )
    end
  end

  def page(_options) do
    {:error, :invalid_page_options}
  end

  defp do_page(limit, nil) do
    requested_rows =
      limit + 1

    case Repo.query(
           @first_page_sql,
           [requested_rows]
         ) do
      {:ok, %{rows: rows}} ->
        {
          :ok,
          build_page(
            rows,
            limit
          )
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_page(limit, %Cursor{
         maximum_record_row_id: maximum_record_row_id,
         last_record_row_id: last_record_row_id
       }) do
    requested_rows =
      limit + 1

    case Repo.query(
           @next_page_sql,
           [
             maximum_record_row_id,
             last_record_row_id,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        {
          :ok,
          build_page(
            rows,
            limit
          )
        }

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_page(rows, limit) when length(rows) <= limit do
    %Page{
      entries:
        Enum.map(
          rows,
          &record_from_page_row/1
        )
    }
  end

  defp build_page(rows, limit) do
    {
      page_rows,
      _remaining_rows
    } =
      Enum.split(
        rows,
        limit
      )

    %Page{
      entries:
        Enum.map(
          page_rows,
          &record_from_page_row/1
        ),
      next:
        page_rows
        |> List.last()
        |> cursor_from_row()
    }
  end

  defp cursor_from_row([
         maximum_record_row_id,
         record_row_id,
         _record_id,
         _game_id,
         _fullmove_number,
         _metadata
       ]) do
    %Cursor{
      maximum_record_row_id: maximum_record_row_id,
      last_record_row_id: record_row_id
    }
  end

  defp record_from_page_row([
         _maximum_record_row_id,
         _record_row_id,
         record_id,
         game_id,
         fullmove_number,
         metadata
       ]) do
    record_from_row([
      record_id,
      game_id,
      fullmove_number,
      metadata
    ])
  end

  defp fetch_limit(options) do
    case Keyword.fetch(
           options,
           :limit
         ) do
      {:ok, limit}
      when is_integer(limit) and limit > 0 ->
        {:ok, limit}

      {:ok, _limit} ->
        {:error, :invalid_limit}

      :error ->
        {:error, :missing_limit}
    end
  end

  defp fetch_cursor(options) do
    case Keyword.get(
           options,
           :cursor
         ) do
      nil ->
        {:ok, nil}

      %Cursor{} = cursor ->
        {:ok, cursor}

      _cursor ->
        {:error, :invalid_cursor}
    end
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
