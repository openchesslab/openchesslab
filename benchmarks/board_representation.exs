defmodule Chess.Benchmarks.BoardRepresentation do
  alias Chess.Board

  empty_board = Board.empty()

  board =
    empty_board
    |> Board.put(0, {:white, :rook})
    |> Board.put(4, {:white, :king})
    |> Board.put(12, {:white, :pawn})
    |> Board.put(28, {:white, :pawn})
    |> Board.put(36, {:black, :pawn})
    |> Board.put(52, {:black, :pawn})
    |> Board.put(60, {:black, :king})
    |> Board.put(63, {:black, :rook})

  Benchee.run(
    %{
      "board_encode" => fn ->
        :erlang.term_to_binary(board)
      end,
      "board_hash" => fn ->
        :crypto.hash(:sha256, :erlang.term_to_binary(board))
      end,
      "piece_at" => fn ->
        Board.get(board, 28)
      end,
      "put_piece" => fn ->
        Board.put(board, 28, {:white, :queen})
      end,
      "remove_piece" => fn ->
        Board.remove(board, 28)
      end,
      "pieces" => fn ->
        Board.pieces(board)
      end
    },
    time: 5,
    memory_time: 2
  )
end
