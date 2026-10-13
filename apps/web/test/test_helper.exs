ExUnit.start()

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    room_analyses,
    rooms,
    analyses,
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
