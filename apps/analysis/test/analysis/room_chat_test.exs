defmodule Analysis.RoomChatTest do
  use ExUnit.Case, async: true

  alias Analysis.RoomChat
  alias Analysis.RoomChat.Message

  test "starts empty" do
    chat = RoomChat.new()

    assert RoomChat.messages(chat) == []
  end

  test "appends messages oldest first with increasing ids" do
    chat = RoomChat.new()

    {:ok, first, chat} = RoomChat.send_message(chat, %{text: "hello", author: "Alice"})
    {:ok, second, chat} = RoomChat.send_message(chat, %{text: "hi", author: "Bob"})

    assert %Message{id: 1, author: "Alice", text: "hello"} = first
    assert %Message{id: 2, author: "Bob", text: "hi"} = second
    assert [%Message{id: 1}, %Message{id: 2}] = RoomChat.messages(chat)
  end

  test "trims text and rejects empty messages" do
    chat = RoomChat.new()

    {:ok, message, chat} = RoomChat.send_message(chat, %{text: "  spaced  ", author: "A"})
    assert message.text == "spaced"

    assert {:error, :empty} = RoomChat.send_message(chat, %{text: "   ", author: "A"})
    assert {:error, :empty} = RoomChat.send_message(chat, %{text: "", author: "A"})
    assert {:error, :empty} = RoomChat.send_message(chat, %{text: nil, author: "A"})
    assert {:error, :empty} = RoomChat.send_message(chat, %{author: "A"})
  end

  test "truncates long messages" do
    chat = RoomChat.new()
    text = String.duplicate("x", 5000)

    {:ok, message, _chat} = RoomChat.send_message(chat, %{text: text, author: "A"})

    assert String.length(message.text) == 2000
  end

  test "normalises the author name" do
    chat = RoomChat.new()

    {:ok, message, chat} = RoomChat.send_message(chat, %{text: "a", author: "  Alice  "})
    assert message.author == "Alice"

    {:ok, message, chat} = RoomChat.send_message(chat, %{text: "b", author: "   "})
    assert message.author == "Guest"

    {:ok, message, _chat} =
      RoomChat.send_message(chat, %{text: "c", author: String.duplicate("a", 100)})

    assert String.length(message.author) == 32
  end

  test "keeps view context and rejects a malformed path" do
    chat = RoomChat.new()

    {:ok, message, chat} =
      RoomChat.send_message(chat, %{
        text: "look here",
        author: "A",
        author_id: "p-1",
        analysis_id: "analysis-1",
        path: [0, 2]
      })

    assert message.analysis_id == "analysis-1"
    assert message.path == [0, 2]
    assert message.author_id == "p-1"

    {:ok, message, chat} =
      RoomChat.send_message(chat, %{text: "bad path", author: "A", path: [0, -1]})

    assert message.path == []
    assert message.analysis_id == nil

    {:ok, message, _chat} =
      RoomChat.send_message(chat, %{text: "bad analysis", author: "A", analysis_id: 42})

    assert message.analysis_id == nil
  end

  test "keeps only the newest messages" do
    chat = RoomChat.new()

    chat =
      Enum.reduce(1..210, chat, fn index, chat ->
        {:ok, _message, chat} = RoomChat.send_message(chat, %{text: "m#{index}", author: "A"})
        chat
      end)

    messages = RoomChat.messages(chat)

    assert length(messages) == 200
    assert hd(messages).text == "m11"
    assert List.last(messages).text == "m210"
  end

  test "serialises to the SPA wire shape" do
    chat = RoomChat.new()

    {:ok, message, _chat} =
      RoomChat.send_message(chat, %{
        text: "hello",
        author: "Alice",
        author_id: "p-1",
        analysis_id: "analysis-1",
        path: [0]
      })

    assert %{
             id: 1,
             author: "Alice",
             author_id: "p-1",
             text: "hello",
             at: at,
             analysis_id: "analysis-1",
             path: [0]
           } = RoomChat.to_wire(message)

    assert is_integer(at)
  end
end
