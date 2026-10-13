ExUnit.start()

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
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
