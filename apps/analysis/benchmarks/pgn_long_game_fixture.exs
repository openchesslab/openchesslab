defmodule Analysis.PgnLongGameFixture do
  @moduledoc """
  Deterministic legal long-game PGN fixtures for the import phase benchmark.

  Generation is deliberately outside benchmark timings. Each candidate starts
  from the standard position, uses a local seeded RNG, and is accepted only
  when it reaches the requested ply count. Canonical uniqueness is checked by
  the complete SAN main line, not by the Event header.
  """

  alias Chess.Notation.SAN
  alias Chess.Position

  @spec build_fixture(Path.t(), pos_integer(), pos_integer(), non_neg_integer()) ::
          non_neg_integer()
  def build_fixture(path, game_count, plies, duplicate_percent)
      when is_binary(path) and is_integer(game_count) and game_count > 0 and is_integer(plies) and
             plies >= 2 and plies <= 120 and is_integer(duplicate_percent) and
             duplicate_percent >= 0 and duplicate_percent < 100 do
    unique_count = game_count - div(game_count * duplicate_percent, 100)
    unique_games = generate_unique_games(unique_count, plies)
    unique_tuple = List.to_tuple(unique_games)

    games =
      1..game_count
      |> Enum.map(fn index ->
        if index <= unique_count do
          elem(unique_tuple, index - 1)
        else
          elem(unique_tuple, rem(index - unique_count - 1, unique_count))
        end
      end)
      |> Enum.with_index()
      |> Enum.sort_by(fn {_movetext, index} -> rem(index * 7_919 + 17, game_count) end)
      |> Enum.map(fn {movetext, _index} -> movetext end)

    File.open!(path, [:write, :utf8], fn io ->
      games
      |> Enum.with_index(1)
      |> Enum.each(fn {movetext, index} ->
        IO.write(io, """
        [Event "PGN long-game profile #{index}"]
        [White "Alice"]
        [Black "Bob"]
        [Result "*"]

        #{movetext}

        """)
      end)
    end)

    File.stat!(path).size
  end

  def build_fixture(_path, _game_count, _plies, _duplicate_percent) do
    raise ArgumentError,
          "expected game_count > 0, 2 <= plies <= 120, and 0 <= duplicate_percent < 100"
  end

  defp generate_unique_games(count, plies) do
    build_unique(1, count, plies, max(200, count * 40), MapSet.new(), [])
  end

  defp build_unique(_seed, 0, _plies, _limit, _seen, acc), do: Enum.reverse(acc)

  defp build_unique(seed, remaining, plies, limit, seen, acc) do
    if seed > limit do
      raise "Could not generate enough distinct legal #{plies}-ply games"
    end

    case sample_game(seed, plies) do
      {:ok, movetext} ->
        if MapSet.member?(seen, movetext) do
          build_unique(seed + 1, remaining, plies, limit, seen, acc)
        else
          build_unique(
            seed + 1,
            remaining - 1,
            plies,
            limit,
            MapSet.put(seen, movetext),
            [movetext | acc]
          )
        end

      :terminal ->
        build_unique(seed + 1, remaining, plies, limit, seen, acc)
    end
  end

  defp sample_game(seed, plies) do
    random_state = :rand.seed_s(:exsss, {104_729 + seed, 73 + seed * 31, 11 + seed * 37})
    sample_moves(Position.starting_position(), plies, random_state, [])
  end

  defp sample_moves(_position, 0, _random_state, reversed_sans) do
    {:ok, reversed_sans |> Enum.reverse() |> format_movetext()}
  end

  defp sample_moves(position, remaining, random_state, reversed_sans) do
    moves = Position.legal_moves(position)

    case moves do
      [] ->
        :terminal

      _ ->
        {move_index, next_random_state} = :rand.uniform_s(length(moves), random_state)
        move = Enum.at(moves, move_index - 1)

        {:ok, san} = SAN.format(position, move)
        {:ok, next_position} = Position.apply_move(position, move)

        sample_moves(next_position, remaining - 1, next_random_state, [san | reversed_sans])
    end
  end

  defp format_movetext(sans) do
    sans
    |> Enum.chunk_every(2)
    |> Enum.with_index(1)
    |> Enum.map_join(" ", fn
      {[white, black], number} -> "#{number}. #{white} #{black}"
      {[white], number} -> "#{number}. #{white}"
    end)
    |> Kernel.<>(" *")
  end
end
