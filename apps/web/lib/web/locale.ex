defmodule Web.Locale do
  @moduledoc """
  Defines the locales supported by the web application.

  Locale selection belongs to the presentation layer. Domain applications
  such as Analysis and Chess remain independent of language.
  """

  @default "en"
  @supported ~w(en nl)

  @spec default() :: String.t()
  def default, do: @default

  @spec supported() :: [String.t()]
  def supported, do: @supported

  @spec supported?(term()) :: boolean()
  def supported?(locale) when is_binary(locale) do
    locale in @supported
  end

  def supported?(_locale), do: false

  @spec normalize(term()) :: String.t()
  def normalize(locale) when is_binary(locale) do
    if supported?(locale), do: locale, else: @default
  end

  def normalize(_locale), do: @default
end
