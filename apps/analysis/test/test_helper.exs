ExUnit.start()
Logger.configure(level: :warning)

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    room_analyses,
    rooms,
    analyses,
    game_records,
    game_occurrences,
    games,
    position_feature_vectors,
    position_features,
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
