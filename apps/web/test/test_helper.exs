ExUnit.start()

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
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
