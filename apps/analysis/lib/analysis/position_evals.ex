defmodule Analysis.PositionEvals do
  @moduledoc """
  Durable engine evaluations per canonical position.

  Evaluations are computed by client-side Stockfish workers and shared through
  PostgreSQL: one member's browser computes, every room and session sees the
  result. Rows are keyed by position and engine identity, so an engine upgrade
  never masquerades as an older engine's work. Writes are deepest-wins: a
  shallower result never overwrites a deeper one. Each row carries every
  computed line (`lines`, one per MultiPV slot, as
  `%{"multipv", "score_cp" | "score_mate", "pv"}`) plus the top line
  denormalized for the evaluation bar and graph; `multipv` records how many
  lines were computed, so a cached result only covers requests it can serve.
  """

  alias OpenChessLab.Repo

  @get_sql """
  SELECT depth, eval_cp, mate, best_move, pv, nodes, multipv, lines
  FROM position_evals
  WHERE position_id = $1 AND engine = $2
  """

  @get_many_sql """
  SELECT position_id, depth, eval_cp, mate, best_move, pv, nodes, multipv, lines
  FROM position_evals
  WHERE position_id = ANY($1::bigint[]) AND engine = $2
  """

  # Deepest wins: an equal-depth refresh updates the row, a shallower one does not.
  @put_sql """
  INSERT INTO position_evals (
    position_id, engine, depth, eval_cp, mate, best_move, pv, nodes, multipv, lines, updated_at
  )
  VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10::jsonb, now())
  ON CONFLICT (position_id, engine) DO UPDATE SET
    depth = EXCLUDED.depth,
    eval_cp = EXCLUDED.eval_cp,
    mate = EXCLUDED.mate,
    best_move = EXCLUDED.best_move,
    pv = EXCLUDED.pv,
    nodes = EXCLUDED.nodes,
    multipv = EXCLUDED.multipv,
    lines = EXCLUDED.lines,
    updated_at = now()
  WHERE position_evals.depth <= EXCLUDED.depth
  """

  @type line :: %{optional(String.t()) => integer() | String.t()}

  @type eval :: %{
          required(:depth) => non_neg_integer(),
          optional(:eval_cp) => integer() | nil,
          optional(:mate) => integer() | nil,
          optional(:best_move) => String.t() | nil,
          optional(:pv) => String.t() | nil,
          optional(:nodes) => non_neg_integer() | nil,
          optional(:multipv) => pos_integer(),
          optional(:lines) => [line()]
        }

  @spec get(integer(), String.t()) :: {:ok, eval()} | :not_found
  def get(position_id, engine) when is_integer(position_id) and is_binary(engine) do
    case Repo.query!(@get_sql, [position_id, engine], log: false).rows do
      [[depth, eval_cp, mate, best_move, pv, nodes, multipv, lines]] ->
        {:ok,
         %{
           depth: depth,
           eval_cp: eval_cp,
           mate: mate,
           best_move: best_move,
           pv: pv,
           nodes: nodes,
           multipv: multipv,
           lines: decode_lines(lines)
         }}

      [] ->
        :not_found
    end
  end

  @doc "Cached evaluations for many positions at once, as `%{position_id => eval}`."
  @spec get_many([integer()], String.t()) :: %{integer() => eval()}
  def get_many(position_ids, engine) when is_list(position_ids) and is_binary(engine) do
    Repo.query!(@get_many_sql, [Enum.uniq(position_ids), engine], log: false).rows
    |> Map.new(fn [position_id, depth, eval_cp, mate, best_move, pv, nodes, multipv, lines] ->
      {position_id,
       %{
         depth: depth,
         eval_cp: eval_cp,
         mate: mate,
         best_move: best_move,
         pv: pv,
         nodes: nodes,
         multipv: multipv,
         lines: decode_lines(lines)
       }}
    end)
  end

  @doc """
  Store an evaluation; a deeper existing evaluation wins over the new one.
  Single-line callers may pass just the top line fields; `lines` defaults to
  that one line.
  """
  @spec put(integer(), String.t(), eval()) :: :ok
  def put(position_id, engine, eval)
      when is_integer(position_id) and is_binary(engine) and is_integer(eval.depth) do
    lines =
      Map.get(eval, :lines) ||
        [
          %{
            "multipv" => 1,
            "score_cp" => Map.get(eval, :eval_cp),
            "score_mate" => Map.get(eval, :mate),
            "pv" => Map.get(eval, :pv)
          }
          |> Enum.reject(fn {_key, value} -> is_nil(value) end)
          |> Map.new()
        ]

    Repo.query!(
      @put_sql,
      [
        position_id,
        engine,
        eval.depth,
        Map.get(eval, :eval_cp),
        Map.get(eval, :mate),
        Map.get(eval, :best_move),
        Map.get(eval, :pv),
        Map.get(eval, :nodes),
        Map.get(eval, :multipv) || 1,
        lines
      ],
      log: false
    )

    :ok
  end

  defp decode_lines(lines) when is_binary(lines), do: Jason.decode!(lines)
  defp decode_lines(lines) when is_list(lines), do: lines
end
