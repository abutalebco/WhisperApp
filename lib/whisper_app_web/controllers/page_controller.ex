defmodule WhisperAppWeb.PageController do
  use WhisperAppWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
