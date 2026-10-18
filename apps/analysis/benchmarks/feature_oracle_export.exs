# Oracle export (fase 2): schrijft een willekeurige steekproef corpus-posities
# als FEN's voor de python-chess-orakelvergelijking.
#
# Gebruik:
#   DATABASE_URL="ecto://openchesslab:openchesslab@localhost/openchesslab_bench" \
#     mix run apps/analysis/benchmarks/feature_oracle_export.exs -- [aantal]

alias Analysis.PositionStore
alias Chess.{Position, Square}
alias OpenChessLab.Repo

Logger.configure(level: :warning)

Application.ensure_all_started(:database)

sample_size =
  case Enum.reject(System.argv(), &(&1 == "--")) do
    [n | _] -> String.to_integer(n)
    _ -> 1_000
  end

max_id = Repo.query!("SELECT max(id) FROM positions").rows |> List.first() |> List.first()

ids =
  1..sample_size
  |> Enum.map(fn _ -> :rand.uniform(max_id) end)
  |> Enum.uniq()

positions =
  Repo.query!("SELECT id, record FROM positions WHERE id = ANY($1)", [ids]).rows
  |> Enum.flat_map(fn [id, _record] ->
    case PositionStore.get(id) do
      {:ok, %Position{} = position} -> [{id, position}]
      _ -> []
    end
  end)

defmodule Fen do
  alias Chess.Position

  @letters %{pawn: "p", knight: "n", bishop: "b", rook: "r", queen: "q", king: "k"}

  def format(position) do
    rows =
      for rank <- Enum.to_list(7..0//-1) do
        {parts, empty} =
          Enum.reduce(0..7, {[], 0}, fn file, {parts, empty} ->
            case Position.piece_at(position, rank * 8 + file) do
              nil ->
                {parts, empty + 1}

              {color, kind} ->
                letter = @letters[kind]
                part = if color == :white, do: String.upcase(letter), else: letter

                if empty > 0,
                  do: {parts ++ [Integer.to_string(empty), part], 0},
                  else: {parts ++ [part], 0}
            end
          end)

        Enum.join(parts ++ if(empty > 0, do: [Integer.to_string(empty)], else: []), "")
      end

    castling =
      [
        {:white_kingside, "K"},
        {:white_queenside, "Q"},
        {:black_kingside, "k"},
        {:black_queenside, "q"}
      ]
      |> Enum.filter(fn {right, _letter} -> MapSet.member?(position.castling_rights, right) end)
      |> case do
        [] -> "-"
        rights -> Enum.map_join(rights, "", fn {_right, letter} -> letter end)
      end

    board = Enum.join(rows, "/")
    side = if position.side_to_move == :white, do: "w", else: "b"
    ep = if position.en_passant, do: Square.to_algebraic(position.en_passant), else: "-"

    "#{board} #{side} #{castling} #{ep} 0 1"
  end

  defp letter(:white_kingside), do: "K"
  defp letter(:white_queenside), do: "Q"
  defp letter(:black_kingside), do: "k"
  defp letter(:black_queenside), do: "q"
end

path = "/tmp/opencode/oracle-fens.txt"

lines =
  Enum.map_join(positions, "\n", fn {id, position} ->
    "#{id}\t#{Fen.format(position)}"
  end)

File.write!(path, lines <> "\n")

IO.puts("geschreven: #{length(positions)} posities naar #{path}")
