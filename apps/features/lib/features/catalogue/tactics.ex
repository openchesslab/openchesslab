defmodule Features.Catalogue.Tactics do
  @moduledoc """
  Spec section 12 — tactical geometry: pins, forks, skewers, discovered
  attacks, x-rays, batteries, defenders and loose/hanging pieces.
  """

  alias Features.Catalogue.{AttackMap, TacticMap}
  alias Features.Chess.{Board, Square}
  alias Features.Feature

  @spec features() :: [Feature.t()]
  def features do
    [
      Feature.new("tactics.pin", 12, [{12, "pin"}], fn board ->
        per_color(board, fn board, color ->
          board |> TacticMap.pins(color) |> Map.keys() |> Enum.sort() |> to_alg()
        end)
      end),
      Feature.new("tactics.absolute_pin", 12, [{12, "absolute pin"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> TacticMap.pins(color)
          |> Enum.filter(fn {_square, kind} -> kind == :absolute end)
          |> Enum.map(fn {square, _kind} -> square end)
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("tactics.relative_pin", 12, [{12, "relative pin"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> TacticMap.pins(color)
          |> Enum.filter(fn {_square, kind} -> kind == :relative end)
          |> Enum.map(fn {square, _kind} -> square end)
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("tactics.skewer", 12, [{12, "skewer"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.skewers(board, color) |> to_alg()
        end)
      end),
      Feature.new("tactics.fork", 12, [{12, "fork"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.multi_attackers(board, color, [:pawns, :knights]) |> to_alg()
        end)
      end),
      Feature.new("tactics.discovered_attack", 12, [{12, "discovered attack"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.discoveries(board, color) |> Map.keys() |> Enum.sort() |> to_alg()
        end)
      end),
      Feature.new("tactics.discovered_check", 12, [{12, "discovered check"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> TacticMap.discoveries(color)
          |> Enum.filter(fn {_disc, info} -> info.king end)
          |> Enum.map(fn {disc, _info} -> disc end)
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("tactics.double_attack", 12, [{12, "double attack"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.multi_attackers(board, color, [:bishops, :rooks, :queens, :kings]) |> to_alg()
        end)
      end),
      Feature.new("tactics.double_check", 12, [{12, "double check"}], fn board ->
        per_color(board, fn board, color ->
          AttackMap.attack_counts(board, Board.opposite(color))
          |> Map.get(TacticMap.king_square(board, color), 0) >= 2
        end)
      end),
      Feature.new("tactics.xray_attack", 12, [{12, "x-ray attack"}], fn board ->
        per_color(board, fn board, color ->
          board
          |> TacticMap.discoveries(color)
          |> Enum.map(fn {_disc, info} -> info.target end)
          |> Enum.uniq()
          |> Enum.sort()
          |> to_alg()
        end)
      end),
      Feature.new("tactics.battery", 12, [{12, "battery"}], fn board ->
        per_color(board, fn board, color -> TacticMap.battery?(board, color) end)
      end),
      Feature.new("tactics.overloaded_piece", 12, [{12, "overloaded piece"}], fn board ->
        per_color(board, fn board, color -> TacticMap.overloaded(board, color) |> to_alg() end)
      end),
      Feature.new(
        "tactics.deflection_possibility",
        12,
        [{12, "deflection possibility"}],
        fn board ->
          per_color(board, fn board, color ->
            TacticMap.deflection_squares(board, color) |> to_alg()
          end)
        end
      ),
      Feature.new("tactics.decoy_possibility", 12, [{12, "decoy possibility"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.decoy_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new("tactics.removal_of_defender", 12, [{12, "removal of defender"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.sole_defenders(board, color) |> to_alg()
        end)
      end),
      Feature.new("tactics.interference", 12, [{12, "interference"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.interference_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new("tactics.clearance", 12, [{12, "clearance"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.clearance_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new(
        "tactics.zwischenzug_possibilities",
        12,
        [{12, "zwischenzug possibilities"}],
        fn board ->
          per_color(board, fn board, color -> TacticMap.zwischenzug?(board, color) end)
        end
      ),
      Feature.new("tactics.trapped_piece", 12, [{12, "trapped piece"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.trapped_squares(board, color) |> to_alg()
        end)
      end),
      Feature.new("tactics.loose_piece", 12, [{12, "loose piece"}], fn board ->
        per_color(board, fn board, color -> TacticMap.loose_squares(board, color) |> to_alg() end)
      end),
      Feature.new("tactics.hanging_piece", 12, [{12, "hanging piece"}], fn board ->
        per_color(board, fn board, color ->
          TacticMap.hanging_squares(board, color) |> to_alg()
        end)
      end)
    ]
  end

  defp per_color(board, fun) do
    %{"white" => fun.(board, :white), "black" => fun.(board, :black)}
  end

  defp to_alg(squares), do: Enum.map(squares, &Square.to_string/1)
end
