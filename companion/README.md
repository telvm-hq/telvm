# Companion

This is the Phoenix application for **telvm**. For architecture, Docker-first workflow, and tests, read the
[repository README](../README.md).

Recommended: from the repo root run `docker compose up --build`. Run tests in-container with
`docker compose --profile test run --rm companion_test` (see repo [README](../README.md#test-strategy)).

To start your Phoenix server locally:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

Now you can visit [`localhost:4000`](http://localhost:4000) from your browser.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
