# telvm-lab-c

**C + libmicrohttpd** (small, portable HTTP stack; not Kore — see top-level [`images/README.md`](../README.md)).

```bash
docker build -t telvm-lab-c:local .
docker run --rm -p 3333:3333 telvm-lab-c:local
```
