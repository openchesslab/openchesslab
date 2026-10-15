defmodule OpenChessLab.Repo.Migrations.AddOpenings do
  use Ecto.Migration

  @moduledoc """
  ECO opening classification from the CC0 lichess-org/chess-openings dataset
  (vendored as TSV under priv/openings). Each entry's PGN line is replayed
  through the chess rules and keyed by the canonical position encoding, the
  same `positions.record` identity used everywhere else.
  """

  @spec up() :: term()
  def up do
    create table(:openings, primary_key: false) do
      add :position_record, :binary, null: false
      add :eco, :text, null: false
      add :name, :text, null: false
    end

    create unique_index(:openings, [:position_record])

    flush()

    seed()
  end

  def down do
    drop(table(:openings))
  end

  defp seed do
    openings_dir = Path.join(:code.priv_dir(:database), "openings")

    entries =
      for volume <- ~w(a b c d e), entry <- read_volume(openings_dir, volume) do
        entry
      end

    # More specific lines win when positions collide across entries.
    entries
    |> Enum.sort_by(fn {_record, _eco, _name, plies} -> plies end)
    |> Enum.chunk_every(500)
    |> Enum.each(fn chunk ->
      repo().query!(
        """
        INSERT INTO openings (position_record, eco, name)
        SELECT * FROM unnest($1::bytea[], $2::text[], $3::text[])
        ON CONFLICT (position_record) DO UPDATE SET
          eco = EXCLUDED.eco,
          name = EXCLUDED.name
        """,
        [
          Enum.map(chunk, &elem(&1, 0)),
          Enum.map(chunk, &elem(&1, 1)),
          Enum.map(chunk, &elem(&1, 2))
        ]
      )
    end)

    [[count]] = repo().query!("SELECT count(*) FROM openings", []).rows
    IO.puts("seeded #{count} openings")
  end

  defp read_volume(dir, volume) do
    dir
    |> Path.join("#{volume}.tsv")
    |> File.stream!()
    |> Stream.drop(1)
    |> Stream.flat_map(fn line ->
      case String.split(String.trim_trailing(line), "\t") do
        [eco, name, pgn] ->
          case replay(pgn) do
            {:ok, record} -> [{record, eco, name, length(String.split(pgn))}]
            :error -> []
          end

        _ ->
          []
      end
    end)
  end

  defp replay(pgn) do
    moves =
      pgn
      |> String.split(~r/\s+/, trim: true)
      |> Enum.map(&String.replace(&1, ~r/^\d+\.(\.\.)?/, ""))
      |> Enum.reject(&(&1 == ""))

    position = Chess.Position.starting_position()

    moves
    |> Enum.reduce_while({:ok, position}, fn san, {:ok, current} ->
      with {:ok, move} <- Chess.Notation.SAN.parse(current, san),
           {:ok, next} <- Chess.Position.apply_move(current, move) do
        {:cont, {:ok, next}}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      {:ok, position} -> {:ok, Chess.PositionCodec.encode(position)}
      :error -> :error
    end
  end
end
