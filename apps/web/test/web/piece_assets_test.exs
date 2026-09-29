defmodule Web.PieceAssetsTest do
  use Web.ConnCase, async: true

  test "both configured piece sets are served as static SVGs", %{conn: conn} do
    for path <- [
          "/images/pieces/merida/white_king.svg",
          "/images/pieces/cburnett/black_knight.svg"
        ] do
      response = conn |> get(path) |> response(200)
      assert response =~ "<svg xmlns=\"http://www.w3.org/2000/svg\""
    end
  end
end
