defmodule Analysis.Analyses do
  @moduledoc false

  alias Analysis.Node
  alias Analysis.AnalysisEvents
  alias Analysis.AnalysisStore
  alias Analysis.GameContent
  alias Analysis.GameRecord
  alias Analysis.GameRecords
  alias Analysis.PositionStore
  alias Analysis.Transition
  alias GameDB.Occurrence
  alias Chess.Move
  alias Chess.Position
  alias Chess.PositionDraft

  @type position_store_error ::
          {:position_store, term()}

  @type game_store_error ::
          {:game_store, term()}

  @spec create(
          Analysis.Analysis.id(),
          keyword()
        ) ::
          {:ok, Analysis.Analysis.t(), pos_integer()}
          | {:error,
             :already_exists
             | {:invalid_position, [atom()]}
             | position_store_error()}
  def create(
        analysis_id,
        opts \\ []
      ) do
    with {:ok, initial_position} <-
           initial_position(opts),
         {:ok, position_id} <-
           append_position(initial_position) do
      analysis =
        Analysis.Analysis.new(
          analysis_id,
          position_id
        )

      case insert(analysis) do
        {:ok, revision} ->
          {:ok, analysis, revision}

        {:error, :already_exists} = error ->
          error
      end
    end
  end

  defp initial_position(opts) do
    case Keyword.fetch(
           opts,
           :position
         ) do
      :error ->
        {:ok, Position.starting_position()}

      {:ok, position} ->
        case Position.validate(position) do
          :ok ->
            {:ok, position}

          {:error, reasons} ->
            {:error, {:invalid_position, reasons}}
        end
    end
  end

  @spec create_from_game_record(
          Analysis.Analysis.id(),
          GameRecord.id()
        ) ::
          {:ok, Analysis.Analysis.t(), pos_integer()}
          | {:error,
             :already_exists
             | :game_record_not_found
             | {:game_not_found, GameDB.game_id()}
             | game_store_error()}

  def create_from_game_record(
        analysis_id,
        game_record_id
      ) do
    case get(analysis_id) do
      {:ok, _analysis, _revision} ->
        {:error, :already_exists}

      :not_found ->
        do_create_from_game_record(
          analysis_id,
          game_record_id
        )
    end
  end

  @spec insert(Analysis.Analysis.t()) ::
          {:ok, pos_integer()} | {:error, :already_exists}
  def insert(%Analysis.Analysis{} = analysis) do
    AnalysisStore.insert(analysis)
  end

  @spec get(Analysis.Analysis.id()) ::
          {:ok, Analysis.Analysis.t(), pos_integer()} | :not_found
  def get(analysis_id) do
    AnalysisStore.get(analysis_id)
  end

  @spec list() :: [{Analysis.Analysis.t(), pos_integer()}]
  def list do
    AnalysisStore.list()
  end

  @spec play(Analysis.Analysis.id(), Analysis.Analysis.path(), Move.t()) ::
          {:ok, Analysis.Analysis.t(), pos_integer(), Analysis.Analysis.path()}
          | {:error,
             :analysis_not_found
             | :node_not_found
             | :position_not_found
             | :illegal_move
             | :conflict
             | position_store_error()}
  def play(analysis_id, path, %Move{} = move) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        play(analysis, revision, path, move)

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @spec edit(Analysis.Analysis.id(), Analysis.Analysis.path(), PositionDraft.t()) ::
          {:ok, Analysis.Analysis.t(), pos_integer(), Analysis.Analysis.path()}
          | {:error,
             :analysis_not_found
             | :node_not_found
             | {:invalid_position, [atom()]}
             | :conflict
             | position_store_error()}
  def edit(analysis_id, path, %PositionDraft{} = draft) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        edit(analysis, revision, path, draft)

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @spec set_nags(
          Analysis.Analysis.id(),
          Analysis.Analysis.path(),
          [Node.nag()]
        ) ::
          {:ok, Analysis.Analysis.t(), pos_integer()}
          | {:error,
             :analysis_not_found
             | :node_not_found
             | :invalid_nags
             | :conflict}
  def set_nags(
        analysis_id,
        path,
        nags
      ) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        set_nags(
          analysis,
          revision,
          path,
          nags
        )

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @spec set_comment(Analysis.Analysis.id(), Analysis.Analysis.path(), String.t() | nil) ::
          {:ok, Analysis.Analysis.t(), pos_integer()}
          | {:error, :analysis_not_found | :node_not_found | :conflict}
  def set_comment(analysis_id, path, comment) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        set_comment(analysis, revision, path, comment)

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @spec promote(Analysis.Analysis.id(), Analysis.Analysis.path()) ::
          {:ok, Analysis.Analysis.t(), pos_integer(), Analysis.Analysis.path()}
          | {:error, :analysis_not_found | :node_not_found | :root | :conflict}
  def promote(analysis_id, path) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        promote(analysis, revision, path)

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  @spec remove(Analysis.Analysis.id(), Analysis.Analysis.path()) ::
          {:ok, Analysis.Analysis.t(), pos_integer(), Analysis.Analysis.path()}
          | {:error, :analysis_not_found | :node_not_found | :root | :conflict}
  def remove(analysis_id, path) do
    case get(analysis_id) do
      {:ok, analysis, revision} ->
        remove(analysis, revision, path)

      :not_found ->
        {:error, :analysis_not_found}
    end
  end

  defp do_create_from_game_record(
         analysis_id,
         game_record_id
       ) do
    with {:ok, record, content, occurrences} <-
           load_game_record(game_record_id),
         {:ok, analysis} <-
           build_analysis(
             analysis_id,
             record,
             content,
             occurrences
           ),
         {:ok, revision} <-
           insert(analysis) do
      {:ok, analysis, revision}
    end
  end

  defp build_analysis(
         analysis_id,
         record,
         content,
         [
           %Occurrence{} = initial_occurrence
           | move_occurrences
         ]
       ) do
    analysis =
      Analysis.Analysis.new(
        analysis_id,
        initial_occurrence.position_id,
        GameRecord.id(record),
        GameRecord.start(record),
        %{}
      )

    analysis =
      content
      |> GameContent.moves()
      |> Enum.zip(move_occurrences)
      |> Enum.reduce(
        {
          analysis,
          []
        },
        fn {
             move,
             %Occurrence{
               position_id: position_id
             }
           },
           {
             analysis,
             path
           } ->
          analysis =
            Analysis.Analysis.add_child(
              analysis,
              path,
              Transition.move(move),
              position_id
            )

          {
            analysis,
            path ++ [0]
          }
        end
      )
      |> elem(0)

    {:ok, analysis}
  end

  defp set_nags(
         analysis,
         revision,
         path,
         nags
       ) do
    with {:ok, updated_analysis} <-
           Analysis.Analysis.set_nags(
             analysis,
             path,
             nags
           ),
         {:ok, new_revision} <-
           persist(
             updated_analysis,
             revision
           ) do
      {:ok, updated_analysis, new_revision}
    end
  end

  defp set_comment(analysis, revision, path, comment) do
    with {:ok, updated_analysis} <- Analysis.Analysis.set_comment(analysis, path, comment),
         {:ok, new_revision} <- persist(updated_analysis, revision) do
      {:ok, updated_analysis, new_revision}
    end
  end

  defp play(
         analysis,
         revision,
         path,
         move
       ) do
    with %Node{} = node <-
           Analysis.Analysis.node_at(
             analysis,
             path
           ),
         {:ok, position} <-
           get_position(Node.position_id(node)),
         {:ok, next_position} <-
           Position.apply_move(
             position,
             move
           ),
         {:ok, position_id} <-
           append_position(next_position) do
      transition =
        Transition.move(move)

      updated_analysis =
        Analysis.Analysis.add_child(
          analysis,
          path,
          transition,
          position_id
        )

      child_index =
        updated_analysis
        |> Analysis.Analysis.node_at(path)
        |> Node.child_index(
          transition,
          position_id
        )

      resulting_path =
        path ++ [child_index]

      case persist(
             updated_analysis,
             revision
           ) do
        {:ok, new_revision} ->
          {:ok, updated_analysis, new_revision, resulting_path}

        {:error, _reason} = error ->
          error
      end
    else
      nil ->
        {:error, :node_not_found}

      :not_found ->
        {:error, :position_not_found}

      {:error, :illegal_move} = error ->
        error

      {:error, {:position_store, _reason}} = error ->
        error
    end
  end

  defp promote(analysis, revision, path) do
    with {:ok, updated_analysis, resulting_path} <- Analysis.Analysis.promote(analysis, path),
         {:ok, new_revision} <- persist(updated_analysis, revision) do
      {:ok, updated_analysis, new_revision, resulting_path}
    end
  end

  defp persist(analysis, revision) do
    case AnalysisStore.update(analysis, revision) do
      {:ok, new_revision} ->
        :ok = AnalysisEvents.publish_changed(analysis.id)
        {:ok, new_revision}

      {:error, :conflict} ->
        {:error, :conflict}

      {:error, :not_found} ->
        {:error, :analysis_not_found}
    end
  end

  defp remove(analysis, revision, path) do
    with {:ok, updated_analysis, resulting_path} <- Analysis.Analysis.remove(analysis, path),
         {:ok, new_revision} <- persist(updated_analysis, revision) do
      {:ok, updated_analysis, new_revision, resulting_path}
    end
  end

  defp edit(
         analysis,
         revision,
         path,
         draft
       ) do
    with %Node{} <-
           Analysis.Analysis.node_at(
             analysis,
             path
           ),
         {:ok, position} <-
           PositionDraft.apply(draft),
         {:ok, position_id} <-
           append_position(position) do
      transition =
        Transition.edit()

      updated_analysis =
        Analysis.Analysis.add_child(
          analysis,
          path,
          transition,
          position_id
        )

      child_index =
        updated_analysis
        |> Analysis.Analysis.node_at(path)
        |> Node.child_index(
          transition,
          position_id
        )

      resulting_path =
        path ++ [child_index]

      case persist(
             updated_analysis,
             revision
           ) do
        {:ok, new_revision} ->
          {:ok, updated_analysis, new_revision, resulting_path}

        {:error, _reason} = error ->
          error
      end
    else
      nil ->
        {:error, :node_not_found}

      {:error, {:position_store, _reason}} = error ->
        error

      {:error, reasons} ->
        {:error, {:invalid_position, reasons}}
    end
  end

  defp append_position(position) do
    case PositionStore.append(position) do
      position_id
      when is_integer(position_id) and
             position_id > 0 ->
        {:ok, position_id}

      {:error, reason} ->
        {:error, {:position_store, reason}}
    end
  end

  defp get_position(position_id) do
    case PositionStore.get(position_id) do
      {:ok, position} ->
        {:ok, position}

      :not_found ->
        :not_found

      {:error, reason} ->
        {:error, {:position_store, reason}}
    end
  end

  defp load_game_record(game_record_id) do
    case GameRecords.load(game_record_id) do
      {
        :ok,
        %GameRecord{} = record,
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
        {:error, :game_record_not_found}

      {:error, _reason} = error ->
        error
    end
  end
end
