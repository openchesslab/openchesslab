defmodule Features.EngineDifferentialTest do
  @moduledoc """
  Differential validation of the catalogue's own chess core
  (`Features.Chess.*`) against the gameplay engine (`Chess.*`).

  Published perft counts anchor absolute correctness; seeded random play
  compares the legal-move sets and the resulting state (placement, side to
  move, castling, en passant) position by position. A failure here means one
  of the two engines is wrong — investigate before touching either.
  """

  use ExUnit.Case, async: false

  alias Chess.Notation.FEN, as: GameFEN
  alias Chess.Notation.UCI, as: GameUCI
  alias Chess.Position
  alias Features.Chess.Board, as: FeatBoard
  alias Features.Chess.FEN, as: FeatFEN
  alias Features.Chess.Move, as: FeatMove
  alias Features.Chess.Movegen

  @start "rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1"

  # The classic perft suite (CPW, first five positions; the last one's
  # counts come from the python-chess reference engine — both engines were
  # cross-checked against it during the differential review). These anchor
  # absolute correctness, not just agreement between the two engines.
  @perft_suite [
    {"startpos", @start, [20, 400, 8902]},
    {"kiwipete", "r3k2r/p1ppqpb1/bn2pnp1/3PN3/1p2P3/2N2Q1p/PPPBBPPP/R3K2R w KQkq - 0 1",
     [48, 2039, 97_862]},
    {"ep-and-pins", "8/2p5/3p4/KP5r/1R3p1k/8/4P1P1/8 w - - 0 1", [14, 191, 2812]},
    {"castling-gauntlet", "r3k2r/Pppp1ppp/1b3nbN/nP6/BBP1P3/q4N2/Pp1P2PP/R2Q1RK1 w kq - 0 1",
     [6, 264, 9467]},
    {"promotion-pressure", "rnbq1k1r/pp1Pbppp/2p5/8/2B5/8/PPP1NnPP/RNBQK2R w KQ - 1 8",
     [44, 1486, 62_379]},
    {"midgame", "r4rk1/1pp1qppp/p1np1n2/8/2BPP3/P1N2N2/1P2QPPP/R4RK1 w - - 0 10",
     [44, 1591, 68_174]}
  ]

  test "published perft counts hold in both engines" do
    for {name, fen, counts} <- @perft_suite do
      for {expected, depth} <- Enum.with_index(counts, 1) do
        assert perft_game(fen, depth) == expected,
               "Chess perft(#{name}, depth #{depth}) != #{expected}"

        assert perft_features(fen, depth) == expected,
               "Features perft(#{name}, depth #{depth}) != #{expected}"
      end
    end
  end

  test "both engines parse identical state from the same FENs" do
    for {_name, fen, _counts} <- @perft_suite do
      assert_same_state(fen)
    end
  end

  test "seeded random play agrees on legal moves and state at every ply" do
    :rand.seed(:exsss, {2026, 10, 17})
    game = game_position(@start)
    features = features_board(@start)

    play_random_games(game, features, 30, 60)
  end

  # --- random play -------------------------------------------------------

  defp play_random_games(_game, _features, 0, _max_plies), do: :ok

  defp play_random_games(game, features, games_left, max_plies) do
    assert_engines_agree(game, features)

    case Position.legal_moves(game) do
      [] ->
        # Mate or stalemate: start a fresh game.
        play_random_games(
          game_position(@start),
          features_board(@start),
          games_left - 1,
          max_plies
        )

      moves ->
        move = Enum.random(moves)
        features_move = FeatMove.new(move.from, move.to, plural(move.promotion))

        case Position.apply_move(game, move) do
          {:ok, next_game} ->
            next_features = FeatBoard.apply_move(features, features_move)

            if max_plies > 1 do
              play_random_games(next_game, next_features, games_left, max_plies - 1)
            else
              play_random_games(game_position(@start), features_board(@start), games_left - 1, 60)
            end

          {:error, :illegal_move} ->
            flunk("Chess rejected its own legal move #{GameUCI.format(move)}")
        end
    end
  end

  defp assert_engines_agree(%Position{} = game, %FeatBoard{} = features) do
    game_moves = game |> Position.legal_moves() |> Enum.map(&GameUCI.format/1) |> Enum.sort()

    features_moves =
      features |> Movegen.legal_moves() |> Enum.map(&FeatMove.to_uci/1) |> Enum.sort()

    assert features_moves == game_moves, """
    legal move sets diverged
      game FEN-ish:    #{inspect(game_state(game))}
      features FEN:    #{FeatFEN.to_fen(features)}
      only in Chess:   #{inspect(game_moves -- features_moves)}
      only in Features: #{inspect(features_moves -- game_moves)}
    """

    assert feat_state(features) == game_state(game)
  end

  # --- shared state comparison -------------------------------------------

  defp assert_same_state(fen) do
    assert feat_state(features_board(fen)) == game_state(game_position(fen)),
           "state differs: #{fen}"
  end

  defp game_state(%Position{} = position) do
    %{
      placement: Enum.map(0..63, &piece_letter(Position.piece_at(position, &1))),
      side: position.side_to_move,
      castling: game_castling(position),
      en_passant: position.en_passant
    }
  end

  defp feat_state(%FeatBoard{} = board) do
    %{
      placement: Enum.map(0..63, &piece_letter(FeatBoard.piece_at(board, &1))),
      side: board.side_to_move,
      castling: feat_castling(board),
      en_passant: effective_ep(board)
    }
  end

  # The engines store en passant differently: Chess keeps the target only
  # while an enemy pawn stands beside the double-pushed pawn; Features keeps
  # the raw target. Move generation is identical either way (proven by the
  # move-set comparison), so the state comparison normalises to the Chess
  # convention instead of treating the representation as a bug.
  defp effective_ep(%FeatBoard{en_passant: nil}), do: nil

  defp effective_ep(%FeatBoard{en_passant: target} = board) do
    # The would-be capturer is the side to move; the pushed pawn is theirs
    # to take (Chess keeps the target only while such a pawn exists).
    {moved_pawn, capturer} =
      if board.side_to_move == :white,
        do: {target - 8, :white},
        else: {target + 8, :black}

    file = rem(moved_pawn, 8)

    adjacent? =
      (file > 0 and FeatBoard.piece_at(board, moved_pawn - 1) == {capturer, :pawns}) or
        (file < 7 and FeatBoard.piece_at(board, moved_pawn + 1) == {capturer, :pawns})

    if adjacent?, do: target
  end

  defp piece_letter(nil), do: nil

  defp piece_letter({color, type}) do
    letter =
      %{pawn: "p", knight: "n", bishop: "b", rook: "r", queen: "q", king: "k"}[
        deplural(type)
      ]

    if color == :white, do: String.upcase(letter), else: letter
  end

  defp deplural(type), do: type |> to_string() |> String.trim_trailing("s") |> String.to_atom()

  defp game_castling(%Position{castling_rights: rights}) do
    letters =
      for {right, letter} <- [
            white_kingside: "K",
            white_queenside: "Q",
            black_kingside: "k",
            black_queenside: "q"
          ],
          MapSet.member?(rights, right),
          do: letter

    case letters do
      [] -> "-"
      _ -> Enum.join(letters)
    end
  end

  defp feat_castling(%FeatBoard{} = board) do
    board |> FeatFEN.to_fen() |> String.split() |> Enum.at(2)
  end

  defp plural(nil), do: nil
  defp plural(type), do: String.to_atom("#{type}s")

  # --- perft ---------------------------------------------------------------

  defp perft_game(fen, depth) do
    fen
    |> game_position()
    |> do_perft_game(depth)
  end

  defp do_perft_game(_position, 0), do: 1

  defp do_perft_game(position, depth) do
    position
    |> Position.legal_moves()
    |> Enum.reduce(0, fn move, acc ->
      {:ok, next} = Position.apply_move(position, move)
      acc + do_perft_game(next, depth - 1)
    end)
  end

  defp perft_features(fen, depth) do
    fen
    |> features_board()
    |> do_perft_features(depth)
  end

  defp do_perft_features(_board, 0), do: 1

  defp do_perft_features(board, depth) do
    board
    |> Movegen.legal_moves()
    |> Enum.reduce(0, fn move, acc ->
      acc + do_perft_features(FeatBoard.apply_move(board, move), depth - 1)
    end)
  end

  # --- constructors ----------------------------------------------------------

  defp game_position(fen) do
    {:ok, %{position: position}} = GameFEN.parse(fen)
    position
  end

  defp features_board(fen), do: FeatFEN.parse(fen)
end
