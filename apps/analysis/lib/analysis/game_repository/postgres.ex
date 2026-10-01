defmodule Analysis.GameRepository.Postgres do
  @moduledoc """
  PostgreSQL persistence for canonical chess games and their occurrences.

  Fingerprints are non-unique lookup keys. Exact game identity is established
  by comparing the complete deterministic `Analysis.GameContentCodec` record.

  New-game insertion and occurrence insertion happen in one PostgreSQL
  transaction. A transaction-level advisory lock serializes writers for one
  fingerprint bucket so concurrent inserts cannot create duplicate exact
  content while still allowing distinct games with the same fingerprint.

  Occurrence paging is stateless keyset paging over occurrence IDs and captures
  a maximum occurrence ID when the scan starts, so later inserts are excluded
  from an already-open scan.
  """

  @behaviour Analysis.GameRepository

  alias Analysis.GameContent
  alias Analysis.GameContentCodec
  alias Analysis.GameFingerprint
  alias Analysis.GameOccurrence
  alias OpenChessLab.Repo

  defmodule Cursor do
    @moduledoc false

    @enforce_keys [
      :position_id,
      :maximum_occurrence_id,
      :last_occurrence_id
    ]

    defstruct [
      :position_id,
      :maximum_occurrence_id,
      :last_occurrence_id
    ]

    @type t :: %__MODULE__{
            position_id: pos_integer(),
            maximum_occurrence_id: non_neg_integer(),
            last_occurrence_id: pos_integer()
          }
  end

  @type game_id :: pos_integer()
  @type occurrence_id :: pos_integer()
  @type occurrence_cursor :: Cursor.t()

  @fingerprint_size GameFingerprint.fingerprint_size()
  @max_bigint 9_223_372_036_854_775_807

  @lock_fingerprint_sql """
  SELECT pg_advisory_xact_lock($1)
  """

  @insert_game_sql """
  INSERT INTO games (
    fingerprint,
    content
  )
  VALUES (
    $1,
    $2
  )
  RETURNING id
  """

  @insert_occurrences_sql """
  INSERT INTO game_occurrences (
    game_id,
    ply,
    position_id
  )
  SELECT
    $1,
    occurrence.ordinality - 1,
    occurrence.position_id
  FROM unnest($2::bigint[])
    WITH ORDINALITY AS occurrence(position_id, ordinality)
  ORDER BY occurrence.ordinality
  """

  @find_sql """
  SELECT id
  FROM games
  WHERE fingerprint = $1
    AND content = $2
  ORDER BY id
  LIMIT 1
  """

  @get_sql """
  SELECT content
  FROM games
  WHERE id = $1
  """

  @game_exists_sql """
  SELECT EXISTS(
    SELECT 1
    FROM games
    WHERE id = $1
  )
  """

  @occurrences_sql """
  SELECT
    id,
    game_id,
    ply,
    position_id
  FROM game_occurrences
  WHERE game_id = $1
  ORDER BY ply
  """

  @get_occurrence_sql """
  SELECT
    id,
    game_id,
    ply,
    position_id
  FROM game_occurrences
  WHERE id = $1
  """

  @maximum_occurrence_id_sql """
  SELECT COALESCE(max(id), 0)
  FROM game_occurrences
  WHERE position_id = $1
  """

  @occurrence_page_sql """
  SELECT
    id,
    game_id,
    ply,
    position_id
  FROM game_occurrences
  WHERE position_id = $1
    AND id > $2
    AND id <= $3
  ORDER BY id
  LIMIT $4
  """

  @impl Analysis.GameRepository
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

  @impl Analysis.GameRepository
  @spec put(
          GameFingerprint.t(),
          GameContent.t(),
          [pos_integer()]
        ) ::
          {:ok, game_id()}
          | {:error, term()}
  def put(fingerprint, %GameContent{} = content, position_ids) do
    with :ok <- validate_fingerprint(fingerprint),
         {:ok, encoded_content} <- GameContentCodec.encode(content),
         :ok <- validate_position_ids(content, position_ids) do
      Repo.transaction(fn ->
        with :ok <- lock_fingerprint(fingerprint),
             {:ok, game_id} <-
               put_game(
                 fingerprint,
                 encoded_content,
                 position_ids
               ) do
          game_id
        else
          {:error, reason} ->
            Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, game_id} ->
          {:ok, game_id}

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  def put(_fingerprint, _content, _position_ids) do
    {:error, :invalid_game_content}
  end

  @impl Analysis.GameRepository
  @spec find(
          GameFingerprint.t(),
          GameContent.t()
        ) ::
          {:ok, game_id()}
          | :not_found
          | {:error, term()}
  def find(fingerprint, %GameContent{} = content) do
    with :ok <- validate_fingerprint(fingerprint),
         {:ok, encoded_content} <- GameContentCodec.encode(content) do
      find_record(
        fingerprint,
        encoded_content
      )
    end
  end

  def find(_fingerprint, _content) do
    {:error, :invalid_game_content}
  end

  @impl Analysis.GameRepository
  @spec get(game_id()) ::
          {:ok, GameContent.t()}
          | :not_found
          | {:error, term()}
  def get(game_id) when is_integer(game_id) and game_id > 0 do
    case Repo.query(
           @get_sql,
           [game_id]
         ) do
      {:ok, %{rows: [[content]]}} ->
        decode_content(content)

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get(_game_id) do
    :not_found
  end

  @impl Analysis.GameRepository
  @spec occurrences(game_id()) ::
          {:ok, [GameOccurrence.t()]}
          | :not_found
          | {:error, term()}
  def occurrences(game_id) when is_integer(game_id) and game_id > 0 do
    case Repo.query(
           @occurrences_sql,
           [game_id]
         ) do
      {:ok, %{rows: []}} ->
        empty_occurrences_result(game_id)

      {:ok, %{rows: rows}} ->
        {:ok,
         Enum.map(
           rows,
           &occurrence_from_row/1
         )}

      {:error, reason} ->
        {:error, reason}
    end
  end

  def occurrences(_game_id) do
    :not_found
  end

  @impl Analysis.GameRepository
  @spec occurrences_page(
          pos_integer(),
          pos_integer()
        ) ::
          {:ok, [GameOccurrence.t()], :done | occurrence_cursor()}
          | {:error, term()}
  def occurrences_page(position_id, page_size)
      when is_integer(position_id) and position_id > 0 and is_integer(page_size) and page_size > 0 do
    with {:ok, maximum_occurrence_id} <-
           maximum_occurrence_id(position_id) do
      occurrence_page(
        position_id,
        0,
        maximum_occurrence_id,
        page_size
      )
    end
  end

  def occurrences_page(_position_id, _page_size) do
    {:error, :invalid_occurrence_page}
  end

  @impl Analysis.GameRepository
  @spec next_occurrences_page(
          occurrence_cursor(),
          pos_integer()
        ) ::
          {:ok, [GameOccurrence.t()], :done | occurrence_cursor()}
          | {:error, term()}
  def next_occurrences_page(
        %Cursor{
          position_id: position_id,
          maximum_occurrence_id: maximum_occurrence_id,
          last_occurrence_id: last_occurrence_id
        },
        page_size
      )
      when is_integer(page_size) and page_size > 0 do
    occurrence_page(
      position_id,
      last_occurrence_id,
      maximum_occurrence_id,
      page_size
    )
  end

  def next_occurrences_page(_cursor, _page_size) do
    {:error, :cursor_not_found}
  end

  @impl Analysis.GameRepository
  def close_occurrences(%Cursor{}) do
    :ok
  end

  def close_occurrences(_cursor) do
    :ok
  end

  @impl Analysis.GameRepository
  @spec get_occurrence(occurrence_id()) ::
          {:ok, GameOccurrence.t()}
          | :not_found
          | {:error, term()}
  def get_occurrence(occurrence_id) when is_integer(occurrence_id) and occurrence_id > 0 do
    case Repo.query(
           @get_occurrence_sql,
           [occurrence_id]
         ) do
      {:ok, %{rows: [row]}} ->
        {:ok, occurrence_from_row(row)}

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_occurrence(_occurrence_id) do
    :not_found
  end

  defp put_game(fingerprint, encoded_content, position_ids) do
    case find_record(
           fingerprint,
           encoded_content
         ) do
      {:ok, game_id} ->
        {:ok, game_id}

      :not_found ->
        insert_game(
          fingerprint,
          encoded_content,
          position_ids
        )

      {:error, _reason} = error ->
        error
    end
  end

  defp insert_game(fingerprint, encoded_content, position_ids) do
    case Repo.query(
           @insert_game_sql,
           [
             fingerprint,
             encoded_content
           ]
         ) do
      {:ok, %{rows: [[game_id]]}} ->
        with :ok <-
               insert_occurrences(
                 game_id,
                 position_ids
               ) do
          {:ok, game_id}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp insert_occurrences(game_id, position_ids) do
    expected_count =
      length(position_ids)

    case Repo.query(
           @insert_occurrences_sql,
           [
             game_id,
             position_ids
           ]
         ) do
      {:ok, %{num_rows: ^expected_count}} ->
        :ok

      {:ok, %{num_rows: actual_count}} ->
        {:error,
         {
           :unexpected_occurrence_count,
           expected_count,
           actual_count
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp find_record(fingerprint, encoded_content) do
    case Repo.query(
           @find_sql,
           [
             fingerprint,
             encoded_content
           ]
         ) do
      {:ok, %{rows: [[game_id]]}} ->
        {:ok, game_id}

      {:ok, %{rows: []}} ->
        :not_found

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp lock_fingerprint(fingerprint) do
    case Repo.query(
           @lock_fingerprint_sql,
           [advisory_lock_key(fingerprint)]
         ) do
      {:ok, _result} ->
        :ok

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp advisory_lock_key(<<key::signed-big-integer-size(64), _remaining::binary>>) do
    key
  end

  defp empty_occurrences_result(game_id) do
    case game_exists?(game_id) do
      {:ok, true} ->
        {:ok, []}

      {:ok, false} ->
        :not_found

      {:error, _reason} = error ->
        error
    end
  end

  defp game_exists?(game_id) do
    case Repo.query(
           @game_exists_sql,
           [game_id]
         ) do
      {:ok, %{rows: [[exists?]]}} ->
        {:ok, exists?}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp occurrence_page(position_id, after_occurrence_id, maximum_occurrence_id, page_size) do
    requested_rows =
      page_size + 1

    case Repo.query(
           @occurrence_page_sql,
           [
             position_id,
             after_occurrence_id,
             maximum_occurrence_id,
             requested_rows
           ]
         ) do
      {:ok, %{rows: rows}} ->
        occurrences =
          Enum.map(
            rows,
            &occurrence_from_row/1
          )

        build_page(
          position_id,
          maximum_occurrence_id,
          occurrences,
          page_size
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_page(_position_id, _maximum_occurrence_id, occurrences, page_size)
       when length(occurrences) <= page_size do
    {
      :ok,
      occurrences,
      :done
    }
  end

  defp build_page(position_id, maximum_occurrence_id, occurrences, page_size) do
    {
      page,
      _remaining
    } =
      Enum.split(
        occurrences,
        page_size
      )

    last_occurrence_id =
      page
      |> List.last()
      |> Map.fetch!(:id)

    {
      :ok,
      page,
      %Cursor{
        position_id: position_id,
        maximum_occurrence_id: maximum_occurrence_id,
        last_occurrence_id: last_occurrence_id
      }
    }
  end

  defp maximum_occurrence_id(position_id) do
    case Repo.query(
           @maximum_occurrence_id_sql,
           [position_id]
         ) do
      {:ok, %{rows: [[maximum_occurrence_id]]}} ->
        {:ok, maximum_occurrence_id}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp occurrence_from_row([id, game_id, ply, position_id]) do
    GameOccurrence.new(
      id,
      game_id,
      ply,
      position_id
    )
  end

  defp decode_content(content) do
    case GameContentCodec.decode(content) do
      {:ok, %GameContent{} = game_content} ->
        {:ok, game_content}

      {:error, reason} ->
        {:error,
         {
           :invalid_game_record,
           reason
         }}
    end
  end

  defp validate_fingerprint(fingerprint)
       when is_binary(fingerprint) and byte_size(fingerprint) == @fingerprint_size do
    :ok
  end

  defp validate_fingerprint(_fingerprint) do
    {:error, :invalid_fingerprint}
  end

  defp validate_position_ids(%GameContent{} = content, position_ids) when is_list(position_ids) do
    expected_count =
      length(GameContent.moves(content)) + 1

    cond do
      position_ids == [] ->
        {:error, :missing_initial_position}

      not Enum.all?(
        position_ids,
        &valid_position_id?/1
      ) ->
        {:error, :invalid_position_ids}

      length(position_ids) != expected_count ->
        {:error, :invalid_occurrences}

      hd(position_ids) != GameContent.initial_position_id(content) ->
        {:error, :invalid_occurrences}

      true ->
        :ok
    end
  end

  defp validate_position_ids(_content, _position_ids) do
    {:error, :invalid_position_ids}
  end

  defp valid_position_id?(position_id) do
    is_integer(position_id) and
      position_id > 0 and
      position_id <= @max_bigint
  end
end
