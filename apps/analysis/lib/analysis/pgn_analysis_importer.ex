defmodule Analysis.PgnAnalysisImporter do
  @moduledoc """
  Imports a single PGN as a played game and an annotated analysis tree.

  Canonical game identity remains solely its mainline positions and moves.
  Human comments and NAGs belong to the new analysis. Machine comment commands
  are stripped. Side variations (including their annotations) are grafted as
  branches: a variation following a move is an alternative to that move, a
  sibling of the mainline child in the analysis tree. Game-record and analysis
  persistence commit together or roll back together.
  """

  alias Analysis.{Analyses, AnalysisStore, Node, PgnImporter}
  alias Analysis.PositionStore
  alias Chess.Notation.SAN
  alias Chess.Position
  alias OpenChessLab.Repo

  @symbols %{"!" => 1, "?" => 2, "!!" => 3, "??" => 4, "!?" => 5, "?!" => 6}
  @tokens ~r/\{[^}]*\}|;[^\r\n]*|[()]|\$\d+|[^\s{}();$]+|[{}$]/u

  # A move in the parsed PGN tree. `leading` holds comments written before the
  # move ("1. {note} e4", or right after "("); `comments` the ones after it.
  # Variations are alternative moves to this one: siblings in the analysis.
  @typep tree_move :: %{
           san: String.t(),
           leading: [String.t()],
           comments: [String.t()],
           nags: [integer()],
           variations: [[tree_move()]]
         }

  @spec import(String.t(), String.t(), String.t()) ::
          {:ok, Analysis.Analysis.t(), pos_integer()} | {:error, term()}
  def import(analysis_id, record_id, pgn) do
    with {:ok, parsed} <- PgnImporter.parse(pgn),
         {:ok, mainline} <- parse_tree(pgn),
         :ok <- check_mainline_agreement(mainline, parsed.moves) do
      Repo.transaction(fn ->
        with {:ok, record} <- PgnImporter.import_parsed(record_id, parsed),
             {:ok, analysis, revision} <- Analyses.create_from_game_record(analysis_id, record.id),
             {:ok, root} <- graft(analysis.root, parsed.initial_position, mainline),
             analysis = %{analysis | root: root},
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

  # Comments before the first mainline move belong to the root.
  defp graft(root, initial_position, [first | rest]) do
    comment = comment_text(first.leading)
    mainline = [%{first | leading: []} | rest]

    with {:ok, grafted} <- graft_line(root, initial_position, mainline) do
      {:ok, %{grafted | comment: comment || grafted.comment}}
    end
  end

  # Walks the mainline, annotating the existing game-record children and
  # grafting each move's variations as siblings of the mainline child.
  defp graft_line(node, _position, []), do: {:ok, node}

  defp graft_line(node, position, [move | rest]) do
    with {:ok, m} <- san(position, move.san),
         {:ok, next_position} <- Position.apply_move(position, m),
         [main | siblings] <- node.children,
         true <- main.transition == {:move, m},
         {:ok, main} <- graft_line(main, next_position, rest),
         {:ok, variation_nodes} <- build_variations(move.variations, position),
         {:ok, main} <- apply_annotations(main, move) do
      {:ok, %{node | children: [main | siblings ++ variation_nodes]}}
    else
      [] -> invalid("PGN mainline is longer than the canonical game")
      false -> invalid("PGN mainline diverges from the canonical game")
      {:error, _} = error -> error
    end
  end

  # Variation heads are alternatives at the given (parent) position.
  defp build_variations(variations, position) do
    Enum.reduce_while(variations, {:ok, []}, fn line, {:ok, acc} ->
      case build_children(line, position) do
        {:ok, nodes} -> {:cont, {:ok, acc ++ nodes}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp build_children([], _position), do: {:ok, []}

  defp build_children([move | rest], position) do
    with {:ok, m} <- san(position, move.san),
         {:ok, next_position} <- Position.apply_move(position, m),
         {:ok, continuation} <- build_children(rest, next_position),
         {:ok, alternatives} <- build_variations(move.variations, position),
         {:ok, node} <-
           Node.new(PositionStore.append(next_position), {:move, m})
           |> apply_annotations(move) do
      {:ok, [%{node | children: continuation} | alternatives]}
    else
      {:error, _} = error -> error
      _ -> invalid("Illegal move in variation #{move.san}")
    end
  end

  defp apply_annotations(node, move) do
    if Node.valid_nags?(move.nags) do
      {:ok, %{node | comment: comment_text(move.leading ++ move.comments), nags: move.nags}}
    else
      invalid("Invalid or excessive move annotations")
    end
  end

  defp comment_text([]), do: nil
  defp comment_text(comments), do: Enum.join(comments, "\n")

  defp san(position, text) do
    case SAN.parse(position, text) do
      {:ok, move} -> {:ok, move}
      {:error, :invalid_san} -> invalid("Could not parse move #{text}")
    end
  end

  defp check_mainline_agreement(mainline, moves) do
    if length(mainline) == length(moves),
      do: :ok,
      else: invalid("PGN mainline and canonical replay disagree")
  end

  # The PGN movetext as a move tree. A variation following a move is an
  # alternative to that move; a variation without a preceding move is invalid.
  defp parse_tree(pgn) do
    text = String.replace(pgn, ~r/^\s*\[[^\]]+\]\s*$/m, " ")
    tokens = @tokens |> Regex.scan(text) |> Enum.map(&hd/1)

    case parse_sequence(tokens, %{moves: [], pending: []}) do
      {:ok, line, []} -> {:ok, line}
      {:ok, _line, _rest} -> invalid("Unexpected variation ending")
      {:error, _} = error -> error
    end
  end

  # acc: %{moves: [tree_move] (reversed), pending: [String.t()]}
  defp parse_sequence(tokens, acc) do
    case tokens do
      [] ->
        {:ok, finish(acc), []}

      [")" | _] = rest ->
        {:ok, finish(acc), rest}

      ["(" | rest] ->
        case acc.moves do
          [] ->
            invalid("Variation without a preceding move")

          _ ->
            with {:ok, variation, rest2} <- parse_sequence(rest, %{moves: [], pending: []}),
                 [")" | rest3] <- rest2 do
              parse_sequence(rest3, attach_variation(acc, variation))
            else
              _ -> invalid("Unclosed variation")
            end
        end

      [token | rest] ->
        case annotation_token(token, acc) do
          {:ok, acc} -> parse_sequence(rest, acc)
          {:error, _} = error -> error
        end
    end
  end

  defp finish(%{moves: moves}), do: Enum.reverse(moves)

  defp attach_variation(acc, []), do: acc

  defp attach_variation(acc, variation) do
    [last | before_last] = acc.moves
    last = %{last | variations: last.variations ++ [variation]}
    %{acc | moves: [last | before_last]}
  end

  defp annotation_token("{" <> comment, acc) do
    if String.ends_with?(comment, "}"),
      do: comment(String.slice(comment, 0..-2//1), acc),
      else: invalid("Unclosed comment")
  end

  defp annotation_token(";" <> comment, acc), do: comment(comment, acc)

  defp annotation_token("$" <> number, acc) do
    case Integer.parse(number) do
      {nag, ""} -> nag(nag, acc)
      _ -> invalid("Invalid numeric annotation")
    end
  end

  defp annotation_token(text, acc) do
    text = String.replace(text, ~r/^\d+\.(?:\.\.)?/, "")

    cond do
      text in ["", "1-0", "0-1", "1/2-1/2", "*"] ->
        {:ok, acc}

      Map.has_key?(@symbols, text) ->
        nag(@symbols[text], acc)

      true ->
        acc = push_move(acc, text)

        case Regex.run(~r/[!?]+$/, text) do
          nil -> {:ok, acc}
          [suffix] -> nag(@symbols[suffix], acc)
        end
    end
  end

  defp push_move(acc, text) do
    san = String.replace(text, ~r/[!?]+$/, "")

    move = %{san: san, leading: Enum.reverse(acc.pending), comments: [], nags: [], variations: []}
    %{acc | moves: [move | acc.moves], pending: []}
  end

  defp comment(text, acc) do
    text = text |> strip_machine_commands() |> String.trim()

    if text == "" do
      {:ok, acc}
    else
      case acc.moves do
        [] ->
          {:ok, %{acc | pending: [text | acc.pending]}}

        [last | before_last] ->
          {:ok, %{acc | moves: [%{last | comments: last.comments ++ [text]} | before_last]}}
      end
    end
  end

  defp strip_machine_commands(text) do
    String.replace(text, ~r/\[%[^\]]*\]/, "")
  end

  defp nag(_nag, %{moves: []}), do: invalid("Annotation without a preceding move")

  defp nag(nag, acc) do
    [last | before_last] = acc.moves
    {:ok, %{acc | moves: [%{last | nags: Enum.uniq(last.nags ++ [nag])} | before_last]}}
  end

  defp invalid(message), do: {:error, {:invalid_pgn, message}}
end
