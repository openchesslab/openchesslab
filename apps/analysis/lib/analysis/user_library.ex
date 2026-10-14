defmodule Analysis.UserLibrary do
  @moduledoc """
  A user's saved analyses. Room stars track live references to the room's own
  analysis; branching into another room or private editing materializes separate
  copies. Removing a reference does not delete the underlying analysis or remove
  it from another user's library.

  Callers must authenticate and authorize the user before invoking this API.
  """

  alias Analysis.Analyses
  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisCodec
  alias Analysis.AnalysisStore
  alias OpenChessLab.Repo

  @doc "Read only this user's personal library title, without loading an analysis tree."
  def title(user_id, analysis_id) when is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        case Repo.query!(
               "SELECT title FROM user_analyses WHERE user_id = $1 AND analysis_id = $2",
               [db_id, analysis_id]
             ).rows do
          [[title]] -> {:ok, title}
          [] -> :not_found
        end

      _ ->
        :not_found
    end
  end

  def title(_, _), do: :not_found

  @doc "Rename this user's saved reference only. Blank titles clear the personal label."
  def rename(user_id, analysis_id, title) when is_binary(analysis_id) and is_binary(title) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         true <- String.valid?(title),
         title = title |> String.replace(~r/\s+/u, " ") |> String.trim(),
         true <- length(String.codepoints(title)) <= 120 do
      title = if title != "", do: title

      case Repo.query!(
             "UPDATE user_analyses SET title = $3 WHERE user_id = $1 AND analysis_id = $2 RETURNING id",
             [db_id, analysis_id, title]
           ).rows do
        [[_]] -> :ok
        [] -> :not_found
      end
    else
      _ -> {:error, :invalid_title}
    end
  end

  def rename(_, _, _), do: {:error, :invalid_title}

  @doc "Read a personal analysis: this user's reference, no room or other user's reference."
  def get_private(user_id, analysis_id) do
    case with_private(user_id, analysis_id, fn -> AnalysisStore.get(analysis_id) end) do
      {:error, :analysis_not_found} -> :not_found
      result -> result
    end
  end

  @doc "Edit a personal analysis while locking its access scope and checking the displayed revision."
  def edit_private(user_id, analysis_id, revision, path, command) do
    with_private(user_id, analysis_id, fn ->
      case AnalysisStore.get(analysis_id) do
        {:ok, _analysis, ^revision} -> private_command(analysis_id, path, command)
        {:ok, _, _} -> {:error, :conflict}
      end
    end)
  end

  defp private_command(id, path, {:play, %Chess.Move{} = move}), do: Analyses.play(id, path, move)

  defp private_command(id, path, {:comment, text}) when is_binary(text),
    do: Analyses.set_comment(id, path, text)

  defp private_command(id, path, {:nags, nags}) when is_list(nags),
    do: Analyses.set_nags(id, path, nags)

  defp private_command(id, path, :promote), do: Analyses.promote(id, path)
  defp private_command(id, path, :remove), do: Analyses.remove(id, path)
  defp private_command(_, _, _), do: {:error, :invalid_command}

  @shared_sql """
  SELECT EXISTS (SELECT 1 FROM room_analyses WHERE analysis_id = $2),
         EXISTS (SELECT 1 FROM user_analyses WHERE analysis_id = $2 AND user_id <> $1)
  """

  @doc """
  Open a library entry for private work, branching a live reference once.

  When the entry still refers to shared work — an analysis that lives in a
  room or that another user's library references — this materializes an
  independent private copy, repoints the entry to it and returns the copy's
  id. Branching is idempotent: later opens of the same entry continue the
  private copy. The room's analysis and other users' references keep the
  original untouched. Entries that are already private open unchanged.
  Callers authenticate the user; this is not an authorization boundary.
  """
  @spec open_private(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_identity | :analysis_not_found}
  def open_private(user_id, analysis_id) when is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.transaction(fn ->
          case Repo.query!(
                 "SELECT id FROM user_analyses WHERE user_id = $1 AND analysis_id = $2 FOR UPDATE",
                 [db_id, analysis_id],
                 log: false
               ).rows do
            [] ->
              Repo.rollback(:analysis_not_found)

            [[_id]] ->
              [[room_shared, other_referenced]] =
                Repo.query!(@shared_sql, [db_id, analysis_id], log: false).rows

              if room_shared or other_referenced,
                do: branch_reference(db_id, analysis_id),
                else: analysis_id
          end
        end)

      :error ->
        {:error, :invalid_identity}
    end
  end

  def open_private(_, _), do: {:error, :invalid_identity}

  defp with_private(user_id, analysis_id, operation) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id), true <- is_binary(analysis_id) do
      # FOR UPDATE also blocks new FK references while the private scope is
      # checked. The library row lock holds access through a concurrent removal.
      case Repo.transaction(fn ->
             if Repo.query!(
                  "SELECT analysis_id FROM analyses WHERE analysis_id = $1 FOR UPDATE",
                  [analysis_id]
                ).rows == [] do
               Repo.rollback(:analysis_not_found)
             end

             if Repo.query!(
                  "SELECT id FROM user_analyses WHERE user_id = $1 AND analysis_id = $2 FOR SHARE",
                  [db_id, analysis_id]
                ).rows == [] do
               Repo.rollback(:analysis_not_found)
             end

             [[shared]] =
               Repo.query!(
                 "SELECT EXISTS (SELECT 1 FROM room_analyses WHERE analysis_id = $2) OR EXISTS (SELECT 1 FROM user_analyses WHERE analysis_id = $2 AND user_id <> $1)",
                 [db_id, analysis_id]
               ).rows

             if shared, do: Repo.rollback(:analysis_not_found)

             case operation.() do
               {:error, reason} -> Repo.rollback(reason)
               result -> result
             end
           end) do
        {:ok, result} -> result
        {:error, reason} -> {:error, reason}
      end
    else
      _ -> {:error, :analysis_not_found}
    end
  end

  @room_source_sql """
  SELECT a.analysis_id
  FROM room_analyses AS ra
  JOIN analyses AS a ON a.analysis_id = ra.analysis_id
  WHERE ra.room_id = $1 AND ra.analysis_id = $2
  FOR SHARE OF ra, a
  """

  @track_sql """
  INSERT INTO user_analyses (user_id, analysis_id)
  VALUES ($1, $2)
  ON CONFLICT (user_id, analysis_id) DO NOTHING
  RETURNING id
  """

  @doc """
  Track a room analysis in this user's library as a live reference.

  The caller authenticates the user and authorizes access to the room; the
  transaction checks durable membership and holds it through the insert. No
  copy is made: the library entry is the room's own analysis, so work in the
  room is reflected in the library while the analysis exists. Branching —
  copying into another room or private editing — happens separately and
  explicitly. Nothing is added to the room or broadcast. Idempotent.
  """
  @spec track_from_room(String.t(), String.t(), String.t()) ::
          {:ok, :tracked | :already_tracked}
          | {:error, :invalid_identity | :user_not_found | :analysis_not_found}
  def track_from_room(user_id, room_id, analysis_id)
      when is_binary(room_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.transaction(fn ->
          if Repo.query!("SELECT id FROM users WHERE id = $1 FOR KEY SHARE", [db_id]).rows == [] do
            Repo.rollback(:user_not_found)
          end

          if Repo.query!(@room_source_sql, [room_id, analysis_id]).rows == [] do
            Repo.rollback(:analysis_not_found)
          end

          case Repo.query!(@track_sql, [db_id, analysis_id], log: false).rows do
            [[_id]] -> :tracked
            [] -> :already_tracked
          end
        end)

      :error ->
        {:error, :invalid_identity}
    end
  end

  def track_from_room(_, _, _), do: {:error, :invalid_identity}

  @doc "Return which of the given analyses this user's library already references."
  @spec tracked(String.t(), [String.t()]) :: [String.t()]
  def tracked(user_id, analysis_ids) when is_binary(user_id) and is_list(analysis_ids) do
    if analysis_ids == [] do
      []
    else
      case Ecto.UUID.dump(user_id) do
        {:ok, db_id} ->
          Repo.query!(
            "SELECT analysis_id FROM user_analyses WHERE user_id = $1 AND analysis_id = ANY($2)",
            [db_id, analysis_ids],
            log: false
          ).rows
          |> Enum.map(fn [id] -> id end)

        :error ->
          []
      end
    end
  end

  def tracked(_, _), do: []

  @own_record_sql """
  SELECT a.record
  FROM user_analyses AS ua
  JOIN analyses AS a ON a.analysis_id = ua.analysis_id
  WHERE ua.user_id = $1 AND ua.analysis_id = $2
  FOR SHARE OF ua, a
  """

  @doc """
  Branch only the underlying game of the user's library entry into a fresh analysis.

  The fresh analysis contains the game's start position and canonical main line
  without the entry's variations, comments or NAGs, so private analysis stays
  private. Entries without an underlying game fail with `:game_not_available`.
  The caller authenticates the user and owns the room flow that adds the fresh
  analysis to a room.
  """
  @spec branch_game(String.t(), String.t()) ::
          {:ok, String.t()}
          | {:error, :invalid_identity | :analysis_not_found | :game_not_available | term()}
  def branch_game(user_id, analysis_id) when is_binary(analysis_id) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         {:ok, record} <- owned_record(db_id, analysis_id),
         {:ok, game_record_id} <- source_game_record_id(record) do
      id = fresh_analysis_id()

      case Analyses.create_from_game_record(id, game_record_id) do
        {:ok, _analysis, _revision} -> {:ok, id}
        {:error, reason} -> {:error, reason}
      end
    else
      :error -> {:error, :invalid_identity}
      {:error, _reason} = error -> error
    end
  end

  def branch_game(_, _), do: {:error, :invalid_identity}

  @doc """
  Branch the user's library entry into an independent snapshot copy.

  The fresh copy preserves all variations, comments, NAGs, start context,
  metadata and source-game reference. Later work in the room never flows back
  into the entry, and the original keeps its identity: other users' references
  to it are untouched. The caller authenticates the user and owns the room flow.
  """
  @spec branch_analysis(String.t(), String.t()) ::
          {:ok, String.t()} | {:error, :invalid_identity | :analysis_not_found}
  def branch_analysis(user_id, analysis_id) when is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.transaction(fn ->
          case Repo.query!(@own_record_sql, [db_id, analysis_id], log: false).rows do
            [[record]] ->
              with {:ok, analysis} <- AnalysisCodec.decode(record),
                   id = fresh_analysis_id(),
                   {:ok, _revision} <- AnalysisStore.insert(%{analysis | id: id}) do
                id
              else
                _other -> Repo.rollback(:analysis_not_found)
              end

            [] ->
              Repo.rollback(:analysis_not_found)
          end
        end)

      :error ->
        {:error, :invalid_identity}
    end
  end

  def branch_analysis(_, _), do: {:error, :invalid_identity}

  @doc """
  Verify that the user's library entry exists, permitting the caller to share its
  analysis live with a room. Live sharing keeps the analysis's identity: work in
  the room appears in the library entry and in every other user's reference to
  it. The caller authenticates the user and owns the room flow and its broadcast.
  """
  @spec authorize_share(String.t(), String.t()) ::
          :ok | {:error, :invalid_identity | :analysis_not_found}
  def authorize_share(user_id, analysis_id) when is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        if Repo.query!(
             "SELECT 1 FROM user_analyses WHERE user_id = $1 AND analysis_id = $2",
             [db_id, analysis_id],
             log: false
           ).rows == [] do
          {:error, :analysis_not_found}
        else
          :ok
        end

      :error ->
        {:error, :invalid_identity}
    end
  end

  def authorize_share(_, _), do: {:error, :invalid_identity}

  defp owned_record(db_id, analysis_id) do
    case Repo.query!(@own_record_sql, [db_id, analysis_id], log: false).rows do
      [[record]] -> {:ok, record}
      [] -> {:error, :analysis_not_found}
    end
  end

  defp source_game_record_id(record) do
    case AnalysisCodec.decode(record) do
      {:ok, %AnalysisModel{source_game_record_id: game_record_id}}
      when not is_nil(game_record_id) ->
        {:ok, game_record_id}

      _other ->
        {:error, :game_not_available}
    end
  end

  defp fresh_analysis_id do
    "analysis-" <> Base.url_encode64(:crypto.strong_rand_bytes(16), padding: false)
  end

  defp branch_reference(db_id, analysis_id) do
    case Repo.query!("SELECT record FROM analyses WHERE analysis_id = $1", [analysis_id],
           log: false
         ).rows do
      [[record]] ->
        with {:ok, analysis} <- AnalysisCodec.decode(record),
             fresh_id = fresh_analysis_id(),
             {:ok, _revision} <- AnalysisStore.insert(%{analysis | id: fresh_id}) do
          result =
            Repo.query!(
              "UPDATE user_analyses SET analysis_id = $3 WHERE user_id = $1 AND analysis_id = $2",
              [db_id, analysis_id, fresh_id],
              log: false
            )

          if result.num_rows == 1, do: fresh_id, else: Repo.rollback(:analysis_not_found)
        else
          _other -> Repo.rollback(:analysis_not_found)
        end

      [] ->
        Repo.rollback(:analysis_not_found)
    end
  end

  @save_sql """
  INSERT INTO user_analyses (user_id, analysis_id)
  SELECT users.id, analyses.analysis_id
  FROM users CROSS JOIN analyses
  WHERE users.id = $1 AND analyses.analysis_id = $2
  ON CONFLICT (user_id, analysis_id) DO NOTHING
  RETURNING id
  """

  @exists_sql """
  SELECT EXISTS (SELECT 1 FROM users WHERE id = $1),
         EXISTS (SELECT 1 FROM analyses WHERE analysis_id = $2)
  """

  @list_sql """
  SELECT analysis_id FROM user_analyses
  WHERE user_id = $1
  ORDER BY created_at, id
  """

  @remove_sql """
  DELETE FROM user_analyses WHERE user_id = $1 AND analysis_id = $2
  RETURNING id
  """

  @doc "Idempotently save a reference to an existing analysis."
  @spec save(String.t(), String.t()) ::
          :ok | {:error, :user_not_found | :analysis_not_found | :invalid_identity}
  def save(user_id, analysis_id) when is_binary(user_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        case Repo.query!(@save_sql, [db_id, analysis_id]).rows do
          [[_id]] ->
            :ok

          [] ->
            [[user_exists, analysis_exists]] = Repo.query!(@exists_sql, [db_id, analysis_id]).rows

            cond do
              not user_exists -> {:error, :user_not_found}
              not analysis_exists -> {:error, :analysis_not_found}
              true -> :ok
            end
        end

      :error ->
        {:error, :invalid_identity}
    end
  end

  def save(_, _), do: {:error, :invalid_identity}

  @spec list(String.t()) :: [String.t()]
  def list(user_id) when is_binary(user_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        Repo.query!(@list_sql, [db_id]).rows |> Enum.map(fn [analysis_id] -> analysis_id end)

      :error ->
        []
    end
  end

  def list(_), do: []

  @doc "Read at most 50 saved references with underlying-game availability, using the existing user/analysis unique index for keyset paging."
  @spec page(String.t(), String.t() | nil) :: %{entries: [map()], next_cursor: String.t() | nil}
  def page(user_id, after_id \\ nil) do
    with {:ok, db_id} <- Ecto.UUID.dump(user_id),
         true <- is_nil(after_id) or is_binary(after_id) do
      {predicate, params} =
        if is_nil(after_id),
          do: {"", [db_id]},
          else: {" AND ua.analysis_id > $2", [db_id, after_id]}

      rows =
        Repo.query!(
          "SELECT ua.analysis_id, ua.created_at, ua.title, a.record FROM user_analyses AS ua JOIN analyses AS a ON a.analysis_id = ua.analysis_id WHERE ua.user_id = $1" <>
            predicate <> " ORDER BY ua.analysis_id LIMIT 51",
          params
        ).rows

      entries =
        for [id, saved_at, title, record] <- Enum.take(rows, 50) do
          game_record_id =
            case AnalysisCodec.decode(record) do
              {:ok, %AnalysisModel{source_game_record_id: game_record_id}} -> game_record_id
              _other -> nil
            end

          %{id: id, saved_at: saved_at, title: title, game_record_id: game_record_id}
        end

      cursor = if length(rows) > 50, do: List.last(entries).id
      %{entries: entries, next_cursor: cursor}
    else
      _ -> %{entries: [], next_cursor: nil}
    end
  end

  @doc "Remove only this user's saved reference, never the analysis."
  @spec remove(String.t(), String.t()) :: :ok | :not_found
  def remove(user_id, analysis_id) when is_binary(user_id) and is_binary(analysis_id) do
    case Ecto.UUID.dump(user_id) do
      {:ok, db_id} ->
        case Repo.query!(@remove_sql, [db_id, analysis_id]).rows do
          [[_id]] -> :ok
          [] -> :not_found
        end

      :error ->
        :not_found
    end
  end

  def remove(_, _), do: :not_found
end
