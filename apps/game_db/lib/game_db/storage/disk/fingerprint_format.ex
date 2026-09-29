defmodule GameDB.Storage.Disk.FingerprintFormat do
  @moduledoc """
  Physical fingerprint representation used by GameDB disk storage.

  Both canonical game records and the fingerprint index must use
  exactly the same fingerprint size.
  """

  @size 32

  @spec size() :: pos_integer()
  def size do
    @size
  end
end
