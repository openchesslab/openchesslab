# Feature-alignment scan (fase 1): vergelijkt de Features-catalogus met
# Chess.PositionProperties op echte corpus-posities uit `openchesslab_bench`.
#
# Gebruik:
#   DATABASE_URL="ecto://openchesslab:openchesslab@localhost/openchesslab_bench" \
#     mix run apps/analysis/benchmarks/feature_alignment.exs -- [aantal posities]
#
# Rapporteert per paar: aantal posities met mismatch, en max 3 voorbeeld-FENs.

Logger.configure(level: :warning)

Application.ensure_all_started(:database)

alias Analysis.PositionFeatures
alias Analysis.PositionStore
alias Chess.{Position, PositionProperties, Square}
alias OpenChessLab.Repo

sample_size =
  case Enum.reject(System.argv(), &(&1 == "--")) do
    [n | _] -> String.to_integer(n)
    _ -> 2_000
  end

max_id =
  Repo.query!("SELECT max(id) FROM positions").rows
  |> List.first()
  |> List.first()

ids =
  1..sample_size
  |> Enum.map(fn _ -> :rand.uniform(max_id) end)
  |> Enum.uniq()

positions =
  Repo.query!("SELECT id, record FROM positions WHERE id = ANY($1)", [ids]).rows
  |> Enum.flat_map(fn [id, record] ->
    case PositionStore.get(id) do
      {:ok, %Position{} = position} -> [{id, position, record}]
      _ -> []
    end
  end)

IO.puts("posities: #{length(positions)} (van #{length(ids)} willekeurige ids)")

# --- normalisatie -----------------------------------------------------------

