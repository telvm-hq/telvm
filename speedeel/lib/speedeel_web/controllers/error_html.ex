defmodule SpeedeelWeb.ErrorHTML do
  @moduledoc false
  use SpeedeelWeb, :html

  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
