defmodule Web.PageLive do
  use Web, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, title: "OpenChessLab")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <section class="hero">
      <h1 class="hero-title">OpenChessLab</h1>
      
      <p class="hero-subtitle">
        {gettext("A collaborative chess analysis platform built with Phoenix LiveView.")}
      </p>
    </section>
    """
  end
end
