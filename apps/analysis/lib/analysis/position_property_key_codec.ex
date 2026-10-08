defmodule Analysis.PositionPropertyKeyCodec do
  @moduledoc """
  Encodes chess position properties into stable binary keys stored in
  PostgreSQL `position_features`.
  """

  @format_id <<"chess-position-property-v1">>

  @file_ids %{
    a: 0,
    b: 1,
    c: 2,
    d: 3,
    e: 4,
    f: 5,
    g: 6,
    h: 7
  }

  @color_ids %{
    white: 0,
    black: 1
  }

  @piece_types [
    :pawn,
    :knight,
    :bishop,
    :rook,
    :queen,
    :king
  ]

  @spec format_id() :: binary()
  def format_id do
    @format_id
  end

  @spec encode(atom(), term()) ::
          {:ok, binary()}
          | {:error, term()}
  def encode(:open_files, file) do
    case Map.fetch(@file_ids, file) do
      {:ok, file_id} ->
        {:ok, <<1::unsigned-8, file_id::unsigned-8>>}

      :error ->
        {:error, :invalid_open_file}
    end
  end

  def encode(:semi_open_files, {color, file}) do
    case {
      Map.fetch(@color_ids, color),
      Map.fetch(@file_ids, file)
    } do
      {{:ok, color_id}, {:ok, file_id}} ->
        {:ok,
         <<
           3::unsigned-8,
           color_id::unsigned-8,
           file_id::unsigned-8
         >>}

      _other ->
        {:error, :invalid_semi_open_file}
    end
  end

  def encode(:semi_open_files, _value) do
    {:error, :invalid_semi_open_file}
  end

  def encode(:outposts, {color, square}) when is_integer(square) and square in 0..63 do
    case Map.fetch(@color_ids, color) do
      {:ok, color_id} ->
        {:ok, <<4::unsigned-8, color_id::unsigned-8, square::unsigned-8>>}

      :error ->
        {:error, :invalid_outpost}
    end
  end

  def encode(:outposts, _value) do
    {:error, :invalid_outpost}
  end

  def encode(:side_to_move, color) do
    case Map.fetch(@color_ids, color) do
      {:ok, color_id} ->
        {:ok, <<5::unsigned-8, color_id::unsigned-8>>}

      :error ->
        {:error, :invalid_side_to_move}
    end
  end

  def encode(:in_check, color) do
    case Map.fetch(@color_ids, color) do
      {:ok, color_id} ->
        {:ok, <<6::unsigned-8, color_id::unsigned-8>>}

      :error ->
        {:error, :invalid_in_check}
    end
  end

  def encode(:castling_right, right) do
    case Map.fetch(
           %{
             white_kingside: 0,
             white_queenside: 1,
             black_kingside: 2,
             black_queenside: 3
           },
           right
         ) do
      {:ok, right_id} ->
        {:ok, <<7::unsigned-8, right_id::unsigned-8>>}

      :error ->
        {:error, :invalid_castling_right}
    end
  end

  def encode(:en_passant_target, square) when is_integer(square) and square in 0..63 do
    {:ok, <<8::unsigned-8, square::unsigned-8>>}
  end

  def encode(:en_passant_target, _square) do
    {:error, :invalid_en_passant_target}
  end

  def encode(:material, %{white: white, black: black}) when is_map(white) and is_map(black) do
    with {:ok, white_counts} <- encode_material_counts(white),
         {:ok, black_counts} <- encode_material_counts(black) do
      {:ok,
       <<
         2::unsigned-8,
         white_counts::binary,
         black_counts::binary
       >>}
    end
  end

  def encode(:material, _value) do
    {:error, :invalid_material}
  end

  def encode(_property, _value) do
    {:error, :unsupported_property}
  end

  defp encode_material_counts(material) do
    Enum.reduce_while(
      @piece_types,
      {:ok, <<>>},
      fn piece_type, {:ok, encoded} ->
        case Map.fetch(material, piece_type) do
          {:ok, count}
          when is_integer(count) and count >= 0 and count <= 255 ->
            {:cont,
             {:ok,
              <<
                encoded::binary,
                count::unsigned-8
              >>}}

          _other ->
            {:halt, {:error, :invalid_material}}
        end
      end
    )
  end
end
