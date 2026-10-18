defmodule Analysis.FeatureDigest do
  @moduledoc """
  Digest atoms for feature search: which catalogue facts become searchable
  atoms, and how atom strings map to stable database ids.

  Only intrinsic, enumerable position facts become atoms. Section 21
  (similarity) is a comparison function and stays out, as do numeric and
  map-shaped values (bucketing is later work). Square lists default to a
  presence atom (`id:w` when non-empty); a curated set of tactically
  meaningful features additionally yields per-square atoms (`id:w:d4`).

  Ids live in the `feature_atoms` dictionary and are assigned lazily at
  first sight (`ON CONFLICT DO NOTHING`, then re-read). The table is
  append-only: a stored digest's ids must never change meaning. An atom
  unknown to the dictionary resolves to `:unknown` — a search for it
  honestly matches nothing.
  """

  alias OpenChessLab.Repo

  @cache_key {__MODULE__, :ids}

  @square_re ~r/^[a-h][1-8]$/

  # Tactically meaningful list features: presence atom plus one atom per
  # square.
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

  # Selective strategic list features: presence atom only.
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

  # Measured ≥90% of positions on the 100K POC: true so often that the atom
  # has no selectivity (and bloats the index).
  @pruned_ids ~w(
    tactics.zwischenzug_possibilities
  )

  @doc """
  The digest atoms of a feature map (`%{feature_id => value}`, as produced
  by `Features.extract/2`).
  """
  @spec atoms(%{String.t() => term()}) :: [String.t()]
  def atoms(features) when is_map(features) do
    features
    |> Enum.flat_map(fn {id, value} -> feature_atoms(id, value) end)
    |> Kernel.++(material_signatures(features))
    |> Enum.uniq()
  end

  @doc """
  Resolve atom strings to dictionary ids, registering unseen atoms. Answer
  order matches the dictionary, not the input.
  """
  @spec ids_for([String.t()]) :: [integer()]
  def ids_for(atoms) when is_list(atoms) do
    cache = cache()

    {known, missing} =
      Enum.split_with(atoms, &Map.has_key?(cache, &1))

    registered =
      case missing do
        [] ->
          cache

        _ ->
          register(missing)
      end

    atoms
    |> Enum.uniq()
    |> Enum.map(&Map.fetch!(registered, &1))
  end

  @doc """
  The dictionary id of one atom, or `:unknown` when no position can have it.
  """
  @spec id_of(String.t()) :: integer() | :unknown
  def id_of(atom) when is_binary(atom) do
    case Map.get(cache(), atom) do
      nil -> lookup(atom)
      id -> id
    end
  end

  @doc """
  The dictionary as `%{id => atom}` (for the search UI's feature picker).
  """
  @spec labels() :: %{integer() => String.t()}
  def labels do
    cache()
    |> Map.new(fn {atom, id} -> {id, atom} end)
  end

  @doc false
  @spec reload_cache() :: %{String.t() => integer()}
  def reload_cache, do: load_cache()

  # ── encoding ──────────────────────────────────────────────────────────────

  defp feature_atoms("similarity." <> _, _value), do: []
  defp feature_atoms("evaluation." <> _, _value), do: []
  defp feature_atoms("state.side_to_move", _value), do: []
  defp feature_atoms("state.en_passant", _value), do: []
  defp feature_atoms("state.castling_rights", _value), do: []
  defp feature_atoms("pawns.structure", _value), do: []

  defp feature_atoms(id, _value) when id in @pruned_ids, do: []

  defp feature_atoms(id, %{"white" => white, "black" => black}) do
    side_atoms(id, "w", white) ++ side_atoms(id, "b", black)
  end

  defp feature_atoms(id, true), do: [id]
  defp feature_atoms(_id, false), do: []

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

  defp square?(value), do: value =~ @square_re

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

  # ── dictionary ────────────────────────────────────────────────────────────

  defp cache do
    case :persistent_term.get(@cache_key, :cold) do
      :cold -> load_cache()
      cache -> cache
    end
  end

  defp load_cache do
    %{rows: rows} = Repo.query!("SELECT atom, id FROM feature_atoms")

    cache = Map.new(rows, fn [atom, id] -> {atom, id} end)
    :persistent_term.put(@cache_key, cache)
    cache
  end

  defp lookup(atom) do
    case Repo.query!("SELECT id FROM feature_atoms WHERE atom = $1", [atom]).rows do
      [[id]] -> id
      [] -> :unknown
    end
  end

  defp register(missing) do
    rows = Enum.map(Enum.uniq(missing), &%{atom: &1})

    Repo.insert_all("feature_atoms", rows, on_conflict: :nothing)

    load_cache()
  end
end
