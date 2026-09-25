defmodule Analysis.AnalysisStoreOwnerTest do
  use ExUnit.Case, async: false

  alias Analysis.AnalysisStoreOwner

  setup do
    previous =
      Application.get_env(
        :analysis,
        AnalysisStoreOwner,
        :not_configured
      )

    on_exit(fn ->
      case previous do
        :not_configured ->
          Application.delete_env(
            :analysis,
            AnalysisStoreOwner
          )

        value ->
          Application.put_env(
            :analysis,
            AnalysisStoreOwner,
            value
          )
      end
    end)

    :ok
  end

  test "owns the analysis store by default" do
    Application.delete_env(
      :analysis,
      AnalysisStoreOwner
    )

    assert AnalysisStoreOwner.owner?()
  end

  test "can be configured as a non-owner" do
    Application.put_env(
      :analysis,
      AnalysisStoreOwner,
      owner: false
    )

    refute AnalysisStoreOwner.owner?()
  end
end
