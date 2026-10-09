defmodule Features.CatalogueTest do
  use ExUnit.Case, async: true

  alias Features.Catalogue
  alias Features.Chess.FEN
  alias Features.Feature

  @spec_path Path.expand("../../../../docs/POSITION_FEATURES.md", __DIR__)

  @section_prefix %{
    1 => "state.",
    2 => "material.",
    3 => "pawns.",
    4 => "placement.",
    5 => "mobility.",
    6 => "center.",
    7 => "space.",
    8 => "squares.",
    9 => "lines.",
    10 => "attacks.",
    11 => "king."
  }

  # Sections the catalogue implements so far; grow this list per milestone
  # until it covers the whole spec (last section wins).
  @sections_done [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11]

  test "feature ids are unique" do
    ids = Enum.map(Catalogue.all(), & &1.id)

    assert ids == Enum.uniq(ids)
  end

  test "ids carry their section prefix and claims stay in their section" do
    for feature <- Catalogue.all() do
      assert String.starts_with?(feature.id, Map.fetch!(@section_prefix, feature.section)),
             "id #{feature.id} does not match section #{feature.section}"

      for {section, _bullet} <- feature.claims do
        assert section == feature.section
      end
    end
  end

  test "every spec bullet of a done section is claimed by at least one feature" do
    missing = parse_spec() |> filter_done() |> MapSet.difference(claimed()) |> Enum.sort()

    assert missing == [], "unclaimed spec bullets:\n" <> bullets(missing)
  end

  test "every claim points at a real spec bullet" do
    stale = claimed() |> MapSet.difference(parse_spec()) |> Enum.sort()

    assert stale == [], "claims without a spec bullet:\n" <> bullets(stale)
  end

  test "every done spec section has at least one feature" do
    for section <- @sections_done do
      refute Catalogue.by_section(section) == [], "section #{section} has no features"
    end
  end

  test "extract computes every catalogue feature for the start position" do
    result = Features.extract(FEN.start_fen())
    expected = Catalogue.all() |> Enum.map(& &1.id) |> Enum.sort()

    assert result.version == Features.version()
    assert result.fen == FEN.start_fen()
    assert result.features |> Map.keys() |> Enum.sort() == expected
  end

  test "extract accepts a board as well" do
    board = FEN.parse(FEN.start_fen())

    assert Features.extract(board).fen == FEN.start_fen()
  end

  test "extract can be restricted to sections" do
    result = Features.extract(FEN.start_fen(), sections: [1])

    refute result.features == %{}
    assert Enum.all?(Map.keys(result.features), &String.starts_with?(&1, "state."))
  end

  test "to_map returns string-keyed plain data" do
    map = FEN.start_fen() |> Features.extract() |> Features.Result.to_map()

    assert %{"version" => _, "fen" => _, "features" => %{"state.side_to_move" => "white"}} = map
  end

  test "unknown feature id raises" do
    assert_raise ArgumentError, fn -> Catalogue.fetch!("nope") end
    assert %Feature{id: "state.side_to_move"} = Catalogue.fetch!("state.side_to_move")
  end

  defp filter_done(spec) do
    for {section, bullet} <- spec,
        section in @sections_done,
        into: MapSet.new(),
        do: {section, bullet}
  end

  defp claimed do
    for feature <- Catalogue.all(),
        {section, bullet} <- feature.claims,
        into: MapSet.new(),
        do: {section, bullet}
  end

  defp parse_spec do
    @spec_path
    |> File.stream!()
    |> Enum.reduce({nil, MapSet.new()}, fn line, {section, acc} ->
      line = String.trim_trailing(line)

      cond do
        header = Regex.run(~r/^\s*(- )?\*\*(\d+)\./, line) ->
          {header |> Enum.at(2) |> String.to_integer(), acc}

        section != nil ->
          case Regex.run(~r/^  - (.+)$/, line) do
            nil ->
              {section, acc}

            bullet ->
              {section, MapSet.put(acc, {section, bullet |> Enum.at(1) |> String.trim()})}
          end

        true ->
          {section, acc}
      end
    end)
    |> elem(1)
  end

  defp bullets(list) do
    Enum.map_join(list, "\n", fn {section, bullet} -> "  #{section}. #{bullet}" end)
  end
end
