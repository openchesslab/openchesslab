defmodule Web.GoogleOAuthTest do
  use ExUnit.Case, async: true

  @config %{
    client_id: "test-client",
    client_secret: "private-secret",
    redirect_uri: "https://example.org/auth/google/callback"
  }

  test "direct HTTPS exchange validates claims and returns only the subject" do
    request = fn :post, {url, _, _, body}, options, response_options ->
      assert url == ~c"https://oauth2.googleapis.com/token"

      assert URI.decode_query(body) == %{
               "grant_type" => "authorization_code",
               "client_id" => @config.client_id,
               "client_secret" => @config.client_secret,
               "redirect_uri" => @config.redirect_uri,
               "code" => "4/code",
               "code_verifier" => "verifier"
             }

      assert options[:ssl][:verify] == :verify_peer
      assert options[:autoredirect] == false
      assert options[:autoretry] == 0
      assert response_options[:max_body_size] == 65_536
      json(%{"id_token" => token(claims()), "access_token" => "discard-me"})
    end

    assert {:ok, %{provider: "google", subject: "opaque-subject"}} =
             Web.GoogleOAuth.verify_code("4/code", "verifier", "nonce", @config, request)
  end

  test "wrong issuer, audience, authorized party, nonce, expiry and malformed tokens fail closed" do
    for change <- [
          %{"iss" => "https://attacker.example"},
          %{"aud" => "other-client"},
          %{"azp" => "other-client"},
          %{"nonce" => "other-nonce"},
          %{"exp" => System.system_time(:second)},
          %{"exp" => "forever"},
          %{"iat" => System.system_time(:second) + 3600},
          %{"sub" => ""},
          %{"sub" => 42}
        ] do
      response = json(%{"id_token" => token(Map.merge(claims(), change))})
      assert {:error, _} = verify(response)
    end

    for token <- [nil, "", "a.b.c", %{}, token(Map.delete(claims(), "nonce"))] do
      assert {:error, _} = verify(json(%{"id_token" => token}))
    end
  end

  test "transport failures, redirects, wrong MIME and oversized responses fail closed" do
    for response <- [
          {:error, :timeout},
          {:ok, {{~c"HTTP/1.1", 302, ~c"Found"}, [], ""}},
          {:ok, {{~c"HTTP/1.1", 200, ~c"OK"}, [], "{}"}},
          json(%{"padding" => String.duplicate("a", 65_537)})
        ] do
      assert {:error, _} = verify(response)
    end

    assert {:error, :transport_unavailable} =
             Web.GoogleOAuth.verify_code("code", "v", "nonce", @config, fn _, _, _, _ ->
               exit(:timeout)
             end)
  end

  defp verify(response),
    do: Web.GoogleOAuth.verify_code("code", "v", "nonce", @config, fn _, _, _, _ -> response end)

  defp claims,
    do: %{
      "iss" => "https://accounts.google.com",
      "aud" => @config.client_id,
      "sub" => "opaque-subject",
      "nonce" => "nonce",
      "iat" => System.system_time(:second),
      "exp" => System.system_time(:second) + 3600,
      "email" => "discard@example.org",
      "name" => "Discard"
    }

  defp token(claims),
    do: encode(%{"alg" => "RS256"}) <> "." <> encode(claims) <> ".provider-signature"

  defp encode(value), do: value |> Jason.encode!() |> Base.url_encode64(padding: false)

  defp json(data),
    do:
      {:ok,
       {{~c"HTTP/1.1", 200, ~c"OK"}, [{~c"content-type", ~c"application/json"}],
        Jason.encode!(data)}}
end
