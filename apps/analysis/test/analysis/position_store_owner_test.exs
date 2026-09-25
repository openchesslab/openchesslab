defmodule Analysis.PositionStoreOwnerTest do
  use ExUnit.Case, async: false

  alias Analysis.PositionStoreOwner

  setup do
    previous =
      Application.get_env(
        :analysis,
        PositionStoreOwner,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            PositionStoreOwner
          )

        value ->
          Application.put_env(
            :analysis,
            PositionStoreOwner,
            value
          )
      end
    end)

    :ok
  end

  test "owns the position store by default" do
    Application.delete_env(
      :analysis,
      PositionStoreOwner
    )

    assert PositionStoreOwner.owner?()
  end

  test "can be configured as a non-owner" do
    Application.put_env(
      :analysis,
      PositionStoreOwner,
      owner: false
    )

    refute PositionStoreOwner.owner?()
  end
end
