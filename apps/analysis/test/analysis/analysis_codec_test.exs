defmodule Analysis.AnalysisCodecTest do
  use ExUnit.Case, async: true

  alias Analysis.Analysis, as: AnalysisModel
  alias Analysis.AnalysisCodec
  alias Analysis.GameStart
  alias Analysis.Node
  alias Analysis.Transition
  alias Chess.Move

  test "exposes the durable analysis format" do
    assert AnalysisCodec.format_id() ==
             <<"OCLANL01">>
  end

  test "round trips a complete analysis aggregate deterministically" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42,
        "record-1",
        GameStart.new(37),
        %{
          "tags" => [
            "opening",
            "study"
          ],
          event: "Candidates"
        }
      )

    analysis =
      AnalysisModel.add_child(
        analysis,
        [],
        Transition.move(
          Move.new(
            12,
            28
          )
        ),
        43
      )

    {:ok, analysis} =
      AnalysisModel.set_comment(
        analysis,
        [0],
        "Main line"
      )

    {:ok, analysis} =
      AnalysisModel.set_nags(
        analysis,
        [0],
        [1, 5]
      )

    analysis =
      AnalysisModel.add_child(
        analysis,
        [0],
        Transition.edit(),
        44
      )

    assert {:ok, first} =
             AnalysisCodec.encode(analysis)

    assert {:ok, second} =
             AnalysisCodec.encode(analysis)

    assert first == second

    assert <<
             "OCLANL01",
             _payload::binary
           >> = first

    assert AnalysisCodec.decode(first) ==
             {:ok, analysis}
  end

  test "round trips all supported promotion values" do
    promotions = [
      nil,
      :queen,
      :rook,
      :bishop,
      :knight
    ]

    analysis =
      Enum.reduce(
        promotions,
        AnalysisModel.new(
          "analysis-1",
          42
        ),
        fn promotion, analysis ->
          AnalysisModel.add_child(
            analysis,
            [],
            Transition.move(
              Move.new(
                48,
                56,
                promotion
              )
            ),
            43
          )
        end
      )

    assert {:ok, encoded} =
             AnalysisCodec.encode(analysis)

    assert AnalysisCodec.decode(encoded) ==
             {:ok, analysis}
  end

  test "preserves nil source record and empty metadata" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, encoded} =
             AnalysisCodec.encode(analysis)

    assert AnalysisCodec.decode(encoded) ==
             {:ok, analysis}
  end

  test "rejects an invalid analysis id" do
    analysis =
      %AnalysisModel{
        id: "",
        root: Node.new(42),
        start: GameStart.standard(),
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_analysis_id}
  end

  test "rejects an invalid source game record id" do
    analysis =
      %AnalysisModel{
        id: "analysis-1",
        root: Node.new(42),
        start: GameStart.standard(),
        source_game_record_id: "",
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_source_game_record_id}
  end

  test "rejects an invalid position id" do
    analysis =
      %AnalysisModel{
        id: "analysis-1",
        root: %Node{
          position_id: 0
        },
        start: GameStart.standard(),
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_position_id}
  end

  test "rejects invalid node nags" do
    analysis =
      %AnalysisModel{
        id: "analysis-1",
        root: %Node{
          position_id: 42,
          nags: [256]
        },
        start: GameStart.standard(),
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_nags}
  end

  test "rejects an invalid move square" do
    analysis =
      %AnalysisModel{
        id: "analysis-1",
        root: %Node{
          position_id: 42,
          children: [
            %Node{
              position_id: 43,
              transition:
                Transition.move(%Move{
                  from: 64,
                  to: 28,
                  promotion: nil
                })
            }
          ]
        },
        start: GameStart.standard(),
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_move}
  end

  test "rejects an invalid promotion" do
    analysis =
      %AnalysisModel{
        id: "analysis-1",
        root: %Node{
          position_id: 42,
          children: [
            %Node{
              position_id: 43,
              transition:
                Transition.move(%Move{
                  from: 48,
                  to: 56,
                  promotion: :king
                })
            }
          ]
        },
        start: GameStart.standard(),
        metadata: %{}
      }

    assert AnalysisCodec.encode(analysis) ==
             {:error, :invalid_promotion}
  end

  test "rejects an unknown record format" do
    analysis =
      AnalysisModel.new(
        "analysis-1",
        42
      )

    assert {:ok, encoded} =
             AnalysisCodec.encode(analysis)

    <<
      _format_id::binary-size(8),
      payload::binary
    >> = encoded

    assert AnalysisCodec.decode(<<
             "OCLANL02",
             payload::binary
           >>) ==
             {:error, :invalid_format}
  end

  test "rejects a malformed record payload" do
    assert AnalysisCodec.decode(<<
             "OCLANL01",
             1,
             2,
             3
           >>) ==
             {:error, :invalid_record}
  end

  test "rejects a non-analysis value" do
    assert AnalysisCodec.encode(:not_an_analysis) ==
             {:error, :invalid_analysis}
  end
end
