defmodule Companion.VmLifecycle.HttpProbe do
  @moduledoc false

  @finch Companion.Finch

  def get(url) when is_binary(url) do
    t0 = System.monotonic_time(:millisecond)
    req = Finch.build(:get, url)

    case Finch.request(req, @finch, receive_timeout: 2_000) do
      {:ok, %Finch.Response{status: status}} ->
        t1 = System.monotonic_time(:millisecond)
        {:ok, %{status: status, latency_ms: t1 - t0}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
