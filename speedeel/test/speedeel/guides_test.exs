defmodule Speedeel.GuidesTest do
  use ExUnit.Case, async: true

  test "render_html wraps markdown" do
    html = Speedeel.Guides.render_html("# Hi\n")
    assert html =~ "<h1>"
    assert html =~ "Hi"
  end
end
