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

defmodule Analysis.PositionRepository.Postgres do
  @moduledoc """
  PostgreSQL persistence for canonical chess positions.

  Position identity is the complete deterministic binary produced by
  `Chess.PositionCodec`.

  Canonical positions are immutable. Search features are derived and
  stored separately in `position_features`.
  """

  @behaviour Analysis.PositionRepository

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionRepository.Postgres.Query
  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.PositionProperties
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :query,
      :maximum_position_id,
      :last_position_id
    ]

    defstruct [
      :query,
      :maximum_position_id,
      :last_position_id
    ]
  end

  @type position_id :: pos_integer()
  @type query_cursor :: Cursor.t()

  @insert_position_sql """
  INSERT INTO positions (record)
  VALUES ($1)
  ON CONFLICT (record) DO NOTHING
  RETURNING id
  """

  @insert_features_sql """
  INSERT INTO position_features (
    position_id,
    properties
  )
  VALUES (
    $1,
    $2::bytea[]
  )
  ON CONFLICT (position_id) DO NOTHING
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

  @maximum_position_id_sql """
  SELECT COALESCE(max(id), 0)
  FROM positions
  """

  @impl Analysis.PositionRepository
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

  @impl Analysis.PositionRepository
  @spec put(Position.t()) ::
          {:ok, position_id()}
          | {:error, term()}
  def put(%Position{} = position) do
    Repo.transaction(fn ->
      with {:ok, position_id} <-
             put_position(position),
           {:ok, properties} <-
             encoded_properties(position),
           :ok <-
             put_features(
               position_id,
               properties
             ) do
        position_id
      else
        {:error, reason} ->
          Repo.rollback(reason)
      end
    end)
    |> case do
      {:ok, position_id} ->
        {:ok, position_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def put(_position) do
    {:error, :invalid_position}
  end

  @impl Analysis.PositionRepository
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

  @impl Analysis.PositionRepository
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

  @impl Analysis.PositionRepository
  def query_page(query, page_size) when is_integer(page_size) and page_size > 0 do
    with {:ok, maximum_position_id} <-
           maximum_position_id() do
      query_page(
        query,
        0,
        maximum_position_id,
        page_size
      )
    end
  end

  @impl Analysis.PositionRepository
  def next_query_page(
        %Cursor{
          query: query,
          maximum_position_id: maximum_position_id,
          last_position_id: last_position_id
        },
        page_size
      )
      when is_integer(page_size) and page_size > 0 do
    query_page(
      query,
      last_position_id,
      maximum_position_id,
      page_size
    )
  end

  def next_query_page(_cursor, _page_size) do
    {:error, :cursor_not_found}
  end

  @impl Analysis.PositionRepository
  def close_query(%Cursor{}) do
    :ok
  end

  def close_query(_cursor) do
    :ok
  end

  defp put_position(%Position{} = position) do
    record =
      PositionCodec.encode(position)

    case Repo.query(
           @insert_position_sql,
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

  defp put_features(position_id, properties) do
    case Repo.query(
           @insert_features_sql,
           [
             position_id,
             properties
           ]
         ) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encoded_properties(%Position{} = position) do
    properties =
      Enum.map(
        PositionProperties.open_files(position),
        &{:open_files, &1}
      ) ++
        [
          {
            :material,
            PositionProperties.material(position)
          }
        ]

    properties
    |> Enum.reduce_while(
      {:ok, []},
      fn {property, value}, {:ok, encoded_properties} ->
        case PositionPropertyKeyCodec.encode(
               property,
               value
             ) do
          {:ok, encoded_property} ->
            {:cont,
             {
               :ok,
               [
                 encoded_property
                 | encoded_properties
               ]
             }}

          {:error, reason} ->
            {:halt, {:error, reason}}
        end
      end
    )
    |> case do
      {:ok, encoded_properties} ->
        {:ok,
         encoded_properties
         |> Enum.reverse()
         |> Enum.uniq()}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp query_page(query, after_position_id, maximum_position_id, page_size) do
    requested_rows =
      page_size + 1

    with {:ok, sql, parameters} <-
           Query.compile(
             query,
             after_position_id,
             maximum_position_id,
             requested_rows
           ),
         {:ok, result} <-
           Repo.query(
             sql,
             parameters
           ) do
      position_ids =
        Enum.map(
          result.rows,
          fn [position_id] ->
            position_id
          end
        )

      build_page(
        query,
        maximum_position_id,
        position_ids,
        page_size
      )
    end
  end

  defp build_page(_query, _maximum_position_id, position_ids, page_size)
       when length(position_ids) <= page_size do
    {
      :ok,
      position_ids,
      :done
    }
  end

  defp build_page(query, maximum_position_id, position_ids, page_size) do
    {
      page,
      _remaining
    } =
      Enum.split(
        position_ids,
        page_size
      )

    last_position_id =
      List.last(page)

    {
      :ok,
      page,
      %Cursor{
        query: query,
        maximum_position_id: maximum_position_id,
        last_position_id: last_position_id
      }
    }
  end

  defp maximum_position_id do
    case Repo.query(
           @maximum_position_id_sql,
           []
         ) do
      {:ok, %{rows: [[maximum_position_id]]}} ->
        {:ok, maximum_position_id}

      {:error, reason} ->
        {:error, reason}
    end
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
