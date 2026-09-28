defmodule Analysis.GameStoreOwner do
  @moduledoc false

  @spec owner?() :: boolean()
  def owner? do
    Application.get_env(
      :analysis,
      __MODULE__,
      []
    )
    |> Keyword.get(
      :owner,
      true
    )
  end
end
