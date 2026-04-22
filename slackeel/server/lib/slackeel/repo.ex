defmodule Slackeel.Repo do
  use Ecto.Repo,
    otp_app: :slackeel,
    adapter: Ecto.Adapters.Postgres
end
