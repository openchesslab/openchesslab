defmodule Web.Accuracy do
  @moduledoc """
  Move- and game-accuracy percentages from a reviewed eval series, following
  lichess's published accuracy model (lichess.org/page/accuracy and lila's
  modules/analyse AccuracyPercent.scala): a move's accuracy maps its Win%
  drop to an exponential curve fitted to real games, and a game's accuracy is
  the mean of each side's volatility-weighted mean and harmonic mean of its
  move accuracies. Reimplemented here in our own code.
  """

  @move_a 103.1668100711649
  @move_k 0.04354415386753951
  @move_b -3.166924740191411

  @doc """
  The accuracy of one move given the mover's Win% before and after. A move
  that holds or improves the mover's position is 100; drops map to the fitted
  curve, clamped to 0..100 (plus lila's +1 uncertainty bonus).
  """
  @spec move(float(), float()) :: float()
  def move(win_before, win_after) when win_before <= win_after, do: 100.0

  def move(win_before, win_after) do
    diff = win_before - win_after
    raw = @move_a * :math.exp(-@move_k * diff) + @move_b
    (raw + 1) |> min(100.0) |> max(0.0)
  end

  @doc """
  Game accuracy per color from the white-perspective Win% series — one value
  per position, so `length(series) - 1` moves — and the side that moves
  first. Each side gets the mean of its volatility-weighted mean and harmonic
  mean of its move accuracies; a side with no moves gets nil.
  """
  @spec game([float()], :white | :black) :: %{white: float() | nil, black: float() | nil}
  def game(win_percents, start_color) when is_list(win_percents) do
    total = length(win_percents) - 1

    if total < 1 do
      %{white: nil, black: nil}
    else
      window = min(8, max(2, div(total, 10)))
      first_window = Enum.take(win_percents, window)

      windows =
        List.duplicate(first_window, window - 2) ++
          Enum.chunk_every(win_percents, window, 1, :discard)

      weights = Enum.map(windows, &window_weight/1)

      moves =
        win_percents
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.zip(weights)
        |> Enum.with_index()
        |> Enum.group_by(fn {{_pair, _weight}, index} ->
          if rem(index, 2) == if(start_color == :white, do: 0, else: 1), do: :white, else: :black
        end)

      %{
        white: color_accuracy(Map.get(moves, :white, []), :white),
        black: color_accuracy(Map.get(moves, :black, []), :black)
      }
    end
  end

  # One color's game accuracy from its own moves: the mean of the
  # volatility-weighted mean and the harmonic mean of the move accuracies.
  # Scoring is oriented per side: for black, the Win% order mirrors.
  defp color_accuracy([], _side), do: nil

  defp color_accuracy(own, side) do
    accuracies =
      Enum.map(own, fn {{[prev, next], weight}, _index} ->
        {win_before, win_after} = if side == :white, do: {prev, next}, else: {next, prev}
        {move(win_before, win_after), weight}
      end)

    mean(weighted_mean(accuracies), harmonic_mean(Enum.map(accuracies, &elem(&1, 0))))
  end

  defp mean(nil, nil), do: nil
  defp mean(a, b), do: ((a || 0.0) + (b || 0.0)) / 2

  defp weighted_mean([]), do: nil

  defp weighted_mean(accuracies) do
    total_weight = Enum.sum(Enum.map(accuracies, &elem(&1, 1)))

    if total_weight == 0.0,
      do: nil,
      else:
        Enum.sum(Enum.map(accuracies, fn {accuracy, weight} -> accuracy * weight end)) /
          total_weight
  end

  defp harmonic_mean([]), do: nil

  defp harmonic_mean(values) do
    if Enum.any?(values, &(&1 == 0.0)) do
      0.0
    else
      length(values) / Enum.sum(Enum.map(values, &(1.0 / &1)))
    end
  end

  # Volatility weight of a window: the standard deviation of its Win% values,
  # clamped like lila's (0.5..12), so decided phases barely weigh.
  defp window_weight(window) do
    count = length(window)
    mean = Enum.sum(window) / count

    variance =
      Enum.sum(Enum.map(window, fn value -> (value - mean) * (value - mean) end)) / count

    :math.sqrt(variance) |> max(0.5) |> min(12.0)
  end
end
