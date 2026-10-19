defmodule Analysis.PositionTablebases do
  @moduledoc """
  Durable endgame tablebase results per canonical position.

  Results come from the public lichess tablebase API (`Web.Tablebase` makes
  the lookup). A position's outcome never changes, so every fetched result is
  written once and served from PostgreSQL afterwards — the external service
  sees one request per unique position, ever.
  """

  alias OpenChessLab.Repo

  @get_sql """
  SELECT result
  FROM position_tablebases
  WHERE position_id = $1
  """

  @put_sql """
  INSERT INTO position_tablebases (position_id, result, updated_at)
  VALUES ($1, $2::jsonb, now())
  ON CONFLICT (position_id) DO UPDATE SET
    result = EXCLUDED.result,
    updated_at = now()
  """

  @doc "The cached tablebase result for a position, if it was fetched before."
  @spec get(pos_integer()) :: {:ok, map()} | :not_found
  def get(position_id) when is_integer(position_id) do
    case Repo.query!(@get_sql, [position_id], log: false).rows do
      [[result]] ->
        :telemetry.execute(
          [:openchesslab, :tablebase, :lookup],
          %{count: 1},
          %{result: :hit}
        )

        {:ok, decode(result)}

      [] ->
        :telemetry.execute(
          [:openchesslab, :tablebase, :lookup],
          %{count: 1},
          %{result: :miss}
        )

        :not_found
    end
  end

  defp decode(result) when is_binary(result), do: Jason.decode!(result)
  defp decode(result) when is_map(result), do: result

  @doc "Store a fetched result; re-fetches replace the row in place."
  @spec put(pos_integer(), map()) :: :ok
  def put(position_id, result) when is_integer(position_id) and is_map(result) do
    Repo.query!(@put_sql, [position_id, result])
    :ok
  end
end
