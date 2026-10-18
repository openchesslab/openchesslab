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

  @doc """
  Import options (defaults keep the historical behavior):

    * `keep_comments` (true) — human comments land on the nodes
    * `keep_variations` (true) — side variations are grafted as branches
    * `keep_metadata` (true) — the game record keeps every header; false
      stores only the identity headers (White/Black/Result/Date)
    * `keep_annotations` (false) — keep the `[%clk]` / `[%eval]` machine
      commands on the nodes as `clock` / `evaluation`
    * `:source` — provenance label (`"lichess"`, `"chesscom"`, `"pgn"`, …)
      stored as `source` in the record metadata, independent of the
      keep-metadata stripping. Provenance never participates in canonical
      dedup: it lives on the concrete record, not on the game content.
  """
  @spec import(String.t(), String.t(), String.t(), keyword()) ::
          {:ok, Analysis.Analysis.t(), pos_integer()} | {:error, term()}
  def import(analysis_id, record_id, pgn, opts \\ []) do
    keep_comments? = Keyword.get(opts, :keep_comments, true)
    keep_variations? = Keyword.get(opts, :keep_variations, true)
    keep_annotations? = Keyword.get(opts, :keep_annotations, false)
    keep_metadata? = Keyword.get(opts, :keep_metadata, true)

    with {:ok, parsed} <- PgnImporter.parse(pgn),
         {:ok, mainline} <-
           parse_tree(pgn,
             keep_comments: keep_comments?,
             keep_annotations: keep_annotations?
           ),
         :ok <- check_mainline_agreement(mainline, parsed.moves) do
      parsed =
        if keep_metadata?,
          do: parsed,
          else: %{
            parsed
            | headers: Map.take(parsed.headers, ["White", "Black", "Result", "Date"])
          }

      parsed =
        case Keyword.get(opts, :source) do
          nil ->
            parsed

          source when is_binary(source) ->
            %{parsed | headers: Map.put(parsed.headers, "Source", source)}
        end

      Repo.transaction(fn ->
        with {:ok, record} <- PgnImporter.import_parsed(record_id, parsed),
             {:ok, analysis, revision} <- Analyses.create_from_game_record(analysis_id, record.id),
             {:ok, root} <-
               graft(analysis.root, parsed.initial_position, mainline, keep_variations?),
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
  defp graft(root, initial_position, [first | rest], keep_variations?) do
    comment = comment_text(first.leading)
    mainline = [%{first | leading: []} | rest]

    with {:ok, grafted} <- graft_line(root, initial_position, mainline, keep_variations?) do
      {:ok, %{grafted | comment: comment || grafted.comment}}
    end
  end

  # Walks the mainline, annotating the existing game-record children and
  # grafting each move's variations as siblings of the mainline child.
  defp graft_line(node, _position, [], _keep_variations?), do: {:ok, node}

  defp graft_line(node, position, [move | rest], keep_variations?) do
    with {:ok, m} <- san(position, move.san),
         {:ok, next_position} <- Position.apply_move(position, m),
         [main | siblings] <- node.children,
         true <- main.transition == {:move, m},
         {:ok, main} <- graft_line(main, next_position, rest, keep_variations?),
         {:ok, variation_nodes} <- build_variations(move.variations, position, keep_variations?),
         {:ok, main} <- apply_annotations(main, move) do
      {:ok, %{node | children: [main | siblings ++ variation_nodes]}}
    else
      [] -> invalid("PGN mainline is longer than the canonical game")
      false -> invalid("PGN mainline diverges from the canonical game")
      {:error, _} = error -> error
    end
  end

  # Variation heads are alternatives at the given (parent) position; an
  # import that drops variations never builds them.
  defp build_variations(_variations, _position, false), do: {:ok, []}

  defp build_variations(variations, position, true) do
    Enum.reduce_while(variations, {:ok, []}, fn line, {:ok, acc} ->
      case build_children(line, position, true) do
        {:ok, nodes} -> {:cont, {:ok, acc ++ nodes}}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp build_children([], _position, _keep_variations?), do: {:ok, []}

  defp build_children([move | rest], position, keep_variations?) do
    with {:ok, m} <- san(position, move.san),
         {:ok, next_position} <- Position.apply_move(position, m),
         {:ok, continuation} <- build_children(rest, next_position, keep_variations?),
         {:ok, alternatives} <- build_variations(move.variations, position, keep_variations?),
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
      {:ok,
       %{
         node
         | comment: comment_text(move.leading ++ move.comments),
           nags: move.nags,
           clock: move.clock,
           evaluation: move.evaluation
       }}
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
  defp parse_tree(pgn, opts) do
    text = String.replace(pgn, ~r/^\s*\[[^\]]+\]\s*$/m, " ")
    tokens = @tokens |> Regex.scan(text) |> Enum.map(&hd/1)

    acc = %{
      moves: [],
      pending: [],
      keep_comments: Keyword.fetch!(opts, :keep_comments),
      keep_annotations: Keyword.fetch!(opts, :keep_annotations)
    }

    case parse_sequence(tokens, acc) do
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
            with {:ok, variation, rest2} <-
                   parse_sequence(rest, %{
                     moves: [],
                     pending: [],
                     keep_comments: acc.keep_comments,
                     keep_annotations: acc.keep_annotations
                   }),
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

    move = %{
      san: san,
      leading: Enum.reverse(acc.pending),
      comments: [],
      nags: [],
      variations: [],
      clock: nil,
      evaluation: nil
    }

    %{acc | moves: [move | acc.moves], pending: []}
  end

  defp comment(text, acc) do
    acc = put_annotations(acc, text)
    text = text |> strip_machine_commands() |> String.trim()

    if text == "" or not acc.keep_comments do
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

  # `[%clk]`/`[%eval]` machine commands become node annotations only when
  # the import keeps them; either way they leave the human comment text.
  defp put_annotations(acc, text) do
    if acc.keep_annotations do
      clock = command_value(text, "clk")
      evaluation = command_value(text, "eval")

      case acc.moves do
        [last | before_last] ->
          last = %{last | clock: clock || last.clock, evaluation: evaluation || last.evaluation}
          %{acc | moves: [last | before_last]}

        [] ->
          acc
      end
    else
      acc
    end
  end

  defp command_value(text, name) do
    case Regex.run(~r/\[%#{name}\s+([^\]]+)\]/, text) do
      [_, value] -> value
      _ -> nil
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
