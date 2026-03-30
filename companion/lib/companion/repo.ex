defmodule Companion.Repo do
  use Ecto.Repo,
    otp_app: :companion,
    adapter: Ecto.Adapters.Postgres
end
