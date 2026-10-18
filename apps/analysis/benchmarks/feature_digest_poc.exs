# Feature-digest POC (fase 2): bewijst de atoom-encodering + GIN-selectiviteit
# + querykosten van feature-zoeken op ~100K echte corpus-posities uit
# `openchesslab_bench`, vóór de volledige 19,7M-backfill wordt ingepland.
#
# Gebruik:
#   DATABASE_URL="ecto://openchesslab:openchesslab@localhost/openchesslab_bench" \
#     mix run apps/analysis/benchmarks/feature_digest_poc.exs -- [aantal posities]
#
# De POC-tabel `position_features_poc` wordt bij elke run opnieuw opgebouwd.

alias Analysis.{PositionFeatures, PositionStore}
alias Chess.Position
alias OpenChessLab.Repo

defmodule DigestPOC do
  @moduledoc false

  # Alleen intrinsieke, opsombare positiefeiten worden atomen. Sectie 21
  # (similarity) is een vergelijkingsfunctie en doet niet mee; numerieke en
  # map-waarden ook niet (later: buckets). Vierkantlijsten worden per veld een
  # atoom (`id:w` bij niet-leeg); alleen een gecureerde lijst met tactisch
  # betekenisvolle features krijgt per-veld-atomen (`id:w:d4`).
  @square_re ~r/^[a-h][1-8]$/
  @square_atom_ids ~w(
    quality.knight_outpost
    squares.occupied_outpost
    squares.enemy_on_outpost
    pawns.passed
    pawns.protected_passed
    tactics.pin
    tactics.absolute_pin
    tactics.relative_pin
    tactics.hanging_piece
    king.weak_shield_pawns
    pawns.levers
  )
  @presence_list_ids ~w(
    attacks.hanging
    goals.attack_isolated_pawn
    goals.blockade_isolated_pawn
    goals.pawn_storm
    motifs.exchange_sacrifice
    pawns.isolated
    pawns.iqp
    pawns.backward
    pawns.doubled
    pawns.minority_attack
    threats.mating_net
  )

  def atoms_for(features) do
    features
    |> Enum.flat_map(fn {id, value} -> feature_atoms(id, value) end)
    |> Kernel.++(material_signatures(features))
    |> Enum.uniq()
  end

  defp feature_atoms("similarity." <> _, _value), do: []
  defp feature_atoms("evaluation." <> _, _value), do: []
  defp feature_atoms("state.side_to_move", _value), do: []
  defp feature_atoms("state.en_passant", _value), do: []
  defp feature_atoms("state.castling_rights", _value), do: []
  defp feature_atoms("pawns.structure", _value), do: []

  defp feature_atoms(id, %{"white" => white, "black" => black}) do
    side_atoms(id, "w", white) ++ side_atoms(id, "b", black)
  end

  defp feature_atoms(id, value) when is_binary(value) do
    if square?(value), do: [id <> ":" <> value], else: []
  end

  defp feature_atoms(id, value) when is_list(value) do
    cond do
      id in @square_atom_ids and value != [] ->
        [id | Enum.map(value, &(id <> ":" <> &1))]

      id in @presence_list_ids and value != [] ->
        [id]

      true ->
        []
    end
  end

  defp feature_atoms(_id, _value), do: []

  defp side_atoms(id, side, true), do: [id <> ":" <> side]

  defp side_atoms(id, side, value) when is_binary(value) do
    if square?(value), do: [id <> ":" <> side <> ":" <> value], else: []
  end

  defp side_atoms(id, side, value) when is_list(value) do
    cond do
      id in @square_atom_ids and value != [] ->
        [id <> ":" <> side | Enum.map(value, &(id <> ":" <> side <> ":" <> &1))]

      id in @presence_list_ids and value != [] ->
        [id <> ":" <> side]

      true ->
        []
    end
  end

  defp side_atoms(_id, _side, _value), do: []

  defp square?(value), do: is_binary(value) and value =~ @square_re

  defp material_signatures(features) do
    for {side, prefix} <- [{"white", "w"}, {"black", "b"}] do
      [queen, rook, bishop, knight, pawn] =
        for piece <- ["queen", "rook", "bishop", "knight", "pawn"] do
          features
          |> Map.get("material.count." <> piece, %{})
          |> Map.get(side, 0)
        end

      "material.signature:#{prefix}:Q#{queen}R#{rook}B#{bishop}N#{knight}P#{pawn}"
    end
  end

  def row(id) do
    with {:ok, %Position{} = position} <- PositionStore.get(id),
         {:ok, result} <- PositionFeatures.extract(position) do
      %{position_id: id, atoms: atoms_for(result.features)}
    else
      _ -> nil
    end
  end

  def report(query, params \\ []) do
    Repo.query!(query, params).rows
  end

  def explain(label, query, params) do
    IO.puts("\n== #{label} ==")

    {micros, %{rows: plan}} =
      :timer.tc(fn -> Repo.query!("EXPLAIN (ANALYZE, BUFFERS) " <> query, params) end)

    IO.puts("planning+uitvoering: #{Float.round(micros / 1000, 1)} ms")

    plan
    |> Enum.map(&List.first/1)
    |> Enum.take(9)
    |> Enum.each(&IO.puts/1)
  end
end

Logger.configure(level: :warning)
Application.ensure_all_started(:database)

sample_size =
  case Enum.reject(System.argv(), &(&1 == "--")) do
    [n | _] -> String.to_integer(n)
    _ -> 100_000
  end

