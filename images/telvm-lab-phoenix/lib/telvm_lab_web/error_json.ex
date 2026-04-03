defmodule TelvmLabWeb.ErrorJSON do
  @moduledoc false

  def render("500.json", _assigns) do
    %{errors: %{detail: "internal server error"}}
  end
end
