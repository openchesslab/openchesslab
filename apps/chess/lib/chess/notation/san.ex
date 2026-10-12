defmodule Chess.Notation.SAN do
  @moduledoc """
  Formats and parses legal chess moves using Standard Algebraic Notation.

  SAN is canonical chess notation and is not localized.

  `format/2` returns the canonical SAN representation of a legal move.
  `parse/2` performs the inverse operation by resolving canonical SAN
  against the legal moves in the supplied position.

  PGN-specific conveniences such as zero-based castling (`0-0`),
  annotation glyphs (`!`, `?`) and `e.p.` markers do not belong to SAN
  itself and are normalized by the PGN reader before calling `parse/2`.
  """

  alias Chess.Move
  alias Chess.Position
  alias Chess.Square

  @destination_regex ~r/([a-h][1-8])(?:=[QRBN])?$/

  @spec format(Position.t(), Move.t()) ::
          {:ok, String.t()} | {:error, :illegal_move}
  def format(%Position{} = position, %Move{} = move) do
    legal_moves =
      Position.legal_moves(position)

    if move in legal_moves do
      {:ok,
       format_legal_move(
         position,
         move,
         legal_moves
       )}
    else
      {:error, :illegal_move}
    end
  end

  @spec parse(Position.t(), String.t()) ::
          {:ok, Move.t()} | {:error, :invalid_san}
  def parse(%Position{} = position, san) when is_binary(san) do
    case quiet_pawn_destination(san) do
      {:ok, to} ->
        parse_quiet_pawn(position, san, to)

      :other ->
        case pawn_capture_destination(san) do
          {:ok, source_file, to} -> parse_pawn_capture(position, san, source_file, to)
          :other -> parse_with_legal_moves(position, san)
        end
    end
  end

  def parse(%Position{}, _san) do
    {:error, :invalid_san}
  end

  # A non-capturing pawn SAN has only a destination and optional check suffix.
  # Captures, promotions, castling, and piece moves retain the reference parser.
  defp quiet_pawn_destination(<<file, rank>>) when file in ?a..?h and rank in ?1..?8 do
    {:ok, (rank - ?1) * 8 + file - ?a}
  end

  defp quiet_pawn_destination(<<file, rank, suffix>>)
       when file in ?a..?h and rank in ?1..?8 and suffix in [?+, ?#] do
    {:ok, (rank - ?1) * 8 + file - ?a}
  end

  defp quiet_pawn_destination(_san), do: :other

  # Pawn captures always identify the source file. Promotions continue to
  # use the reference SAN parser in this slice.
  defp pawn_capture_destination(<<from_file, ?x, to_file, rank>>)
       when from_file in ?a..?h and to_file in ?a..?h and rank in ?1..?8 do
    {:ok, from_file, (rank - ?1) * 8 + to_file - ?a}
  end

  defp pawn_capture_destination(<<from_file, ?x, to_file, rank, suffix>>)
       when from_file in ?a..?h and to_file in ?a..?h and rank in ?1..?8 and suffix in [?+, ?#] do
    {:ok, from_file, (rank - ?1) * 8 + to_file - ?a}
  end

  defp pawn_capture_destination(_san), do: :other

  defp parse_pawn_capture(position, san, source_file, to) do
    color = position.side_to_move
    destination_file = rem(to, 8)
    origin_rank = div(to, 8) + if(color == :white, do: -1, else: 1)
    file = source_file - ?a

    if origin_rank in 0..7 and abs(file - destination_file) == 1 do
      from = origin_rank * 8 + file

      if Position.piece_at(position, from) == {color, :pawn} do
        move = Move.new(from, to)

        case Position.apply_move(position, move) do
          {:ok, next_position} ->
            base = <<source_file, ?x>> <> Square.to_algebraic(to)
            canonical = base <> check_suffix_after_move(next_position)
            if canonical == san, do: {:ok, move}, else: {:error, :invalid_san}

          {:error, :illegal_move} ->
            {:error, :invalid_san}
        end
      else
        {:error, :invalid_san}
      end
    else
      {:error, :invalid_san}
    end
  end

  defp parse_quiet_pawn(position, san, to) do
    if Position.piece_at(position, to) == nil do
      color = position.side_to_move
      advance = if color == :white, do: 8, else: -8

      # One-step first, then initial-rank double-step. A pawn on the one-step
      # origin also blocks a pawn on the double-step origin.
      Enum.find_value([to - advance, to - 2 * advance], {:error, :invalid_san}, fn from ->
        if from in 0..63 and Position.piece_at(position, from) == {color, :pawn} do
          move = Move.new(from, to)

          case Position.apply_move(position, move) do
            {:ok, next_position} ->
              canonical = Square.to_algebraic(to) <> check_suffix_after_move(next_position)
              if canonical == san, do: {:ok, move}

            {:error, :illegal_move} ->
              nil
          end
        end
      end)
    else
      {:error, :invalid_san}
    end
  end

  defp parse_with_legal_moves(position, san) do
    legal_moves = Position.legal_moves(position)
    candidate_moves = candidate_moves(position, san, legal_moves)

    case Enum.find(candidate_moves, fn move ->
           format_legal_move(position, move, legal_moves) == san
         end) do
      %Move{} = move -> {:ok, move}
      nil -> {:error, :invalid_san}
    end
  end

  defp candidate_moves(position, san, legal_moves) do
    san_without_check =
      remove_check_suffix(san)

    case san_without_check do
      "O-O" ->
        Enum.filter(
          legal_moves,
          &kingside_castle_candidate?(
            position,
            &1
          )
        )

      "O-O-O" ->
        Enum.filter(
          legal_moves,
          &queenside_castle_candidate?(
            position,
            &1
          )
        )

      _other ->
        ordinary_candidate_moves(
          position,
          san_without_check,
          legal_moves
        )
    end
  end

  defp ordinary_candidate_moves(position, san, legal_moves) do
    case Regex.run(
           @destination_regex,
           san,
           capture: :all_but_first
         ) do
      [destination] ->
        destination_square =
          Square.from_algebraic(destination)

        piece =
          san_piece(san)

        Enum.filter(
          legal_moves,
          fn %Move{
               from: from,
               to: to
             } ->
            to == destination_square and
              Position.piece_at(
                position,
                from
              ) ==
                {
                  position.side_to_move,
                  piece
                }
          end
        )

      _no_destination ->
        []
    end
  end

  defp kingside_castle_candidate?(position, %Move{} = move) do
    castle_candidate?(
      position,
      move
    ) and
      move.to > move.from
  end

  defp queenside_castle_candidate?(position, %Move{} = move) do
    castle_candidate?(
      position,
      move
    ) and
      move.to < move.from
  end

  defp castle_candidate?(position, %Move{} = move) do
    Position.piece_at(
      position,
      move.from
    ) ==
      {
        position.side_to_move,
        :king
      } and
      abs(move.to - move.from) == 2
  end

  defp san_piece(<<"K", _rest::binary>>) do
    :king
  end

  defp san_piece(<<"Q", _rest::binary>>) do
    :queen
  end

  defp san_piece(<<"R", _rest::binary>>) do
    :rook
  end

  defp san_piece(<<"B", _rest::binary>>) do
    :bishop
  end

  defp san_piece(<<"N", _rest::binary>>) do
    :knight
  end

  defp san_piece(_san) do
    :pawn
  end

  defp remove_check_suffix(<<>>) do
    ""
  end

  defp remove_check_suffix(san) do
    prefix_size =
      byte_size(san) - 1

    case san do
      <<prefix::binary-size(^prefix_size), suffix>>
      when suffix in [?+, ?#] ->
        prefix

      _other ->
        san
    end
  end

  defp format_legal_move(position, %Move{} = move, legal_moves) do
    {_color, piece} =
      Position.piece_at(
        position,
        move.from
      )

    notation =
      if castle?(
           piece,
           move
         ) do
        format_castle(move)
      else
        destination =
          Square.to_algebraic(move.to)

        capture? =
          capture?(
            position,
            piece,
            move
          )

        case piece do
          :pawn ->
            format_pawn_move(
              move,
              destination,
              capture?
            )

          piece ->
            piece_letter(piece) <>
              disambiguation(
                position,
                move,
                piece,
                legal_moves
              ) <>
              capture_marker(capture?) <>
              destination
        end
      end

    notation <>
      check_suffix(
        position,
        move
      )
  end

  defp castle?(:king, %Move{from: from, to: to}) do
    abs(to - from) ==
      2
  end

  defp castle?(_piece, _move) do
    false
  end

  defp format_castle(%Move{from: from, to: to}) when to > from do
    "O-O"
  end

  defp format_castle(%Move{}) do
    "O-O-O"
  end

  defp format_pawn_move(move, destination, capture?) do
    prefix =
      if capture? do
        move.from
        |> Square.to_algebraic()
        |> String.first()
        |> Kernel.<>("x")
      else
        ""
      end

    prefix <>
      destination <>
      promotion_suffix(move.promotion)
  end

  defp disambiguation(position, move, piece, legal_moves) do
    alternatives =
      Enum.filter(
        legal_moves,
        fn candidate ->
          candidate != move and
            candidate.to == move.to and
            Position.piece_at(
              position,
              candidate.from
            ) ==
              {
                position.side_to_move,
                piece
              }
        end
      )

    case alternatives do
      [] ->
        ""

      alternatives ->
        source =
          Square.to_algebraic(move.from)

        source_file =
          String.first(source)

        source_rank =
          String.last(source)

        same_file? =
          Enum.any?(
            alternatives,
            fn candidate ->
              rem(
                candidate.from,
                8
              ) ==
                rem(
                  move.from,
                  8
                )
            end
          )

        same_rank? =
          Enum.any?(
            alternatives,
            fn candidate ->
              div(
                candidate.from,
                8
              ) ==
                div(
                  move.from,
                  8
                )
            end
          )

        cond do
          not same_file? ->
            source_file

          not same_rank? ->
            source_rank

          true ->
            source
        end
    end
  end

  defp capture?(position, :pawn, move) do
    Position.piece_at(
      position,
      move.to
    ) != nil or
      en_passant_capture?(
        position,
        move
      )
  end

  defp capture?(position, _piece, move) do
    Position.piece_at(
      position,
      move.to
    ) != nil
  end

  defp en_passant_capture?(%Position{en_passant: target}, %Move{to: target})
       when not is_nil(target) do
    true
  end

  defp en_passant_capture?(_position, _move) do
    false
  end

  defp promotion_suffix(nil) do
    ""
  end

  defp promotion_suffix(piece) do
    "=" <>
      piece_letter(piece)
  end

  defp check_suffix(position, move) do
    {:ok, next_position} = Position.apply_move(position, move)
    check_suffix_after_move(next_position)
  end

  defp check_suffix_after_move(next_position) do
    opponent = next_position.side_to_move

    cond do
      Position.checkmate?(next_position, opponent) -> "#"
      Position.in_check?(next_position, opponent) -> "+"
      true -> ""
    end
  end

  defp capture_marker(true) do
    "x"
  end

  defp capture_marker(false) do
    ""
  end

  defp piece_letter(:king) do
    "K"
  end

  defp piece_letter(:queen) do
    "Q"
  end

  defp piece_letter(:rook) do
    "R"
  end

  defp piece_letter(:bishop) do
    "B"
  end

  defp piece_letter(:knight) do
    "N"
  end
end
