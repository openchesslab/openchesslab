defmodule Analysis.PositionPropertyKeyCodec do
  @moduledoc """
  Encodes chess position properties for durable PositionDB
  secondary indexes.
  """

  @behaviour PositionDB.Storage.PropertyKeyCodec

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

  @piece_types [
    :pawn,
    :knight,
    :bishop,
    :rook,
    :queen,
    :king
  ]

  @impl PositionDB.Storage.PropertyKeyCodec
  def format_id do
    @format_id
  end

  @impl PositionDB.Storage.PropertyKeyCodec
  def encode(
        :open_files,
        file
      ) do
    case Map.fetch(
           @file_ids,
           file
         ) do
      {:ok, file_id} ->
        {:ok,
         <<
           1::unsigned-8,
           file_id::unsigned-8
         >>}

      :error ->
        {:error, :invalid_open_file}
    end
  end

  def encode(
        :material,
        %{
          white: white,
          black: black
        }
      )
      when is_map(white) and
             is_map(black) do
    with {:ok, white_counts} <-
           encode_material_counts(white),
         {:ok, black_counts} <-
           encode_material_counts(black) do
      {:ok,
       <<
         2::unsigned-8,
         white_counts::binary,
         black_counts::binary
       >>}
    end
  end

  def encode(
        :material,
        _value
      ) do
    {:error, :invalid_material}
  end

  def encode(
        _property,
        _value
      ) do
    {:error, :unsupported_property}
  end

  defp encode_material_counts(material) do
    @piece_types
    |> Enum.reduce_while(
      {:ok, <<>>},
      fn piece_type, {:ok, encoded} ->
        case Map.fetch(
               material,
               piece_type
             ) do
          {:ok, count}
          when is_integer(count) and
                 count >= 0 and
                 count <= 255 ->
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
