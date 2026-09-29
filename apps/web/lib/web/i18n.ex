defmodule Web.I18n do
  @moduledoc """
  Server-side UI messages for the LiveView application.

  The English and Dutch catalogs are carried over from the previous
  browser UI. Locale negotiation remains owned by `Localize`; this
  module only selects a message and interpolates its placeholders.
  """

  @en_path Path.expand("../../priv/i18n/en.json", __DIR__)
  @nl_path Path.expand("../../priv/i18n/nl.json", __DIR__)
  @external_resource @en_path
  @external_resource @nl_path

  @catalogs %{
    "en" => @en_path |> File.read!() |> Jason.decode!(),
    "nl" => @nl_path |> File.read!() |> Jason.decode!()
  }

  @spec locale() :: String.t()
  def locale do
    case Localize.get_locale().cldr_locale_id do
      :nl -> "nl"
      _ -> "en"
    end
  end

  @spec locale_from_session(map()) :: String.t()
  def locale_from_session(session) do
    locale =
      case session[Localize.Plug.PutLocale.session_key()] do
        %Localize.LanguageTag{cldr_locale_id: :nl} -> "nl"
        "nl" -> "nl"
        _ -> "en"
      end

    {:ok, _tag} = Localize.put_locale(locale)
    locale
  end

  @spec t(String.t(), map() | String.t() | atom()) :: String.t()
  def t(key, locale) when is_binary(key) and (is_binary(locale) or is_atom(locale)) do
    t(key, locale, %{})
  end

  def t(key, params) when is_binary(key) and is_map(params) do
    t(key, locale(), params)
  end

  def t(key) when is_binary(key), do: t(key, locale(), %{})

  @spec t(String.t(), String.t() | atom(), map()) :: String.t()
  def t(key, locale, params) when is_binary(key) and is_map(params) do
    language = normalize_locale(locale)
    template = get_in(@catalogs, [language, key]) || get_in(@catalogs, ["en", key]) || key

    Regex.replace(~r/\{([[:alnum:]_]+)\}/, template, fn _match, name ->
      case fetch_param(params, name) do
        {:ok, value} -> to_string(value)
        :error -> "{" <> name <> "}"
      end
    end)
  end

  @spec plural(String.t(), non_neg_integer(), map()) :: String.t()
  def plural(key, count, params \\ %{}) when is_binary(key) and is_integer(count) do
    form = if count == 1, do: "_one", else: "_other"
    t(key <> form, locale(), Map.put(params, "count", count))
  end

  @spec format_time(integer()) :: String.t()
  def format_time(milliseconds) when is_integer(milliseconds) do
    milliseconds
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M")
  end

  defp normalize_locale(%Localize.LanguageTag{cldr_locale_id: :nl}), do: "nl"
  defp normalize_locale(:nl), do: "nl"
  defp normalize_locale("nl"), do: "nl"
  defp normalize_locale(_locale), do: "en"

  defp fetch_param(params, name) do
    case Map.fetch(params, name) do
      {:ok, value} -> {:ok, value}
      :error -> Map.fetch(params, String.to_atom(name))
    end
  end
end
