import http from "node:http";

const server = http.createServer((req, res) => {
  res.setHeader("Set-Cookie", "morayeel_lab_cookie=synthetic; Path=/; HttpOnly");
  res.setHeader("Content-Type", "text/html; charset=utf-8");
  res.end("<!doctype html><html><head><title>Morayeel lab</title></head><body><p>Morayeel lab OK</p></body></html>");
});

server.listen(8080, "0.0.0.0", () => {
  process.stderr.write("morayeel_lab listening on :8080\n");
});
