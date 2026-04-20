# Slackeel

To start your Phoenix server:

* Run `mix setup` to install and setup dependencies
* Start Phoenix endpoint with `mix phx.server` or inside IEx with `iex -S mix phx.server`

You must run Mix **in this directory** (`slackeel/server/`). From the parent folder, use **`../scripts/phx-server.ps1`** or **`../scripts/phx-server.sh`**.

The dev server listens on **port 4020** (see [`config/dev.exs`](config/dev.exs)) so it does not collide with Telvm Companion (**4000**) or Speedeel (**4010**).

Now you can visit [`http://127.0.0.1:4020`](http://127.0.0.1:4020) from your browser.

## Development with Ollama in Docker

Hot reload (`code_reloader`, esbuild/Tailwind `--watch`, LiveView refresh) assumes you run **Phoenix on the host**. Start **only Ollama** in the background:

```bash
# from telvm repo root
docker compose -f slackeel/docker-compose.ollama-dev.yml up -d
```

Defaults expect the Ollama API at **`http://127.0.0.1:11434`**. See the parent [`../README.md`](../README.md) section **Local Phoenix (hot reload) + Ollama in Docker**.

Ready to run in production? Please [check our deployment guides](https://hexdocs.pm/phoenix/deployment.html).

## Learn more

* Official website: https://www.phoenixframework.org/
* Guides: https://hexdocs.pm/phoenix/overview.html
* Docs: https://hexdocs.pm/phoenix
* Forum: https://elixirforum.com/c/phoenix-forum
* Source: https://github.com/phoenixframework/phoenix
