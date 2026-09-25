defmodule Analysis.GameStoreOwnerTest do
  use ExUnit.Case, async: false

  alias Analysis.GameStoreOwner

  setup do
    previous =
      Application.get_env(
        :analysis,
        GameStoreOwner,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            GameStoreOwner
          )

        value ->
          Application.put_env(
            :analysis,
            GameStoreOwner,
            value
          )
      end
    end)

    :ok
  end

  test "owns the game store by default" do
    Application.delete_env(
      :analysis,
      GameStoreOwner
    )

    assert GameStoreOwner.owner?()
  end

  test "can be configured as a non-owner" do
    Application.put_env(
      :analysis,
      GameStoreOwner,
      owner: false
    )

    refute GameStoreOwner.owner?()
  end
end
