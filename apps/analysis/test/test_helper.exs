ExUnit.start()
Logger.configure(level: :warning)

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    oauth_attempts,
    user_sessions,
    user_analyses,
    accounts,
    users,
    room_analyses,
    rooms,
    analyses,
    game_records,
    game_occurrences,
    games,
    position_feature_vectors,
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
