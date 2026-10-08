defmodule Features.Catalogue.State do
  @moduledoc """
  Spec section 1 — exact state of the position.
  """

  alias Features.Catalogue.Support
  alias Features.Chess.{Board, FEN, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("state.square_occupancy", 1, [{1, "bezetting van ieder veld"}], fn board ->
        for square <- 0..63 do
          case Board.piece_at(board, square) do
            nil -> nil
            piece -> FEN.piece_char(piece)
          end
        end
      end),
      Feature.new("state.pieces", 1, [{1, "type en kleur van ieder stuk"}], fn board ->
        for square <- 0..63, piece = Board.piece_at(board, square), piece != nil do
          {color, type} = piece

          %{
            square: Square.to_string(square),
            color: Support.color_name(color),
            type: Support.type_name(type)
          }
        end
      end),
      Feature.new("state.side_to_move", 1, [{1, "side to move"}], fn board ->
        Support.color_name(board.side_to_move)
      end),
      Feature.new("state.king_squares", 1, [{1, "positie van beide koningen"}], fn board ->
        for color <- [:white, :black], into: %{} do
          {Support.color_name(color),
           board |> Board.piece_bb(color, :kings) |> Support.squares() |> List.first()}
        end
      end),
      Feature.new("state.castling_rights", 1, [{1, "rokaderechten"}], fn board ->
        Board.castling_to_string(board.castling)
      end),
      Feature.new("state.en_passant", 1, [{1, "en-passantmogelijkheid"}], fn board ->
        case board.en_passant do
          nil -> nil
          square -> Square.to_string(square)
        end
      end),
      Feature.new(
        "state.white_pawn_squares",
        1,
        [{1, "exacte witte-pionnenbezetting"}],
        fn board ->
          Support.squares(Board.piece_bb(board, :white, :pawns))
        end
      ),
      Feature.new(
        "state.black_pawn_squares",
        1,
        [{1, "exacte zwarte-pionnenbezetting"}],
        fn board ->
          Support.squares(Board.piece_bb(board, :black, :pawns))
        end
      ),
      Feature.new(
        "state.piece_occupancy",
        1,
        [{1, "exacte piece occupancy per stuktype en kleur"}],
        fn board ->
          for color <- [:white, :black], into: %{} do
            occupancy =
              for type <- Board.types(), into: %{} do
                {Support.type_name(type), Support.squares(Board.piece_bb(board, color, type))}
              end

            {Support.color_name(color), occupancy}
          end
        end
      )
    ]
  end
end
