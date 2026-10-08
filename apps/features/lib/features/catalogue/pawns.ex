defmodule Features.Catalogue.Pawns do
  @moduledoc """
  Spec section 3 — pawn structure.

  Definitions are heuristic and pinned by the test suite; every bullet of
  the spec section maps to exactly one feature id.
  """

  import Bitwise

  alias Features.Catalogue.Support
  alias Features.Chess.{Bitboard, Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("pawns.structure", 3, [{3, "exacte pionnenstructuur"}], fn board ->
        %{
          "white" => structure(board, :white),
          "black" => structure(board, :black)
        }
      end),
      Feature.new("pawns.count.per_wing", 3, [{3, "aantal pionnen per vleugel"}], fn board ->
        per_color(board, fn board, color ->
          %{
            "queenside" => count(board, color, 0..3),
            "kingside" => count(board, color, 4..7)
          }
        end)
      end),
      Feature.new("pawns.islands", 3, [{3, "pawn islands"}], fn board ->
        per_color(board, fn board, color ->
          groups(board, color)
          |> Map.keys()
          |> Enum.sort()
          |> count_islands()
        end)
      end),
      Feature.new("pawns.isolated", 3, [{3, "geïsoleerde pion"}], fn board ->
        per_color(board, fn board, color ->
          groups = groups(board, color)

          squares_of(board, color)
          |> Enum.filter(&isolated?(&1, groups))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.iqp", 3, [{3, "isolated queen pawn / IQP"}], fn board ->
        per_color(board, fn board, color ->
          groups = groups(board, color)

          squares_of(board, color)
          |> Enum.filter(fn square ->
            Square.file(square) <= 3 and isolated?(square, groups)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("pawns.backward", 3, [{3, "backward pawn"}], fn board ->
        per_color(board, fn board, color ->
          groups = groups(board, color)

          squares_of(board, color)
          |> Enum.filter(&backward?(&1, color, groups))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.doubled", 3, [{3, "doubled pawns"}], fn board ->
        per_color(board, &on_crowded_files(&1, &2, 2))
      end),
      Feature.new("pawns.tripled", 3, [{3, "tripled pawns"}], fn board ->
        per_color(board, &on_crowded_files(&1, &2, 3))
      end),
      Feature.new("pawns.passed", 3, [{3, "passed pawn"}], fn board ->
        per_color(board, fn board, color -> to_alg(Support.passed_pawns(board, color)) end)
      end),
      Feature.new("pawns.protected_passed", 3, [{3, "protected passed pawn"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> Support.passed_pawns(color)
          |> Enum.filter(&Support.attacked_by_pawn?(board, &1, color))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.connected_passed", 3, [{3, "connected passed pawns"}], fn board ->
        per_color(board, fn board, color ->
          passed = Support.passed_pawns(board, color)

          passed
          |> Enum.filter(fn square ->
            Enum.any?(passed, &(&1 != square and paired?(&1, square)))
          end)
          |> to_alg()
        end)
      end),
      Feature.new("pawns.candidate_passed", 3, [{3, "candidate passed pawn"}], fn board ->
        per_color(board, fn board, color ->
          passed = Support.passed_pawns(board, color)
          enemy = pawn_squares(board, Board.opposite(color))

          squares_of(board, color)
          |> Enum.filter(fn square ->
            square not in passed and virtually_passed?(square, color, enemy)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("pawns.connected", 3, [{3, "connected pawns"}], fn board ->
        per_color(board, fn board, color ->
          squares_of(board, color)
          |> Enum.filter(&Support.attacked_by_pawn?(board, &1, color))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.hanging", 3, [{3, "hanging pawns"}], fn board ->
        per_color(board, fn board, color ->
          squares = squares_of(board, color)

          squares
          |> Enum.filter(&hanging?(&1, squares))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.chains", 3, [{3, "pawn chains"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> chains(color)
          |> Enum.filter(&(length(&1) >= 2))
          |> Enum.map(&to_alg/1)
          |> Enum.sort()
        end)
      end),
      Feature.new("pawns.chain_bases", 3, [{3, "basis van een pawn chain"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> chains(color)
          |> Enum.filter(&(length(&1) >= 2))
          |> Enum.map(fn chain -> chain |> chain_base(color) |> Square.to_string() end)
          |> Enum.sort()
        end)
      end),
      Feature.new("pawns.majority", 3, [{3, "pawn majority"}], fn board ->
        per_color(board, fn board, color ->
          count(board, color, 0..7) > count(board, Board.opposite(color), 0..7)
        end)
      end),
      Feature.new("pawns.kingside_majority", 3, [{3, "kingside majority"}], fn board ->
        per_color(board, fn board, color ->
          count(board, color, 4..7) > count(board, Board.opposite(color), 4..7)
        end)
      end),
      Feature.new("pawns.queenside_majority", 3, [{3, "queenside majority"}], fn board ->
        per_color(board, fn board, color ->
          count(board, color, 0..3) > count(board, Board.opposite(color), 0..3)
        end)
      end),
      Feature.new("pawns.minority", 3, [{3, "minority"}], fn board ->
        per_color(board, fn board, color ->
          count(board, color, 0..7) < count(board, Board.opposite(color), 0..7)
        end)
      end),
      Feature.new("pawns.minority_attack", 3, [{3, "minority-attackstructuur"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.opposite(color)

          Enum.any?([0..3, 4..7], fn files ->
            mine = count(board, color, files)
            mine >= 1 and mine < count(board, enemy, files)
          end)
        end)
      end),
      Feature.new("pawns.levers", 3, [{3, "pawn lever"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.piece_bb(board, Board.opposite(color), :pawns)

          squares_of(board, color)
          |> Enum.filter(&attacks_enemy_pawn?(&1, color, enemy))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.breaks", 3, [{3, "mogelijke pawn break"}], fn board ->
        per_color(board, fn board, color ->
          enemy = Board.piece_bb(board, Board.opposite(color), :pawns)

          squares_of(board, color)
          |> Enum.filter(&break_square?(&1, color, enemy, board))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.locked", 3, [{3, "locked pawn structure"}], fn board ->
        head_to_head?(board) and not pawn_tension?(board)
      end),
      Feature.new("pawns.open_structure", 3, [{3, "open pawn structure"}], fn board ->
        not head_to_head?(board) and not pawn_tension?(board)
      end),
      Feature.new("pawns.fixed", 3, [{3, "fixed pawn structure"}], fn board ->
        not Enum.any?([:white, :black], fn color ->
          Enum.any?(squares_of(board, color), &Support.can_advance?(board, &1))
        end)
      end),
      Feature.new("pawns.weak", 3, [{3, "zwakke pion"}], fn board ->
        per_color(board, fn board, color ->
          groups = groups(board, color)

          squares_of(board, color)
          |> Enum.filter(&(isolated?(&1, groups) or backward?(&1, color, groups)))
          |> to_alg()
        end)
      end),
      Feature.new(
        "pawns.weak_undeprotectable",
        3,
        [{3, "zwakke pion die niet door een andere pion kan worden gedekt"}],
        fn board ->
          per_color(board, fn board, color ->
            groups = groups(board, color)

            squares_of(board, color)
            |> Enum.filter(fn square ->
              (isolated?(square, groups) or backward?(square, color, groups)) and
                not rear_supportable?(square, color, groups)
            end)
            |> to_alg()
          end)
        end
      ),
      Feature.new("pawns.advanced", 3, [{3, "advanced pawn"}], fn board ->
        per_color(board, fn board, color ->
          squares_of(board, color)
          |> Enum.filter(&advanced?(&1, color))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.overextended", 3, [{3, "overextended pawn"}], fn board ->
        per_color(board, fn board, color ->
          squares_of(board, color)
          |> Enum.filter(fn square ->
            advanced?(square, color) and
              not Support.attacked_by_pawn?(board, square, color)
          end)
          |> to_alg()
        end)
      end),
      Feature.new("pawns.rook_behind_passed", 3, [{3, "rook behind passed pawn"}], fn board ->
        per_color(board, fn board, color ->
          rooks = Bitboard.squares(Board.piece_bb(board, color, :rooks))

          Enum.any?(Support.passed_pawns(board, color), fn square ->
            file = Square.file(square)
            rank = Square.rank(square)

            Enum.any?(rooks, fn rook ->
              Square.file(rook) == file and behind?(Square.rank(rook), rank, color)
            end)
          end)
        end)
      end),
      Feature.new("pawns.blockaded_passed", 3, [{3, "blockaded passed pawn"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> Support.passed_pawns(color)
          |> Enum.filter(&blocker?(&1, color, board))
          |> to_alg()
        end)
      end),
      Feature.new("pawns.blockade_square", 3, [{3, "blockade-square"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> Support.passed_pawns(color)
          |> Enum.filter(&blocker?(&1, color, board))
          |> Enum.map(fn square -> square |> ahead_square(color) |> Square.to_string() end)
          |> Enum.sort()
        end)
      end),
      Feature.new(
        "pawns.structure_gap",
        3,
        [{3, "afstand tussen vergelijkbare pionnenstructuren"}],
        fn board ->
          white = groups(board, :white)
          black = groups(board, :black)

          gaps =
            for file <- 0..7,
                wr <- Map.get(white, file, []),
                br <- Map.get(black, file, []),
                do: abs(wr - br)

          case gaps do
            [] ->
              nil

            gaps ->
              round(Enum.sum(gaps) / length(gaps) * 100) / 100
          end
        end
      ),
      Feature.new("pawns.single_rank_shift", 3, [{3, "één pion één rang verschoven"}], fn board ->
        white = groups(board, :white)

        black =
          board
          |> groups(:black)
          |> Map.new(fn {file, ranks} -> {file, Enum.map(ranks, &(7 - &1))} end)

        case Enum.filter(
               0..7,
               &(Enum.sort(Map.get(white, &1, [])) != Enum.sort(Map.get(black, &1, [])))
             ) do
          [file] ->
            one_shift?(Enum.sort(Map.get(white, file, [])), Enum.sort(Map.get(black, file, [])))

          _ ->
            false
        end
      end),
      Feature.new(
        "pawns.diagonal_displacement",
        3,
        [{3, "capture-like diagonale pionverschuiving"}],
        fn board ->
          per_color(board, fn board, color ->
            groups(board, color)
            |> Map.values()
            |> Enum.any?(&(length(&1) >= 2))
          end)
        end
      ),
      Feature.new("pawns.count_anomaly", 3, [{3, "ontbrekende/toegevoegde pion"}], fn board ->
        %{
          "white" => 8 - count(board, :white, 0..7),
          "black" => 8 - count(board, :black, 0..7)
        }
      end),
      Feature.new(
        "pawns.color_mirrored",
        3,
        [{3, "kleurgespiegelde pionnenstructuur"}],
        fn board ->
          white = board |> squares_of(:white) |> MapSet.new()
          black = board |> squares_of(:black) |> MapSet.new(&(63 - &1))

          white == black
        end
      )
    ]
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp structure(board, color) do
    groups = groups(board, color)
    Map.new(0..7, fn file -> {file, Map.get(groups, file, [])} end)
  end

  defp groups(board, color), do: Support.pawns_by_file(board, color)

  defp squares_of(board, color) do
    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.sort()
  end

  defp pawn_squares(board, color), do: squares_of(board, color)

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)

  defp count(board, color, files) do
    board
    |> Board.piece_bb(color, :pawns)
    |> Bitboard.squares()
    |> Enum.count(&(Square.file(&1) in files))
  end

  defp count_islands(files) do
    files
    |> Enum.reduce({0, nil}, fn file, {islands, previous} ->
      if previous == nil or file != previous + 1, do: {islands + 1, file}, else: {islands, file}
    end)
    |> elem(0)
  end

  defp isolated?(square, groups) do
    file = Square.file(square)
    not (Map.has_key?(groups, file - 1) or Map.has_key?(groups, file + 1))
  end

  defp backward?(square, color, groups) do
    file = Square.file(square)
    rank = Square.rank(square)

    not Enum.any?([-1, 1], fn offset ->
      groups
      |> Map.get(file + offset, [])
      |> Enum.any?(&rear_or_level?(&1, rank, color))
    end)
  end

  defp rear_or_level?(rank, own, :white), do: rank <= own
  defp rear_or_level?(rank, own, :black), do: rank >= own

  defp on_crowded_files(board, color, minimum) do
    groups = groups(board, color)

    squares_of(board, color)
    |> Enum.filter(&(length(Map.fetch!(groups, Square.file(&1))) >= minimum))
    |> to_alg()
  end

  defp paired?(square, other) do
    abs(Square.file(square) - Square.file(other)) == 1 and
      abs(Square.rank(square) - Square.rank(other)) == 1
  end

  defp hanging?(square, pawns) do
    file = Square.file(square)
    rank = Square.rank(square)

    file in 2..5 and
      Enum.any?(pawns, fn other ->
        other != square and Square.rank(other) == rank and
          Square.file(other) in 2..5 and abs(Square.file(other) - file) == 1
      end) and
      Enum.count(pawns, fn other ->
        other != square and abs(Square.file(other) - file) <= 1
      end) == 1
  end

  defp virtually_passed?(square, color, enemy) do
    file = Square.file(square)
    rank = forward_rank(Square.rank(square), color)

    rank in 0..7 and
      Enum.all?(enemy, fn pawn ->
        abs(Square.file(pawn) - file) > 1 or not ahead?(Square.rank(pawn), rank, color)
      end)
  end

  defp ahead?(rank, own, :white), do: rank > own
  defp ahead?(rank, own, :black), do: rank < own

  defp behind?(rank, own, :white), do: rank < own
  defp behind?(rank, own, :black), do: rank > own

  defp forward_rank(rank, :white), do: rank + 1
  defp forward_rank(rank, :black), do: rank - 1

  defp advanced?(square, :white), do: Square.rank(square) >= 4
  defp advanced?(square, :black), do: Square.rank(square) <= 3

  defp rear_supportable?(square, color, groups) do
    file = Square.file(square)
    rank = Square.rank(square)

    Enum.any?([-1, 1], fn offset ->
      groups
      |> Map.get(file + offset, [])
      |> Enum.any?(&supportable?(&1, rank, color))
    end)
  end

  defp supportable?(rank, own, :white), do: rank < own
  defp supportable?(rank, own, :black), do: rank > own

  defp chains(board, color) do
    squares = squares_of(board, color)

    graph =
      Map.new(squares, fn square -> {square, Enum.filter(squares, &paired?(square, &1))} end)

    {components, _seen} =
      Enum.reduce(squares, {[], MapSet.new()}, fn square, {components, seen} ->
        if MapSet.member?(seen, square) do
          {components, seen}
        else
          component = component(square, graph)
          {[component | components], MapSet.union(seen, component)}
        end
      end)

    components
    |> Enum.map(&sort_chain(&1, color))
    |> Enum.sort()
  end

  defp component(start, graph) do
    do_component([start], MapSet.new(), graph)
  end

  defp do_component([], visited, _graph), do: visited

  defp do_component([square | rest], visited, graph) do
    if MapSet.member?(visited, square) do
      do_component(rest, visited, graph)
    else
      do_component(graph[square] ++ rest, MapSet.put(visited, square), graph)
    end
  end

  defp sort_chain(squares, :white), do: Enum.sort_by(squares, &{Square.rank(&1), Square.file(&1)})

  defp sort_chain(squares, :black),
    do: Enum.sort_by(squares, &{-Square.rank(&1), Square.file(&1)})

  defp chain_base(chain, :white), do: Enum.min_by(chain, &Square.rank/1)
  defp chain_base(chain, :black), do: Enum.max_by(chain, &Square.rank/1)

  defp attacks_enemy_pawn?(square, color, enemy) do
    file = Square.file(square)
    rank = forward_rank(Square.rank(square), color)

    Enum.any?([-1, 1], fn offset ->
      case target_square(file + offset, rank) do
        nil -> false
        target -> (1 <<< target &&& enemy) != 0
      end
    end)
  end

  defp break_square?(square, color, enemy, board) do
    file = Square.file(square)
    rank = forward_rank(Square.rank(square), color)

    case target_square(file, rank) do
      nil ->
        false

      step ->
        Board.piece_at(board, step) == nil and
          Enum.any?([-1, 1], fn offset ->
            case target_square(file + offset, forward_rank(rank, color)) do
              nil -> false
              target -> (1 <<< target &&& enemy) != 0
            end
          end)
    end
  end

  defp head_to_head?(board) do
    Enum.any?(squares_of(board, :white), fn square ->
      case ahead_square(square, :white) do
        nil -> false
        target -> Board.piece_at(board, target) == {:black, :pawns}
      end
    end)
  end

  defp pawn_tension?(board) do
    black_pawns = Board.piece_bb(board, :black, :pawns)
    white_pawns = Board.piece_bb(board, :white, :pawns)

    Enum.any?(squares_of(board, :white), &attacks_enemy_pawn?(&1, :white, black_pawns)) or
      Enum.any?(squares_of(board, :black), &attacks_enemy_pawn?(&1, :black, white_pawns))
  end

  defp blocker?(square, color, board) do
    case ahead_square(square, color) do
      nil ->
        false

      target ->
        case Board.piece_at(board, target) do
          nil -> false
          {^color, _type} -> false
          {_enemy, _type} -> true
        end
    end
  end

  defp ahead_square(square, color) do
    target_square(Square.file(square), forward_rank(Square.rank(square), color))
  end

  defp target_square(file, rank) when file in 0..7 and rank in 0..7, do: rank * 8 + file
  defp target_square(_file, _rank), do: nil

  defp one_shift?(white, black) do
    case {white -- black, black -- white} do
      {[a], [b]} -> abs(a - b) == 1
      _ -> false
    end
  end
end
