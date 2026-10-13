ExUnit.start()

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    lichess_oauth_attempts,
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
    position_features,
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
