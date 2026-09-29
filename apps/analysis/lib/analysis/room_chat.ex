defmodule Analysis.RoomChat do
  @moduledoc """
  Ephemeral per-room chat.

  A room is a temporary workspace, so its chat is part of the room's
  live state rather than persisted data: messages live in the room
  process and are gone when it stops. The author is the display name
  the client supplied when joining the room channel; when auth lands
  that becomes a user reference.

  Messages are trimmed, empty messages are rejected and long messages
  are truncated. Only the newest `@max_messages` are kept, so a room
  that runs for a long time cannot grow without bound.
  """

  @max_messages 200
  @max_text 2000
  @max_author 32
  @max_analysis_id 128
  @max_path 512

  defmodule Message do
    @moduledoc false

    @enforce_keys [:id, :author, :text, :at]
    defstruct [:id, :author, :text, :at, :author_id, analysis_id: nil, path: []]

    @type t :: %__MODULE__{
            id: pos_integer(),
            author: String.t(),
            author_id: String.t() | nil,
            text: String.t(),
            at: integer(),
            analysis_id: String.t() | nil,
            path: [non_neg_integer()]
          }
  end

  @type t :: %__MODULE__{next_id: pos_integer(), messages: [Message.t()]}

  defstruct next_id: 1, messages: []

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec messages(t()) :: [Message.t()]
  def messages(%__MODULE__{messages: messages}), do: messages

  @doc """
  Appends a message (oldest first). `attrs` is a map with `:text`,
  `:author`, optional `:author_id` and optional view context
  (`:analysis_id`, `:path`) so the UI can show where the sender was
  looking.
  """
  @spec send_message(t(), map()) :: {:ok, Message.t(), t()} | {:error, :empty}
  def send_message(%__MODULE__{} = chat, attrs) do
    case normalize_text(Map.get(attrs, :text)) do
      nil ->
        {:error, :empty}

      text ->
        message = %Message{
          id: chat.next_id,
          author: normalize_author(Map.get(attrs, :author)),
          author_id: normalize_optional_string(Map.get(attrs, :author_id), 128),
          text: text,
          at: System.system_time(:millisecond),
          analysis_id: normalize_analysis_id(Map.get(attrs, :analysis_id)),
          path: normalize_path(Map.get(attrs, :path))
        }

        updated = %{
          chat
          | next_id: chat.next_id + 1,
            messages: cap(chat.messages ++ [message])
        }

        {:ok, message, updated}
    end
  end

  @spec to_wire(Message.t()) :: map()
  def to_wire(%Message{} = message) do
    %{
      id: message.id,
      author: message.author,
      author_id: message.author_id,
      text: message.text,
      at: message.at,
      analysis_id: message.analysis_id,
      path: message.path
    }
  end

  # --- Helpers --------------------------------------------------------------

  defp normalize_text(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, @max_text)
    end
  end

  defp normalize_text(_text), do: nil

  defp normalize_author(author) when is_binary(author) do
    case String.trim(author) do
      "" -> "Guest"
      trimmed -> String.slice(trimmed, 0, @max_author)
    end
  end

  defp normalize_author(_author), do: "Guest"

  defp normalize_analysis_id(id) when is_binary(id) do
    normalize_optional_string(id, @max_analysis_id)
  end

  defp normalize_analysis_id(_id), do: nil

  defp normalize_optional_string(value, max) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, max)
    end
  end

  defp normalize_optional_string(_value, _max), do: nil

  defp normalize_path(path) when is_list(path) do
    if length(path) <= @max_path and Enum.all?(path, &(is_integer(&1) and &1 >= 0)) do
      path
    else
      []
    end
  end

  defp normalize_path(_path), do: []

  defp cap(messages) when length(messages) > @max_messages do
    Enum.take(messages, -@max_messages)
  end

  defp cap(messages), do: messages
end
