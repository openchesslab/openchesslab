defmodule Features.Catalogue.StateTest do
  use ExUnit.Case, async: true

  alias Features.Chess.FEN

  defp extract(fen), do: Features.extract(fen).features

  test "start position" do
    features = extract(FEN.start_fen())

    occupancy = features["state.square_occupancy"]
    assert length(occupancy) == 64
    assert Enum.at(occupancy, 0) == "R"
    assert Enum.at(occupancy, 12) == "P"
    assert Enum.at(occupancy, 27) == nil
    assert Enum.at(occupancy, 60) == "k"

    assert features["state.side_to_move"] == "white"
    assert features["state.king_squares"] == %{"white" => "e1", "black" => "e8"}
    assert features["state.castling_rights"] == "KQkq"
    assert features["state.en_passant"] == nil

    assert features["state.white_pawn_squares"] ==
             ~w(a2 b2 c2 d2 e2 f2 g2 h2)

    assert features["state.black_pawn_squares"] ==
             ~w(a7 b7 c7 d7 e7 f7 g7 h7)

    assert features["state.pieces"] |> List.first() ==
             %{square: "a1", color: "white", type: "rook"}

    assert length(features["state.pieces"]) == 32

    occupancy_by_type = features["state.piece_occupancy"]
    assert occupancy_by_type["white"]["queen"] == ["d1"]
    assert occupancy_by_type["black"]["king"] == ["e8"]
    assert occupancy_by_type["white"]["bishop"] == ~w(c1 f1)
    assert occupancy_by_type["black"]["pawn"] == ~w(a7 b7 c7 d7 e7 f7 g7 h7)
  end

  test "en passant and side to move" do
    features = extract("rnbqkbnr/pppppppp/8/8/4P3/8/PPPP1PPP/RNBQKBNR b KQkq e3 0 1")

    assert features["state.side_to_move"] == "black"
    assert features["state.en_passant"] == "e3"
    assert "e4" in features["state.white_pawn_squares"]
    refute "e2" in features["state.white_pawn_squares"]
  end

  test "castling rights serialization" do
    assert extract("8/8/8/8/8/8/8/K6k w - - 0 1")["state.castling_rights"] == "-"
    assert extract("8/8/8/8/8/8/8/K6k w Kq - 0 1")["state.castling_rights"] == "Kq"
  end
end
