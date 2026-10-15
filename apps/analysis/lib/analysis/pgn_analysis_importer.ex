defmodule Analysis.PgnAnalysisImporter do
  @moduledoc """
  Imports a single PGN as a played game and an annotated mainline analysis.

  Canonical game identity remains solely its positions and moves. Human comments
  and NAGs belong to the new analysis. Machine comment commands are stripped;
  side variations (including their annotations) are not imported yet.
  Game-record and analysis persistence commit together or roll back together.
  """

  alias Analysis.{Analyses, AnalysisStore, Node, PgnImporter}
  alias OpenChessLab.Repo

  @symbols %{"!" => 1, "?" => 2, "!!" => 3, "??" => 4, "!?" => 5, "?!" => 6}
  @tokens ~r/\{[^}]*\}|;[^\r\n]*|[()]|\$\d+|[^\s{}();$]+|[{}$]/u

  def import(analysis_id, record_id, pgn) do
    with {:ok, parsed} <- PgnImporter.parse(pgn),
         {:ok, notes} <- annotations(pgn, length(parsed.moves)) do
      Repo.transaction(fn ->
        with {:ok, record} <- PgnImporter.import_parsed(record_id, parsed),
             {:ok, analysis, revision} <- Analyses.create_from_game_record(analysis_id, record.id),
             analysis = %{analysis | root: annotate(analysis.root, notes, 0)},
             {:ok, revision} <- AnalysisStore.update(analysis, revision) do
          {analysis, revision}
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
      |> case do
        {:ok, {analysis, revision}} -> {:ok, analysis, revision}
        {:error, _} = error -> error
      end
    end
  end

  defp annotations(pgn, expected_plies) do
    text = String.replace(pgn, ~r/^\s*\[[^\]]+\]\s*$/m, " ")

    @tokens
    |> Regex.scan(text)
    |> Enum.reduce_while({:ok, %{ply: 0, depth: 0, notes: %{}}}, fn [token], {:ok, state} ->
      case token(token, state) do
        {:ok, state} -> {:cont, {:ok, state}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, %{ply: ^expected_plies, depth: 0, notes: notes}} -> {:ok, notes}
      {:ok, _} -> invalid("Unbalanced variations or annotation/move mismatch")
      {:error, _} = error -> error
    end
  end

  defp token("(", state), do: {:ok, %{state | depth: state.depth + 1}}
  defp token(")", %{depth: 0}), do: invalid("Unexpected variation ending")
  defp token(")", state), do: {:ok, %{state | depth: state.depth - 1}}
  defp token(_, %{depth: depth} = state) when depth > 0, do: {:ok, state}

  defp token("{" <> comment, state) do
    if String.ends_with?(comment, "}"),
      do: comment(String.slice(comment, 0..-2//1), state),
      else: invalid("Unclosed comment")
  end

  defp token(";" <> comment, state), do: comment(comment, state)

  defp token("$" <> number, state) do
    case Integer.parse(number) do
      {nag, ""} -> nag(nag, state)
      _ -> invalid("Invalid numeric annotation")
    end
  end

  defp token(text, state) do
    text = String.replace(text, ~r/^\d+\.(?:\.\.)?/, "")

    cond do
      text in ["", "1-0", "0-1", "1/2-1/2", "*"] ->
        {:ok, state}

      Map.has_key?(@symbols, text) ->
        nag(@symbols[text], state)

      true ->
        state = %{state | ply: state.ply + 1}

        case Regex.run(~r/[!?]+$/, text) do
          nil -> {:ok, state}
          [suffix] -> nag(@symbols[suffix], state)
        end
    end
  end

  defp comment(text, state) do
    text = text |> String.replace(~r/\[%[^\]]*\]/, "") |> String.trim()

    if text == "" do
      {:ok, state}
    else
      update_note(state, fn note -> %{note | comments: [text | note.comments]} end)
    end
  end

  defp nag(nag, state) do
    note = Map.get(state.notes, state.ply, %{comments: [], nags: []})
    nags = Enum.uniq(note.nags ++ [nag])

    if state.ply > 0 and Node.valid_nags?(nags),
      do: update_note(state, fn note -> %{note | nags: nags} end),
      else: invalid("Invalid or excessive move annotations")
  end

  defp update_note(state, fun) do
    notes = Map.update(state.notes, state.ply, fun.(%{comments: [], nags: []}), fun)
    {:ok, %{state | notes: notes}}
  end

  defp annotate(node, notes, ply) do
    note = Map.get(notes, ply, %{comments: [], nags: []})
    comment = if note.comments != [], do: note.comments |> Enum.reverse() |> Enum.join("\n")
    children = Enum.map(node.children, &annotate(&1, notes, ply + 1))
    %{node | comment: comment, nags: note.nags, children: children}
  end

  defp invalid(message), do: {:error, {:invalid_pgn, message}}
end
