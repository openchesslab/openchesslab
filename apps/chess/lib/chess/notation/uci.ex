defmodule Chess.Notation.UCI do
  @moduledoc """
  Parses UCI coordinate notation (for example `e2e4` or `e7e8q`) and renders
  engine principal variations in SAN.

  UCI coordinates alone do not say whether a move is legal, so parsing always
  resolves against the legal moves of the given position.
  """

  alias Chess.Move
  alias Chess.Notation.SAN
  alias Chess.Position
  alias Chess.Square

  @promotions %{"q" => :queen, "r" => :rook, "b" => :bishop, "n" => :knight}

  @doc """
  Resolves a UCI move against the legal moves of the position.

  Returns the fully qualified legal move (including its promotion, if any),
  or `:error` when the coordinates do not describe a legal move.
  """
  @spec parse_move(Position.t(), String.t()) :: {:ok, Move.t()} | :error
  def parse_move(%Position{} = position, <<from::binary-size(2), to::binary-size(2)>>) do
    parse_move(position, from, to, nil)
  end

  def parse_move(
        %Position{} = position,
        <<from::binary-size(2), to::binary-size(2), promo::binary-size(1)>>
      ) do
    case Map.fetch(@promotions, promo) do
      {:ok, promotion} -> parse_move(position, from, to, promotion)
      _ -> :error
    end
  end

  def parse_move(%Position{}, _uci), do: :error

  @doc """
  Renders a space-separated UCI principal variation as a list of SAN moves.

  Stops at the first move that does not resolve legally, returning the SAN
  rendered so far; an empty result means even the first move failed.
  """
  @spec pv_to_san(Position.t(), String.t()) :: [String.t()]
  def pv_to_san(%Position{} = position, pv) when is_binary(pv) do
    pv
    |> String.split(" ", trim: true)
    |> Enum.reduce_while({position, []}, fn uci, {current, sans} ->
      with {:ok, move} <- parse_move(current, uci),
           {:ok, san} <- SAN.format(current, move),
           {:ok, next} <- Position.apply_move(current, move) do
        {:cont, {next, [san | sans]}}
      else
        _ -> {:halt, {current, sans}}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  @doc "Formats a move in UCI coordinate notation, e.g. `e2e4` or `e7e8q`."
  @spec format(Move.t()) :: String.t()
  def format(%Move{from: from, to: to, promotion: promotion}) do
    Square.to_algebraic(from) <>
      Square.to_algebraic(to) <>
      case promotion do
        nil -> ""
        :queen -> "q"
        :rook -> "r"
        :bishop -> "b"
        :knight -> "n"
      end
  end

  defp parse_move(position, from, to, promotion) do
    with from_square when is_integer(from_square) <- Square.from_algebraic(from),
         to_square when is_integer(to_square) <- Square.from_algebraic(to) do
      position
      |> Position.legal_moves()
      |> Enum.find(:error, fn move ->
        move.from == from_square and move.to == to_square and move.promotion == promotion
      end)
      |> case do
        :error -> :error
        %Move{} = move -> {:ok, move}
      end
    else
      _ -> :error
    end
  end
end
