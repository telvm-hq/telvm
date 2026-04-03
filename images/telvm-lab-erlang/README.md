# telvm-lab-erlang

**Erlang + Cowboy** — `rebar3 release`, HTTP handler returns JSON on **port 3333**.

```bash
docker build -t telvm-lab-erlang:local .
docker run --rm -p 3333:3333 telvm-lab-erlang:local
```
