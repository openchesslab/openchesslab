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

  alias Analysis.PositionPawnStructureCodec
  alias Analysis.PositionPropertyKeyCodec
  alias Analysis.PositionQuery
  alias Analysis.PositionQuery.PostgresPage
  alias Analysis.PositionQueryNormalizer
  alias Chess.PawnStructure
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

  @put_position_sql """
  WITH inserted AS (
    INSERT INTO positions (
      record,
      white_pawns,
      black_pawns
    )
    VALUES (
      $1,
      $2,
      $3
    )
    ON CONFLICT (record) DO NOTHING
    RETURNING id
  )
  SELECT
    id,
    TRUE AS inserted
  FROM inserted

  UNION ALL

  SELECT
    id,
    FALSE AS inserted
  FROM positions
  WHERE record = $1

  LIMIT 1
  """

  @insert_positions_sql """
  INSERT INTO positions (
    record,
    white_pawns,
    black_pawns
  )
  SELECT DISTINCT
    input.record,
    input.white_pawns,
    input.black_pawns
  FROM unnest(
    $1::bytea[],
    $2::bigint[],
    $3::bigint[]
  ) AS input(
    record,
    white_pawns,
    black_pawns
  )
  ORDER BY
    input.record
  ON CONFLICT (record) DO NOTHING
  RETURNING
    id,
    record
  """

  @find_position_ids_sql """
  SELECT
    p.id
  FROM unnest($1::bytea[])
    WITH ORDINALITY AS input(record, ordinality)
  JOIN positions AS p
    ON p.record = input.record
  ORDER BY
    input.ordinality
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

  @spec append_many([Position.t()]) ::
          {:ok, [position_id()]}
          | {:error, term()}
  def append_many([]) do
    {:ok, []}
  end

  def append_many(positions) when is_list(positions) do
    if Enum.all?(
         positions,
         &match?(%Position{}, &1)
       ) do
      put_many(positions)
    else
      {:error, :invalid_position}
    end
  end

  def append_many(_positions) do
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
    PostgresPage.compile_first(
      query,
      limit
    )
  end

  defp compile_next_page(
         query,
         %Cursor{maximum_position_id: maximum_position_id, last_position_id: last_position_id},
         limit
       ) do
    PostgresPage.compile_next(
      query,
      maximum_position_id,
      last_position_id,
      limit
    )
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

  defp put_many(positions) do
    with {:ok, encoded_positions} <-
           encode_positions(positions) do
      records =
        Enum.map(
          encoded_positions,
          fn
            {
              record,
              _position,
              _white_pawns,
              _black_pawns
            } ->
              record
          end
        )

      white_pawns =
        Enum.map(
          encoded_positions,
          fn
            {
              _record,
              _position,
              white_pawns,
              _black_pawns
            } ->
              white_pawns
          end
        )

      black_pawns =
        Enum.map(
          encoded_positions,
          fn
            {
              _record,
              _position,
              _white_pawns,
              black_pawns
            } ->
              black_pawns
          end
        )

      positions_by_record =
        Map.new(
          encoded_positions,
          fn
            {
              record,
              position,
              _white_pawns,
              _black_pawns
            } ->
              {
                record,
                position
              }
          end
        )

      transact(fn ->
        with {:ok, inserted_rows} <-
               insert_positions(
                 records,
                 white_pawns,
                 black_pawns
               ),
             :ok <-
               put_inserted_features(
                 inserted_rows,
                 positions_by_record
               ) do
          find_position_ids(records)
        end
      end)
    end
  end

  defp put_position(%Position{} = position) do
    with {:ok,
          {
            record,
            _position,
            white_pawns,
            black_pawns
          }} <-
           encode_position(position) do
      case Repo.query(
             @put_position_sql,
             [
               record,
               white_pawns,
               black_pawns
             ]
           ) do
        {:ok,
         %{
           rows: [
             [
               position_id,
               true
             ]
           ]
         }} ->
          {:ok, position_id, :inserted}

        {:ok,
         %{
           rows: [
             [
               position_id,
               false
             ]
           ]
         }} ->
          {:ok, position_id, :existing}

        {:ok, %{rows: []}} ->
          resolve_concurrent_position(record)

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp insert_positions(records, white_pawns, black_pawns) do
    case Repo.query(
           @insert_positions_sql,
           [
             records,
             white_pawns,
             black_pawns
           ]
         ) do
      {:ok, %{rows: rows}} ->
        {:ok, rows}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_positions(positions) do
    positions
    |> Enum.reduce_while(
      {
        :ok,
        []
      },
      fn
        %Position{} = position,
        {
          :ok,
          encoded_positions
        } ->
          case encode_position(position) do
            {:ok, encoded_position} ->
              {:cont,
               {
                 :ok,
                 [
                   encoded_position
                   | encoded_positions
                 ]
               }}

            {:error, reason} ->
              {:halt,
               {
                 :error,
                 reason
               }}
          end
      end
    )
    |> case do
      {
        :ok,
        encoded_positions
      } ->
        {:ok, Enum.reverse(encoded_positions)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp encode_position(%Position{} = position) do
    structure =
      PawnStructure.from_position(position)

    with {:ok,
          {
            white_pawns,
            black_pawns
          }} <-
           PositionPawnStructureCodec.encode(structure) do
      {:ok,
       {
         PositionCodec.encode(position),
         position,
         white_pawns,
         black_pawns
       }}
    end
  end

  defp find_position_ids(records) do
    expected_count =
      length(records)

    case Repo.query(
           @find_position_ids_sql,
           [records]
         ) do
      {:ok,
       %{
         rows: rows
       }}
      when length(rows) == expected_count ->
        {:ok,
         Enum.map(
           rows,
           fn [position_id] ->
             position_id
           end
         )}

      {:ok, %{rows: rows}} ->
        {:error,
         {
           :unexpected_position_count,
           expected_count,
           length(rows)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp resolve_concurrent_position(record) do
    case find_record(record) do
      {:ok, position_id} ->
        {:ok, position_id, :existing}

      :not_found ->
        {:error, :position_not_found_after_conflict}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp put_inserted_features(inserted_rows, positions_by_record) do
    Enum.reduce_while(
      inserted_rows,
      :ok,
      fn
        [
          position_id,
          record
        ],
        :ok ->
          with {:ok, position} <-
                 Map.fetch(
                   positions_by_record,
                   record
                 ),
               {:ok, properties} <-
                 encoded_properties(position),
               :ok <-
                 put_features(
                   position_id,
                   properties
                 ) do
            {:cont, :ok}
          else
            :error ->
              {:halt,
               {
                 :error,
                 :inserted_position_not_in_batch
               }}

            {:error, reason} ->
              {:halt,
               {
                 :error,
                 reason
               }}
          end
      end
    )
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
    semi_open_files =
      PositionProperties.semi_open_files(position)

    outposts = PositionProperties.outposts(position)

    checks = PositionProperties.in_check(position)

    properties =
      Enum.map(
        PositionProperties.open_files(position),
        &{:open_files, &1}
      ) ++
        Enum.flat_map(
          [:white, :black],
          fn color ->
            semi_open_files
            |> Map.fetch!(color)
            |> Enum.map(fn file ->
              {:semi_open_files, {color, file}}
            end)
          end
        ) ++
        Enum.flat_map(
          [:white, :black],
          fn color ->
            outposts
            |> Map.fetch!(color)
            |> Enum.map(fn square ->
              {:outposts, {color, square}}
            end)
          end
        ) ++
        Enum.flat_map(
          [:white, :black],
          fn color ->
            if Map.fetch!(checks, color) do
              [{:in_check, color}]
            else
              []
            end
          end
        ) ++
        [
          {
            :material,
            PositionProperties.material(position)
          },
          {:side_to_move, position.side_to_move}
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
