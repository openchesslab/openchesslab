defmodule Analysis.PositionDigests do
  @moduledoc """
  Per-position digest atoms for feature search, keyed by position id.

  Digests are derived from feature vectors: written alongside them (the
  same extraction, no recompute) and by the bulk backfill. The
  `{:digests, ...}` position-query term reads them.
  """

  alias Analysis.FeatureDigest
  alias Analysis.PositionFeatures
  alias Analysis.PositionStore
  alias OpenChessLab.Repo

  @upsert_sql """
  INSERT INTO position_digests (position_id, atom_ids)
  VALUES ($1, $2::integer[])
  ON CONFLICT (position_id) DO UPDATE SET atom_ids = EXCLUDED.atom_ids
  """

  @fetch_sql """
  SELECT atom_ids
  FROM position_digests
  WHERE position_id = $1
  """

  @doc """
  Encode a feature map to atoms, resolve their ids and upsert the digest.
  """
  @spec store_features(PositionStore.position_id(), %{String.t() => term()}) ::
          {:ok, [integer()]} | {:error, term()}
  def store_features(position_id, features)
      when is_integer(position_id) and position_id > 0 and is_map(features) do
    ids =
      features
      |> FeatureDigest.atoms()
      |> FeatureDigest.ids_for()

    case Repo.query(@upsert_sql, [position_id, ids]) do
      {:ok, _result} -> {:ok, ids}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Extract and persist the digest for a stored position id.
  """
  @spec store_position_id(PositionStore.position_id()) ::
          {:ok, [integer()]} | :not_found | {:error, term()}
  def store_position_id(position_id) do
    with {:ok, result} <- PositionFeatures.extract_position_id(position_id) do
      store_features(position_id, result.features)
    end
  end

  @doc """
  Read the persisted digest of a stored position id.
  """
  @spec fetch(PositionStore.position_id()) ::
          {:ok, [integer()]} | :not_found | {:error, term()}
  def fetch(position_id) when is_integer(position_id) and position_id > 0 do
    case Repo.query(@fetch_sql, [position_id]) do
      {:ok, %{rows: [[atom_ids]]}} -> {:ok, atom_ids}
      {:ok, %{rows: []}} -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  def fetch(_position_id), do: :not_found
end
