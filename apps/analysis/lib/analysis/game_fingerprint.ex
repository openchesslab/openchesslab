defmodule Analysis.GameFingerprint do
  @moduledoc """
  Produces fingerprints for canonical game content.

  A fingerprint is an index key only. Game identity must still be
  established by comparing the complete canonical game content.
  """

  alias Analysis.GameContent
  alias Analysis.GameFingerprintCodec

  @type t :: <<_::256>>

  @spec for_content(GameContent.t()) ::
          {:ok, t()}
          | {:error, term()}
  def for_content(%GameContent{} = content) do
    with {:ok, encoded} <-
           GameFingerprintCodec.encode(content) do
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
