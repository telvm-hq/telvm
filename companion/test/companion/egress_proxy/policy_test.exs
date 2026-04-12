defmodule Companion.EgressProxy.PolicyTest do
  use ExUnit.Case, async: true

  alias Companion.EgressProxy.Policy

  test "exact host match" do
    assert Policy.allowed?("api.anthropic.com", ["api.anthropic.com"])
    refute Policy.allowed?("evil.anthropic.com", ["api.anthropic.com"])
  end

  test "suffix rule with leading dot" do
    assert Policy.allowed?("api.anthropic.com", [".anthropic.com"])
    assert Policy.allowed?("anthropic.com", [".anthropic.com"])
    refute Policy.allowed?("notanthropic.com", [".anthropic.com"])
  end

  test "case normalization" do
    assert Policy.allowed?("API.Anthropic.COM", [".anthropic.com"])
  end

  test "empty or blank rules never match" do
    refute Policy.allowed?("x.com", [""])
    refute Policy.allowed?("x.com", ["  "])
  end
end
