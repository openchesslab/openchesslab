# Oracle-vergelijking (fase 2): Features-catalogus vs. python-chess op de
# geëxporteerde steekproef. Vereist dat feature_oracle_export.exs en
# feature_oracle.py eerst gedraaid hebben.
#
# Gebruik:
#   DATABASE_URL="ecto://openchesslab:openchesslab@localhost/openchesslab_bench" \
#     mix run apps/analysis/benchmarks/feature_oracle_check.exs

Logger.configure(level: :warning)

Application.ensure_all_started(:features)

defmodule Oracle do
  def read_fens(path) do
    path
    |> File.stream!()
    |> Map.new(fn line ->
      [id, fen] = String.trim_trailing(line) |> String.split("\t", parts: 2)
      {String.to_integer(id), fen}
    end)
  end

  def read_oracle(path) do
    path
    |> File.stream!()
    |> Enum.map(fn line -> Jason.decode!(line) end)
  end
end

fens = Oracle.read_fens("/tmp/opencode/oracle-fens.txt")
records = Oracle.read_oracle("/tmp/opencode/oracle-out.jsonl")

defmodule Check do
  def sort_colors(map) do
    Map.new(map, fn {color, squares} -> {color, Enum.sort(squares)} end)
  end

  def compare(records, fens) do
    pairs = [
      {"mobility.legal_moves (stm)", fn vec, oracle -> vec["mobility.legal_moves"] end,
       fn oracle -> oracle["legal_moves_stm"] end},
      {"mobility.per_side (pseudo-legaal)", fn vec, _oracle -> vec["mobility.per_side"] end,
       fn oracle -> %{"white" => oracle["pseudo_white"], "black" => oracle["pseudo_black"]} end},
      {"tactics.absolute_pin", fn vec, _oracle -> sort_colors(vec["tactics.absolute_pin"]) end,
       fn oracle ->
         %{"white" => oracle["absolute_pin_white"], "black" => oracle["absolute_pin_black"]}
       end},
      {"threats.check (kleur in schaak)", fn vec, _oracle -> vec["threats.check"] end,
       fn oracle ->
         stm_in_check = oracle["stm_in_check"]

         %{
           "white" => oracle["stm"] == "w" and stm_in_check,
           "black" => oracle["stm"] == "b" and stm_in_check
         }
       end},
      {"threats.aantal_checks", fn vec, _oracle -> vec["threats.aantal_checks"] end,
       fn oracle -> %{"white" => oracle["checks_white"], "black" => oracle["checks_black"]} end},
      {"attacks.attacked_pieces (derde stem; kruisperspectief)",
       fn vec, _oracle -> sort_colors(vec["attacks.attacked_pieces"]) end,
       fn oracle ->
         # De catalogus telt per kleur wat die kleur aanvalt — het orakel
         # wat er op die kleur aangevallen wordt: kruislings vergelijken.
         %{"white" => oracle["attacked_black"], "black" => oracle["attacked_white"]}
       end},
      {"attacks.defended_squares (derde stem)",
       fn vec, _oracle -> sort_colors(vec["attacks.defended_squares"]) end,
       fn oracle ->
         %{"white" => oracle["defended_white"], "black" => oracle["defended_black"]}
       end}
    ]

    for {name, catalogue_fn, oracle_fn} <- pairs, into: %{} do
      initial = %{checked: 0, mismatches: 0, examples: []}

      Enum.reduce(records, initial, fn oracle, acc ->
        fen = Map.fetch!(fens, oracle["id"])
        vec = Features.extract(fen, sections: [5, 10, 12, 13]).features

        left = catalogue_fn.(vec, oracle)
        right = oracle_fn.(oracle)

        if left == right do
          %{acc | checked: acc.checked + 1}
        else
          examples =
            if length(acc.examples) < 3,
              do: [{fen, left, right} | acc.examples],
              else: acc.examples

          %{acc | checked: acc.checked + 1, mismatches: acc.mismatches + 1, examples: examples}
        end
      end)
      |> then(&{name, &1})
    end
  end
end

report = Check.compare(records, fens)

IO.puts("\n=== ORACLE-RAPPORT (python-chess vs catalogus, #{length(records)} posities) ===\n")

Enum.each(report, fn {name, %{checked: checked, mismatches: mismatches, examples: examples}} ->
  status = if mismatches == 0, do: "OK  ", else: "DIFF"
  IO.puts("#{status} #{name}: #{mismatches}/#{checked} mismatches")

  Enum.each(Enum.reverse(examples), fn {fen, left, right} ->
    IO.puts("      #{fen}")
    IO.puts("        catalogus: #{inspect(left, limit: 8)}")
    IO.puts("        orakel:    #{inspect(right, limit: 8)}")
  end)
end)