IO.puts("# Feature-digest POC: #{sample_size} posities")

Repo.query!("DROP TABLE IF EXISTS position_features_poc")

Repo.query!(
  "CREATE TABLE position_features_poc (position_id bigint PRIMARY KEY, atoms text[] NOT NULL)"
)

ids =
  Repo.query!("SELECT id FROM positions ORDER BY id LIMIT $1", [sample_size]).rows
  |> List.flatten()

started = System.monotonic_time(:millisecond)

{inserted, atom_total} =
  ids
  |> Enum.chunk_every(1_000)
  |> Enum.with_index(1)
  |> Enum.map_reduce({0, 0}, fn {chunk, batch}, {count, atoms} ->
    rows =
      chunk
      |> Task.async_stream(&DigestPOC.row/1,
        max_concurrency: System.schedulers_online(),
        ordered: false,
        timeout: 120_000
      )
      |> Enum.flat_map(fn
        {:ok, nil} -> []
        {:ok, row} -> [row]
      end)

    Repo.insert_all("position_features_poc", rows)

    count = count + length(rows)
    atoms = atoms + Enum.sum(Enum.map(rows, &length(&1.atoms)))

    if rem(batch, 10) == 0 do
      elapsed = System.monotonic_time(:millisecond) - started
      IO.puts("  #{count} posities, #{elapsed} ms (#{Float.round(count / max(elapsed / 1000, 1), 0)}/s)")
    end

    {nil, {count, atoms}}
  end)
  |> elem(1)

elapsed = System.monotonic_time(:millisecond) - started

IO.puts(
  "\nExtractie+insert: #{elapsed} ms → #{Float.round(inserted / (elapsed / 1000), 0)} posities/s " <>
    "(#{Float.round(elapsed / max(inserted, 1), 2)} ms/positie)"
)

IO.puts("Gemiddeld #{Float.round(atom_total / max(inserted, 1), 1)} atomen/positie")

[[avg, min, max]] =
  DigestPOC.report("SELECT avg(cardinality(atoms))::numeric(10,1), min(cardinality(atoms)), max(cardinality(atoms)) FROM position_features_poc")

IO.puts("Atomen/positie: avg #{avg}, min #{min}, max #{max}")

[[distinct]] =
  DigestPOC.report("SELECT count(DISTINCT atom) FROM (SELECT unnest(atoms) AS atom FROM position_features_poc) s")

IO.puts("Distincte atomen: #{distinct}")

IO.puts("\nTop 20 atomen (posting list):")

DigestPOC.report(
  "SELECT atom, count(*) FROM (SELECT unnest(atoms) AS atom FROM position_features_poc) s GROUP BY atom ORDER BY count DESC, atom LIMIT 20"
)
|> Enum.each(fn [atom, n] -> IO.puts("  #{n}\t#{atom}") end)

IO.puts("\nTactische/selectieve atomen:")

DigestPOC.report(
  "SELECT atom, count(*) FROM (SELECT unnest(atoms) AS atom FROM position_features_poc) s WHERE atom LIKE 'motifs.%' OR atom LIKE 'quality.knight_outpost%' OR atom LIKE 'tactics.pin%' GROUP BY atom ORDER BY count DESC, atom LIMIT 20"
)
|> Enum.each(fn [atom, n] -> IO.puts("  #{n}\t#{atom}") end)

{index_micros, _} =
  :timer.tc(fn ->
    Repo.query!(
      "CREATE INDEX position_features_poc_atoms_gin ON position_features_poc USING gin (atoms)"
    )
  end)

IO.puts("\nGIN-index gebouwd in #{div(index_micros, 1000)} ms")

[[table_size, index_size]] =
  DigestPOC.report(
    "SELECT pg_size_pretty(pg_relation_size('position_features_poc')), pg_size_pretty(pg_relation_size('position_features_poc_atoms_gin'))"
  )

IO.puts("Tabel: #{table_size}, GIN-index: #{index_size}")

DigestPOC.explain(
  "veelvoorkomend atoom (endgame_like)",
  "SELECT count(*) FROM position_features_poc WHERE atoms @> $1",
  [["position.endgame_like_position"]]
)

DigestPOC.explain(
  "middelzeldzaam atoom (loperpaar wit)",
  "SELECT count(*) FROM position_features_poc WHERE atoms @> $1",
  [["material.bishop_pair:w"]]
)

DigestPOC.explain(
  "zeldzaam atoom (Grieks offer zwart)",
  "SELECT count(*) FROM position_features_poc WHERE atoms @> $1",
  [["motifs.greek_gift:b"]]
)

DigestPOC.explain(
  "conjunctie van twee atomen",
  "SELECT count(*) FROM position_features_poc WHERE atoms @> $1",
  [["position.endgame_like_position", "material.bishop_pair:w"]]
)

DigestPOC.explain(
  "zoekvorm-join (atoom → occurrences → records, LIMIT 26)",
  """
  SELECT gr.id, go.ply
  FROM position_features_poc pf
  JOIN game_occurrences go ON go.position_id = pf.position_id
  JOIN game_records gr ON gr.game_id = go.game_id
  WHERE pf.atoms @> $1
  ORDER BY pf.position_id, go.id, gr.id
  LIMIT 26
  """,
  [["material.bishop_pair:w"]]
)

IO.puts("\nklaar")
