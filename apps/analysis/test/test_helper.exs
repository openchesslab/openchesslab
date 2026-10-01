ExUnit.start()

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    game_records,
    game_occurrences,
    games,
    position_features,
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
