defmodule Analysis.GameStore do
  @moduledoc false

  alias Analysis.Game

  @type store :: GenServer.server()
  @type revision :: pos_integer()

  @callback insert(store(), Game.t()) ::
              {:ok, revision()}
              | {:error, :already_exists}

  @callback get(store(), Game.id()) ::
              {:ok, Game.t(), revision()}
              | :not_found

  @callback update(store(), Game.t(), revision()) ::
              {:ok, revision()}
              | {:error, :not_found | :conflict}

  @callback delete(store(), Game.id(), revision()) ::
              :ok
              | {:error, :not_found | :conflict}
end
