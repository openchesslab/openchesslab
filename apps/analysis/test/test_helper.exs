ExUnit.start()

OpenChessLab.Repo.query!(
  """
  TRUNCATE TABLE
    position_features,
    positions
  RESTART IDENTITY
  CASCADE
  """,
  []
)
