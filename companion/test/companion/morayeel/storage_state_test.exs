defmodule Companion.Morayeel.StorageStateTest do
  use ExUnit.Case, async: true

  alias Companion.Morayeel.StorageState

  test "summarize/1 extracts cookie names and domains" do
    json = %{
      "cookies" => [
        %{"name" => "morayeel_lab_cookie", "domain" => "morayeel_lab", "value" => "x"}
      ],
      "origins" => []
    }

    assert %{cookie_count: 1, cookie_names: ["morayeel_lab_cookie"], origins: ["morayeel_lab"]} =
             StorageState.summarize(json)
  end

  test "summarize_from_path/1 handles missing file" do
    m = StorageState.summarize_from_path("/nonexistent/morayeel/storageState.json")
    assert m.cookie_count == 0
    assert m.cookie_names == []
    assert m.origins == []
    assert m.note == "missing_file"
  end
end
