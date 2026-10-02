defmodule Analysis.AnalysisStore do
  @moduledoc """
  PostgreSQL persistence for analysis aggregates.

  Analysis identity and revision live in relational columns. The mutable
  aggregate itself is stored using `Analysis.AnalysisCodec`.

  Revision checks provide optimistic concurrency for updates and deletes.
  """

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisCodec
  alias OpenChessLab.Repo

  @registry Analysis.AnalysisStoreRegistry
  @registry_key :analysis_store

  @type store :: GenServer.server()
  @type revision :: pos_integer()

  # These callbacks remain temporarily while the legacy Memory/DETS
  # implementations still exist. They disappear together with those
  # implementations in the next cleanup slice.
  @callback insert(store(), AnalysisModel.t()) ::
              {:ok, revision()}
              | {:error, :already_exists}

  @callback get(store(), AnalysisModel.id()) ::
              {:ok, AnalysisModel.t(), revision()}
              | :not_found

  @callback list(store()) ::
              [{AnalysisModel.t(), revision()}]

  @callback update(store(), AnalysisModel.t(), revision()) ::
              {:ok, revision()}
              | {:error, :not_found | :conflict}

  @callback delete(store(), AnalysisModel.id(), revision()) ::
              :ok
              | {:error, :not_found | :conflict}

  @insert_sql """
  INSERT INTO analyses (
    analysis_id,
    revision,
    record
  )
  VALUES (
    $1,
    1,
    $2
  )
  ON CONFLICT (analysis_id) DO NOTHING
  RETURNING revision
  """

  @get_sql """
  SELECT
    record,
    revision
  FROM analyses
  WHERE analysis_id = $1
  """

  @list_sql """
  SELECT
    analysis_id,
    record,
    revision
  FROM analyses
  ORDER BY id
  """

  @update_sql """
  UPDATE analyses
  SET
    record = $2,
    revision = revision + 1
  WHERE
    analysis_id = $1
    AND revision = $3
  RETURNING revision
  """

  @delete_sql """
  DELETE FROM analyses
  WHERE
    analysis_id = $1
    AND revision = $2
  RETURNING revision
  """

  @revision_sql """
  SELECT revision
  FROM analyses
  WHERE analysis_id = $1
  """

  @spec clustered_store() :: GenServer.server()
  def clustered_store do
    {:via, Horde.Registry, {@registry, @registry_key}}
  end

  @doc """
  Temporary readiness check for the legacy AnalysisStore process.

  This remains only until the legacy AnalysisStore supervision is removed.
  PostgreSQL readiness itself belongs to `OpenChessLab.Repo.ready?/0`.
  """
  @spec ready?() :: boolean()
  def ready? do
    GenServer.call(
      legacy_store(),
      :ping,
      1_000
    ) == :ok
  rescue
    ArgumentError ->
      false
  catch
    :exit, _reason ->
      false
  end

  @spec insert(AnalysisModel.t()) ::
          {:ok, revision()}
          | {:error, :already_exists}
  def insert(%AnalysisModel{} = analysis) do
    record =
      encode_record!(analysis)

    case Repo.query!(
           @insert_sql,
           [
             analysis.id,
             record
           ]
         ).rows do
      [[revision]] ->
        {:ok, revision}

      [] ->
        {:error, :already_exists}
    end
  end

  @spec get(AnalysisModel.id()) ::
          {:ok, AnalysisModel.t(), revision()}
          | :not_found
  def get(analysis_id) when is_binary(analysis_id) and byte_size(analysis_id) > 0 do
    case Repo.query!(
           @get_sql,
           [analysis_id]
         ).rows do
      [[record, revision]] ->
        {
          :ok,
          decode_record!(
            analysis_id,
            record
          ),
          revision
        }

      [] ->
        :not_found
    end
  end

  def get(_analysis_id) do
    :not_found
  end

  @spec list() ::
          [{AnalysisModel.t(), revision()}]
  def list do
    @list_sql
    |> Repo.query!([])
    |> Map.fetch!(:rows)
    |> Enum.map(fn [
                     analysis_id,
                     record,
                     revision
                   ] ->
      {
        decode_record!(
          analysis_id,
          record
        ),
        revision
      }
    end)
  end

  @spec update(AnalysisModel.t(), revision()) ::
          {:ok, revision()}
          | {:error, :not_found | :conflict}
  def update(%AnalysisModel{} = analysis, expected_revision) do
    record =
      encode_record!(analysis)

    case Repo.query!(
           @update_sql,
           [
             analysis.id,
             record,
             expected_revision
           ]
         ).rows do
      [[revision]] ->
        {:ok, revision}

      [] ->
        write_miss(analysis.id)
    end
  end

  @spec delete(AnalysisModel.id(), revision()) ::
          :ok
          | {:error, :not_found | :conflict}
  def delete(analysis_id, expected_revision)
      when is_binary(analysis_id) and byte_size(analysis_id) > 0 do
    case Repo.query!(
           @delete_sql,
           [
             analysis_id,
             expected_revision
           ]
         ).rows do
      [[_revision]] ->
        :ok

      [] ->
        write_miss(analysis_id)
    end
  end

  def delete(_analysis_id, _expected_revision) do
    {:error, :not_found}
  end

  defp write_miss(analysis_id) do
    case Repo.query!(
           @revision_sql,
           [analysis_id]
         ).rows do
      [[_revision]] ->
        {:error, :conflict}

      [] ->
        {:error, :not_found}
    end
  end

  defp encode_record!(%AnalysisModel{} = analysis) do
    case AnalysisCodec.encode(analysis) do
      {:ok, record} ->
        record

      {:error, reason} ->
        raise ArgumentError,
              "cannot persist invalid analysis: #{inspect(reason)}"
    end
  end

  defp decode_record!(analysis_id, record) do
    case AnalysisCodec.decode(record) do
      {
        :ok,
        %AnalysisModel{
          id: ^analysis_id
        } = analysis
      } ->
        analysis

      {
        :ok,
        %AnalysisModel{}
      } ->
        raise ArgumentError,
              "stored analysis id does not match relational analysis id"

      {:error, reason} ->
        raise ArgumentError,
              "cannot decode stored analysis: #{inspect(reason)}"
    end
  end

  defp legacy_store do
    :analysis
    |> Application.get_env(
      __MODULE__,
      []
    )
    |> Keyword.get(
      :store,
      clustered_store()
    )
  end
end
