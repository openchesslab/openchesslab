defmodule Analysis.GameFingerprint do
  @moduledoc """
  Produces fingerprints for canonical game content.

  A fingerprint is an index key only. Game identity must still be
  established by comparing the complete canonical game content.

  The format ID identifies the durable fingerprint representation and
  must change whenever its hashing semantics change incompatibly.
  """

  alias Analysis.GameContent
  alias Analysis.GameContentCodec

  @format_id <<"game-content-sha256-v1">>
  @fingerprint_size 32

  @type t :: <<_::256>>

  @spec format_id() :: binary()
  def format_id do
    @format_id
  end

  @spec fingerprint_size() :: pos_integer()
  def fingerprint_size do
    @fingerprint_size
  end

  @spec for_content(GameContent.t()) ::
          {:ok, t()}
          | {:error, term()}
  def for_content(%GameContent{} = content) do
    with {:ok, encoded} <-
           GameContentCodec.encode(content) do
      {:ok,
       :crypto.hash(
         :sha256,
         encoded
       )}
    end
  end

  def for_content(_content) do
    {:error, :invalid_game_content}
  end
end
