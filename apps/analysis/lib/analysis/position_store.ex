defmodule Analysis.PositionStore do
  @moduledoc """
  PostgreSQL-native storage for canonical chess positions.

  Position identity is the complete deterministic binary produced by
  `Chess.PositionCodec`.

  Canonical positions are immutable. Search features are derived and
  stored separately in `position_features`.

  Position queries use stateless keyset paging. The first page captures
  a high-water position id in the same PostgreSQL statement as the page,
  excluding positions inserted after the scan starts.
  """

  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.Postgres, as: PostgresQuery
  alias Analysis.PositionQueryNormalizer
  alias Chess.Position
  alias Chess.PositionCodec
  alias Chess.PositionProperties
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :maximum_position_id,
      :last_position_id
    ]

    defstruct [
      :maximum_position_id,
      :last_position_id
    ]

    @type t :: %__MODULE__{
            maximum_position_id: non_neg_integer(),
            last_position_id: pos_integer()
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
            entries: [Analysis.PositionStore.position_id()],
            next:
              Analysis.PositionStore.cursor()
              | nil
          }
  end

  @type position_id :: pos_integer()
  @opaque cursor :: Cursor.t()

  @type page_result ::
          {:ok, Page.t()}
          | {:error, term()}

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

  @spec append(Position.t()) ::
          position_id()
          | {:error, term()}
  def append(%Position{} = position) do
    case put(position) do
      {:ok, position_id} ->
        position_id

      {:error, reason} ->
        {:error, reason}
    end
  end

  def append(_position) do
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

  @spec page(
          PositionQuery.t(),
          keyword()
        ) ::
          page_result()
  def page(query, options) when is_list(options) do
    normalized_query =
      PositionQueryNormalizer.normalize(query)

    with {:ok, limit} <-
           fetch_limit(options),
         {:ok, cursor} <-
           fetch_cursor(options) do
      do_page(
        normalized_query,
        limit,
        cursor
      )
    end
  end

  def page(_query, _options) do
    {:error, :invalid_page_options}
  end

  defp do_page(false, _limit, _cursor) do
    empty_page()
  end

  defp do_page(query, limit, nil) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           compile_first_page(
             query,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      {
        :ok,
        build_page(
          rows,
          limit
        )
      }
    end
  end

  defp do_page(query, limit, %Cursor{} = cursor) do
    requested_rows =
      limit + 1

    with {
           :ok,
           sql,
           parameters
         } <-
           compile_next_page(
             query,
             cursor,
             requested_rows
           ),
         {:ok, %{rows: rows}} <-
           Repo.query(
             sql,
             parameters
           ) do
      {
        :ok,
        build_page(
          rows,
          limit
        )
      }
    end
  end

  defp compile_first_page(query, limit) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           PostgresQuery.compile_predicate(
             query,
             1
           ) do
      limit_parameter =
        next_parameter

      sql = """
      SELECT
        COALESCE(
          (
            SELECT max(id)
            FROM positions
          ),
          0
        )::bigint AS maximum_position_id,
        p.id
      FROM positions AS p
      WHERE
        (#{predicate})
      ORDER BY
        p.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            limit
          ]
      }
    end
  end

  defp compile_next_page(
         query,
         %Cursor{maximum_position_id: maximum_position_id, last_position_id: last_position_id},
         limit
       ) do
    with {
           :ok,
           predicate,
           parameters,
           next_parameter
         } <-
           PostgresQuery.compile_predicate(
             query,
             1
           ) do
      maximum_parameter =
        next_parameter

      last_parameter =
        maximum_parameter + 1

      limit_parameter =
        last_parameter + 1

      sql = """
      SELECT
        $#{maximum_parameter}::bigint,
        p.id
      FROM positions AS p
      WHERE
        p.id > $#{last_parameter}::bigint
        AND p.id <= $#{maximum_parameter}::bigint
        AND (#{predicate})
      ORDER BY
        p.id
      LIMIT $#{limit_parameter}::bigint
      """

      {
        :ok,
        sql,
        parameters ++
          [
            maximum_position_id,
            last_position_id,
            limit
          ]
      }
    end
  end

  defp build_page(rows, limit) when length(rows) <= limit do
    %Page{
      entries:
        Enum.map(
          rows,
          fn [
               _maximum_position_id,
               position_id
             ] ->
            position_id
          end
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
          fn [
               _maximum_position_id,
               position_id
             ] ->
            position_id
          end
        ),
      next:
        page_rows
        |> List.last()
        |> cursor_from_row()
    }
  end

  defp cursor_from_row([maximum_position_id, position_id]) do
    %Cursor{
      maximum_position_id: maximum_position_id,
      last_position_id: position_id
    }
  end

  defp empty_page do
    {
      :ok,
      %Page{
        entries: []
      }
    }
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

  defp put(%Position{} = position) do
    transact(fn ->
      with {:ok, position_id, status} <-
             put_position(position),
           :ok <-
             put_features_if_needed(
               position,
               position_id,
               status
             ) do
        {:ok, position_id}
      end
    end)
  end

  defp put_position(%Position{} = position) do
    record =
      PositionCodec.encode(position)

    case Repo.query(
           @insert_position_sql,
           [record]
         ) do
      {:ok, %{rows: [[position_id]]}} ->
        {:ok, position_id, :inserted}

      {:ok, %{rows: []}} ->
        case find_record(record) do
          {:ok, position_id} ->
            {:ok, position_id, :existing}

          :not_found ->
            {:error, :position_not_found_after_conflict}

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_features_if_needed(position, position_id, :inserted) do
    with {:ok, properties} <-
           encoded_properties(position) do
      put_features(
        position_id,
        properties
      )
    end
  end

  defp put_features_if_needed(_position, _position_id, :existing) do
    :ok
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
      fn
        {
          property,
          value
        },
        {
          :ok,
          encoded_properties
        } ->
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

  defp transact(fun) when is_function(fun, 0) do
    if Repo.in_transaction?() do
      fun.()
    else
      Repo.transact(fun)
    end
  end
end
