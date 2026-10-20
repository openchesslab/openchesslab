defmodule Analysis.DigestBackfill do
  @moduledoc """
  Fills `position_digests` for every stored position that lacks one.

  Resumable by construction (positions with a digest are skipped), chunked
  and parallel; failed positions are excluded for the rest of the run so a
  bad row cannot stall it. Run it on a worker machine, never in a request
  path:

      DATABASE_URL=... mix run -e 'IO.inspect(Analysis.DigestBackfill.run())'

  Within one run a high-water mark (`p.id > $3`) bounds every chunk query:
  without it each `NOT EXISTS` scan re-traverses the whole filled prefix,
  which made chunk queries exceed the connection timeout once most of the
  table was done. A fresh run still rescans from id 0 once (to pick up
  positions created or failed earlier), so the chunk query gets a generous
  timeout.

  Options: `:chunk_size` (1.000), `:workers` (schedulers), `:limit` (a
  bounded run, for verification).
  """

  alias Analysis.PositionDigests
  alias OpenChessLab.Repo

  require Logger

  @chunk_sql """
  SELECT p.id
  FROM positions AS p
  WHERE p.id > $3::bigint
  AND NOT EXISTS (
    SELECT 1
    FROM position_digests AS d
    WHERE d.position_id = p.id
  )
  AND NOT (p.id = ANY($2::bigint[]))
  ORDER BY p.id
  LIMIT $1
  """

  @max_failures 10_000

  @spec run(keyword()) :: %{computed: non_neg_integer(), failed: non_neg_integer()}
  def run(opts \\ []) do
    {:ok, _apps} = Application.ensure_all_started(:analysis)

    chunk_size = Keyword.get(opts, :chunk_size, 1_000)
    limit = Keyword.get(opts, :limit)
    workers = Keyword.get(opts, :workers, System.schedulers_online())

    do_run(%{computed: 0, failed: 0}, [], chunk_size, limit, workers, 0)
  end

  defp do_run(stats, failed_ids, chunk_size, limit, workers, last_id) do
    size =
      case limit do
        nil -> chunk_size
        n -> min(chunk_size, max(n - stats.computed - stats.failed, 0))
      end

    cond do
      size == 0 ->
        stats

      length(failed_ids) > @max_failures ->
        Logger.error("digest backfill: aborting after #{length(failed_ids)} failures")
        stats

      true ->
        ids =
          Repo.query!(@chunk_sql, [size, failed_ids, last_id], timeout: 120_000).rows
          |> List.flatten()

        case ids do
          [] ->
            stats

          ids ->
            {chunk_stats, chunk_failed} =
              ids
              |> Task.async_stream(
                fn id ->
                  result =
                    try do
                      PositionDigests.store_position_id(id)
                    rescue
                      _ -> :error
                    catch
                      _, _ -> :error
                    end

                  {id, result}
                end,
                max_concurrency: workers,
                ordered: false,
                timeout: 120_000
              )
              |> Enum.reduce(
                {%{computed: 0, failed: 0}, []},
                fn
                  {:ok, {_id, {:ok, _ids}}}, {acc, failed} ->
                    {%{acc | computed: acc.computed + 1}, failed}

                  {:ok, {id, _error}}, {acc, failed} ->
                    {%{acc | failed: acc.failed + 1}, [id | failed]}

                  {:exit, _reason}, {acc, failed} ->
                    {%{acc | failed: acc.failed + 1}, failed}
                end
              )

            stats = Map.merge(stats, chunk_stats, fn _key, left, right -> left + right end)
            Logger.info("digest backfill: #{stats.computed} computed, #{stats.failed} failed")

            do_run(stats, chunk_failed ++ failed_ids, chunk_size, limit, workers, Enum.max(ids))
        end
    end
  end
end
