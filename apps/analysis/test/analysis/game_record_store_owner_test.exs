defmodule Analysis.GameRecordStoreOwnerTest do
  use ExUnit.Case, async: false

  alias Analysis.GameRecordStoreOwner

  setup do
    previous =
      Application.get_env(
        :analysis,
        GameRecordStoreOwner,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            GameRecordStoreOwner
          )

        value ->
          Application.put_env(
            :analysis,
            GameRecordStoreOwner,
            value
          )
      end
    end)

    :ok
  end

  test "owns the game record store by default" do
    Application.delete_env(
      :analysis,
      GameRecordStoreOwner
    )

    assert GameRecordStoreOwner.owner?()
  end

  test "can be configured as a non-owner" do
    Application.put_env(
      :analysis,
      GameRecordStoreOwner,
      owner: false
    )

    refute GameRecordStoreOwner.owner?()
  end
end
