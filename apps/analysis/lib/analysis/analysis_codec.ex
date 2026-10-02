defmodule Analysis.AnalysisCodec do
  @moduledoc """
  Encodes an analysis aggregate into a versioned durable binary record.

  Analysis identity, revision, ownership and other queryable persistence
  concerns belong in PostgreSQL columns. This codec owns only the mutable
  analysis aggregate itself.

  Format `OCLANL01` consists of:

    * 8 bytes format identifier
    * one deterministic Erlang external-term payload containing only
      explicitly encoded analysis data

  Nodes and transitions are converted to plain tuples before encoding so
  persisted records do not depend on the in-memory struct representation.
  """

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.GameStart
  alias Analysis.Node
  alias Chess.Move

  @format_id <<"OCLANL01">>
  @format_size byte_size(@format_id)

  @max_bigint 9_223_372_036_854_775_807

  @type encoded :: binary()

  @spec format_id() :: binary()
  def format_id do
    @format_id
  end

  @spec encode(term()) ::
          {:ok, encoded()}
          | {:error, term()}
  def encode(%AnalysisModel{
        id: analysis_id,
        root: %Node{} = root,
        start: %GameStart{} = start,
        source_game_record_id: source_game_record_id,
        metadata: metadata
      }) do
    fullmove_number =
      GameStart.fullmove_number(start)

    with :ok <-
           validate_analysis_id(analysis_id),
         :ok <-
           validate_fullmove_number(fullmove_number),
         :ok <-
           validate_source_game_record_id(source_game_record_id),
         :ok <-
           validate_metadata(metadata),
         {:ok, encoded_root} <-
           encode_node(root) do
      payload = {
        analysis_id,
        fullmove_number,
        source_game_record_id,
        metadata,
        encoded_root
      }

      encoded_payload =
        :erlang.term_to_binary(
          payload,
          [:deterministic]
        )

      {:ok,
       <<
         @format_id::binary,
         encoded_payload::binary
       >>}
    end
  end

  def encode(_analysis) do
    {:error, :invalid_analysis}
  end

  @spec decode(term()) ::
          {:ok, AnalysisModel.t()}
          | {:error, term()}
  def decode(encoded) when is_binary(encoded) do
    case encoded do
      <<
        format_id::binary-size(@format_size),
        payload::binary
      >> ->
        with :ok <-
               validate_format_id(format_id),
             {:ok, decoded_payload} <-
               decode_payload(payload) do
          decode_analysis(decoded_payload)
        end

      _other ->
        {:error, :invalid_record}
    end
  end

  def decode(_encoded) do
    {:error, :invalid_record}
  end

  defp encode_node(%Node{
         position_id: position_id,
         transition: transition,
         comment: comment,
         nags: nags,
         children: children
       })
       when is_list(children) do
    with :ok <-
           validate_position_id(position_id),
         {:ok, encoded_transition} <-
           encode_transition(transition),
         :ok <-
           validate_comment(comment),
         :ok <-
           validate_nags(nags),
         {:ok, encoded_children} <-
           encode_nodes(children) do
      {:ok,
       {
         position_id,
         encoded_transition,
         comment,
         nags,
         encoded_children
       }}
    end
  end

  defp encode_node(_node) do
    {:error, :invalid_node}
  end

  defp encode_nodes([]) do
    {:ok, []}
  end

  defp encode_nodes([%Node{} = node | remaining_nodes]) do
    with {:ok, encoded_node} <-
           encode_node(node),
         {:ok, encoded_remaining_nodes} <-
           encode_nodes(remaining_nodes) do
      {:ok,
       [
         encoded_node
         | encoded_remaining_nodes
       ]}
    end
  end

  defp encode_nodes(_nodes) do
    {:error, :invalid_node}
  end

  defp encode_transition(nil) do
    {:ok, 0}
  end

  defp encode_transition(:edit) do
    {:ok, 1}
  end

  defp encode_transition({:move, %Move{from: from, to: to, promotion: promotion}}) do
    with :ok <-
           validate_square(from),
         :ok <-
           validate_square(to),
         {:ok, promotion_code} <-
           promotion_code(promotion) do
      {:ok,
       {
         2,
         from,
         to,
         promotion_code
       }}
    end
  end

  defp encode_transition(_transition) do
    {:error, :invalid_transition}
  end

  defp decode_payload(payload) do
    {:ok,
     :erlang.binary_to_term(
       payload,
       [:safe]
     )}
  rescue
    ArgumentError ->
      {:error, :invalid_record}
  end

  defp decode_analysis(
         {analysis_id, fullmove_number, source_game_record_id, metadata, encoded_root}
       ) do
    with :ok <-
           validate_analysis_id(analysis_id),
         :ok <-
           validate_fullmove_number(fullmove_number),
         :ok <-
           validate_source_game_record_id(source_game_record_id),
         :ok <-
           validate_metadata(metadata),
         {:ok, root} <-
           decode_node(encoded_root) do
      {:ok,
       %AnalysisModel{
         id: analysis_id,
         root: root,
         start: GameStart.new(fullmove_number),
         source_game_record_id: source_game_record_id,
         metadata: metadata
       }}
    end
  end

  defp decode_analysis(_payload) do
    {:error, :invalid_record}
  end

  defp decode_node({position_id, encoded_transition, comment, nags, encoded_children}) do
    with :ok <-
           validate_position_id(position_id),
         {:ok, transition} <-
           decode_transition(encoded_transition),
         :ok <-
           validate_comment(comment),
         :ok <-
           validate_nags(nags),
         {:ok, children} <-
           decode_nodes(encoded_children) do
      {:ok,
       %Node{
         position_id: position_id,
         transition: transition,
         comment: comment,
         nags: nags,
         children: children
       }}
    end
  end

  defp decode_node(_node) do
    {:error, :invalid_node}
  end

  defp decode_nodes([]) do
    {:ok, []}
  end

  defp decode_nodes([encoded_node | remaining_nodes]) do
    with {:ok, node} <-
           decode_node(encoded_node),
         {:ok, decoded_remaining_nodes} <-
           decode_nodes(remaining_nodes) do
      {:ok,
       [
         node
         | decoded_remaining_nodes
       ]}
    end
  end

  defp decode_nodes(_nodes) do
    {:error, :invalid_node}
  end

  defp decode_transition(0) do
    {:ok, nil}
  end

  defp decode_transition(1) do
    {:ok, :edit}
  end

  defp decode_transition({2, from, to, promotion_code}) do
    with :ok <-
           validate_square(from),
         :ok <-
           validate_square(to),
         {:ok, promotion} <-
           promotion_from_code(promotion_code) do
      {:ok,
       {:move,
        Move.new(
          from,
          to,
          promotion
        )}}
    end
  end

  defp decode_transition(_transition) do
    {:error, :invalid_transition}
  end

  defp validate_format_id(@format_id) do
    :ok
  end

  defp validate_format_id(_format_id) do
    {:error, :invalid_format}
  end

  defp validate_analysis_id(analysis_id)
       when is_binary(analysis_id) and byte_size(analysis_id) > 0 do
    :ok
  end

  defp validate_analysis_id(_analysis_id) do
    {:error, :invalid_analysis_id}
  end

  defp validate_fullmove_number(fullmove_number)
       when is_integer(fullmove_number) and fullmove_number > 0 and fullmove_number <= @max_bigint do
    :ok
  end

  defp validate_fullmove_number(_fullmove_number) do
    {:error, :invalid_fullmove_number}
  end

  defp validate_source_game_record_id(nil) do
    :ok
  end

  defp validate_source_game_record_id(source_game_record_id)
       when is_binary(source_game_record_id) and byte_size(source_game_record_id) > 0 do
    :ok
  end

  defp validate_source_game_record_id(_source_game_record_id) do
    {:error, :invalid_source_game_record_id}
  end

  defp validate_metadata(metadata) when is_map(metadata) do
    :ok
  end

  defp validate_metadata(_metadata) do
    {:error, :invalid_metadata}
  end

  defp validate_position_id(position_id)
       when is_integer(position_id) and position_id > 0 and position_id <= @max_bigint do
    :ok
  end

  defp validate_position_id(_position_id) do
    {:error, :invalid_position_id}
  end

  defp validate_comment(nil) do
    :ok
  end

  defp validate_comment(comment) when is_binary(comment) do
    :ok
  end

  defp validate_comment(_comment) do
    {:error, :invalid_comment}
  end

  defp validate_nags(nags) do
    if Node.valid_nags?(nags) do
      :ok
    else
      {:error, :invalid_nags}
    end
  end

  defp validate_square(square) when is_integer(square) and square in 0..63 do
    :ok
  end

  defp validate_square(_square) do
    {:error, :invalid_move}
  end

  defp promotion_code(nil), do: {:ok, 0}
  defp promotion_code(:queen), do: {:ok, 1}
  defp promotion_code(:rook), do: {:ok, 2}
  defp promotion_code(:bishop), do: {:ok, 3}
  defp promotion_code(:knight), do: {:ok, 4}

  defp promotion_code(_promotion) do
    {:error, :invalid_promotion}
  end

  defp promotion_from_code(0), do: {:ok, nil}
  defp promotion_from_code(1), do: {:ok, :queen}
  defp promotion_from_code(2), do: {:ok, :rook}
  defp promotion_from_code(3), do: {:ok, :bishop}
  defp promotion_from_code(4), do: {:ok, :knight}

  defp promotion_from_code(_promotion_code) do
    {:error, :invalid_promotion}
  end
end
