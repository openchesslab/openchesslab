defmodule Analysis.GameStoreOwner do
  @moduledoc false

  @spec owner?() :: boolean()
  def owner? do
    :analysis
    |> Application.get_env(
      __MODULE__,
      []
    )
    |> Keyword.get(
      :owner,
      true
    )
  end
end