defmodule Align do
  alias Chess.Square

  def per_color(map) when is_map(map) do
    for {k, v} <- map, into: %{} do
      color =
        case k do
          :white -> :white
          :black -> :black
          "white" -> :white
          "black" -> :black
        end

      {color, v}
    end
  end

  def squares(list) when is_list(list) do
    list
    |> Enum.map(fn
      square when is_integer(square) -> square
      square when is_binary(square) -> Square.from_algebraic(square)
    end)
    |> Enum.sort()
  end

  def files(list) when is_list(list) do
    list
    |> Enum.map(fn
      file when is_integer(file) -> file
      file when is_atom(file) -> :binary.first(Atom.to_string(file)) - ?a
      file when is_binary(file) -> :binary.first(file) - ?a
    end)
    |> Enum.sort()
  end

  def castling(value) do
    value
    |> List.wrap()
    |> Enum.flat_map(fn
      :white_kingside -> ["K"]
      :white_queenside -> ["Q"]
      :black_kingside -> ["k"]
      :black_queenside -> ["q"]
      "-" -> []
      other when is_binary(other) -> String.graphemes(other)
    end)
    |> Enum.sort()
  end

  def fen(position) do
    rows =
      for rank <- Enum.to_list(7..0//-1) do
        {parts, empty} =
          Enum.reduce(0..7, {[], 0}, fn file, {parts, empty} ->
            case Position.piece_at(position, rank * 8 + file) do
              nil ->
                {parts, empty + 1}

              {color, kind} ->
                part =
                  kind
                  |> Atom.to_string()
                  |> String.first()
                  |> then(fn letter ->
                    if color == :white, do: String.upcase(letter), else: letter
                  end)

                if empty > 0,
                  do: {parts ++ [Integer.to_string(empty), part], 0},
                  else: {parts ++ [part], 0}
            end
          end)

        Enum.join(parts ++ if(empty > 0, do: [Integer.to_string(empty)], else: []), "")
      end

    castling =
      case MapSet.to_list(position.castling_rights) do
        [] -> "-"
        rights -> Enum.join(castling(rights), "")
      end

    board = Enum.join(rows, "/")
    side = if position.side_to_move == :white, do: "w", else: "b"
    ep = if position.en_passant, do: Square.to_algebraic(position.en_passant), else: "-"

    "#{board} #{side} #{castling} #{ep} 0 1"
  end
end

# --- paren -------------------------------------------------------------------
# Elke entry: {naam, catalogue-waarde-fn(vector, position), chess-waarde-fn(position)}
# Beide geven een direct vergelijkbare vorm terug (via Align-normalisatie).

opp = fn
  :white -> :black
  :black -> :white
end

pairs = [
  {"attacks.attacked_pieces (kruisperspectief)",
   fn vec, _pos ->
     vec["attacks.attacked_pieces"]
     |> Align.per_color()
     |> Map.new(fn {color, v} -> {color, Align.squares(v)} end)
   end,
   fn pos ->
     for color <- [:white, :black], into: %{} do
       {color, Align.squares(PositionProperties.attacked_pieces(pos)[opp.(color)])}
     end
   end},
  {"attacks.defended_squares",
   fn vec, _pos ->
     vec["attacks.defended_squares"]
     |> Align.per_color()
     |> Map.new(fn {color, v} -> {color, Align.squares(v)} end)
   end,
   fn pos ->
     for color <- [:white, :black], into: %{} do
       {color, Align.squares(PositionProperties.defended_squares(pos)[color])}
     end
   end},
  {"attacks.map vs PositionProperties.attacked_squares",
   fn vec, _pos ->
     vec["attacks.map"]
     |> Align.per_color()
     |> Map.new(fn {color, v} -> {color, Align.squares(v)} end)
   end,
   fn pos ->
     for color <- [:white, :black], into: %{} do
       {color, Align.squares(PositionProperties.attacked_squares(pos)[color])}
     end
   end},
  {"squares.outpost ∪ occupied_outpost vs PositionProperties.outposts",
   fn vec, _pos ->
     outpost = Align.per_color(vec["squares.outpost"])
     occupied = Align.per_color(vec["squares.occupied_outpost"])

     for color <- [:white, :black], into: %{} do
       {color,
        Align.squares(Map.get(outpost, color, []) ++ Map.get(occupied, color, []))}
     end
   end,
   fn pos ->
     for color <- [:white, :black], into: %{} do
       {color, Align.squares(PositionProperties.outposts(pos)[color])}
     end
   end},
  {"space.enemy_half_control vs PositionProperties.space.controlled",
   fn vec, _pos -> Align.per_color(vec["space.enemy_half_control"]) end,
   fn pos ->
     space = PositionProperties.space(pos)
     for color <- [:white, :black], into: %{} do {color, space[color].controlled} end
   end},
  {"IDENTITEIT attacks.map − PP.attacked_squares == PP.defended_squares",
   fn vec, pos ->
     map = Align.per_color(vec["attacks.map"])
     attacked = PositionProperties.attacked_squares(pos)

     for color <- [:white, :black], into: %{} do
       diff = MapSet.difference(MapSet.new(Align.squares(map[color])), MapSet.new(attacked[color]))
       {color, diff |> MapSet.to_list() |> Enum.sort()}
     end
   end,
   fn pos ->
     for color <- [:white, :black], into: %{} do
       {color, Align.squares(PositionProperties.defended_squares(pos)[color])}
     end
   end},
  {"IDENTITEIT catalogus.space − chess.controlled == verdedigde eigen stukken in vijandelijke helft",
   fn vec, pos ->
     catalogue = Align.per_color(vec["space.enemy_half_control"])
     chess = PositionProperties.space(pos)

     for color <- [:white, :black], into: %{} do
       {color, catalogue[color] - chess[color].controlled}
     end
   end,
   fn pos ->
     defended = PositionProperties.defended_squares(pos)

     for color <- [:white, :black], into: %{} do
       in_half =
         if color == :white,
           do: &(&1 in 32..63),
           else: &(&1 in 0..31)

       {color, Enum.count(Enum.filter(defended[color], in_half))}
     end
   end},
  {"material.count.*",
   fn vec, _pos ->
     for piece <- ["queen", "rook", "bishop", "knight", "pawn"],
         id = "material.count.#{piece}",
         entry = Align.per_color(vec[id]),
         into: %{} do
       {piece, entry}
     end
   end,
   fn pos ->
     material = PositionProperties.material(pos)

     for piece <- ["queen", "rook", "bishop", "knight", "pawn"],
         key = String.to_existing_atom(piece),
         into: %{} do
       {piece, %{white: material.white[key], black: material.black[key]}}
     end
   end},
  {"material.total_value",
   fn vec, _pos -> Align.per_color(vec["material.total_value"]) end,
   fn pos ->
     material = PositionProperties.material(pos)

     total = fn counts ->
       counts.queen * 9 + counts.rook * 5 + counts.bishop * 3 + counts.knight * 3 +
         counts.pawn
     end

     %{white: total.(material.white), black: total.(material.black)}
   end},
  {"lines.open_files",
   fn vec, _pos -> Align.files(vec["lines.open_files"]) end,
   fn pos -> Align.files(PositionProperties.open_files(pos)) end},
  {"lines.semi_open_files",
   fn vec, _pos ->
     vec["lines.semi_open_files"]
     |> Align.per_color()
     |> Map.new(fn {color, v} -> {color, Align.files(v)} end)
   end,
   fn pos ->
     semi = PositionProperties.semi_open_files(pos)
     for color <- [:white, :black], into: %{} do {color, Align.files(semi[color])} end
   end},
  {"state.side_to_move",
   fn vec, _pos -> to_string(vec["state.side_to_move"]) end,
   fn pos -> to_string(pos.side_to_move) end},
  {"state.castling_rights",
   fn vec, _pos -> Align.castling(List.wrap(vec["state.castling_rights"])) end,
   fn pos -> Align.castling(MapSet.to_list(pos.castling_rights)) end},
  {"state.en_passant",
   fn vec, _pos -> to_string(vec["state.en_passant"] || "-") end,
   fn pos -> to_string(pos.en_passant || "-") end}
]

report =
  for {name, catalogue_fn, chess_fn} <- pairs, into: %{} do
    initial = %{checked: 0, mismatches: 0, examples: []}

    Enum.reduce(positions, initial, fn {_id, position, _record}, acc ->
      with {:ok, vector} <- PositionFeatures.extract(position) do
        left = catalogue_fn.(vector.features, position)
        right = chess_fn.(position)

        if left == right do
          %{acc | checked: acc.checked + 1}
        else
          examples =
            if length(acc.examples) < 3 do
              [{vector.fen, left, right} | acc.examples]
            else
              acc.examples
            end

          %{acc | checked: acc.checked + 1, mismatches: acc.mismatches + 1, examples: examples}
        end
      else
        _ -> acc
      end
    end)
    |> then(&{name, &1})
  end

IO.puts("\n=== FEATURE-ALIGNMENT RAPPORT (#{length(positions)} posities) ===\n")

Enum.each(report, fn {name, %{checked: checked, mismatches: mismatches, examples: examples}} ->
  status = if mismatches == 0, do: "OK  ", else: "DIFF"
  IO.puts("#{status} #{name}: #{mismatches}/#{checked} mismatches")

  Enum.each(Enum.reverse(examples), fn {fen, left, right} ->
    IO.puts("      #{fen}")
    IO.puts("        catalogus: #{inspect(left, limit: 8)}")
    IO.puts("        chess:     #{inspect(right, limit: 8)}")
  end)
end)
