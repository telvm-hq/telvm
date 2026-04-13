/**
 * Headless Chromium lab run: visit TARGET_URL, persist storageState + HAR + run.json.
 * Intended for in-cluster use with HTTP(S)_PROXY pointing at companion egress (port 4003).
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";

const outDir = process.env.OUT_DIR || "/artifacts/run";
const targetUrl = process.env.TARGET_URL || "http://morayeel_lab:8080/";

fs.mkdirSync(outDir, { recursive: true });

const logPath = path.join(outDir, "runner.log");
function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  process.stderr.write(line);
  fs.appendFileSync(logPath, line, { flag: "a" });
}

function writeRunJson(payload) {
  fs.writeFileSync(
    path.join(outDir, "run.json"),
    JSON.stringify(
      {
        ...payload,
        target_url: targetUrl,
        finished_at: new Date().toISOString(),
      },
      null,
      2
    )
  );
}

const proxyServer = process.env.HTTP_PROXY || process.env.HTTPS_PROXY || "";

const contextOpts = {
  recordHar: { path: path.join(outDir, "network.har"), mode: "full" },
};

if (proxyServer) {
  contextOpts.proxy = { server: proxyServer };
}

let browser;
let context;
let page;

try {
  log(`TARGET_URL=${targetUrl}`);
  log(`proxy=${proxyServer || "(none)"}`);

  browser = await chromium.launch({ headless: true });
  context = await browser.newContext(contextOpts);
  page = await context.newPage();

  await page.goto(targetUrl, { waitUntil: "load", timeout: 60_000 });
  await page.waitForLoadState("networkidle", { timeout: 8_000 }).catch(() => {});
  log(`navigation ok title=${await page.title()}`);

  await context.storageState({ path: path.join(outDir, "storageState.json") });
  await context.close();
  await browser.close();

  writeRunJson({ status: "passed", exit_code: 0 });
  process.exit(0);
} catch (err) {
  log(`error: ${err && err.stack ? err.stack : String(err)}`);
  try {
    if (page) {
      await page.screenshot({ path: path.join(outDir, "last.png") }).catch(() => {});
    }
  } catch (_) {}
  try {
    if (context) await context.close().catch(() => {});
  } catch (_) {}
  try {
    if (browser) await browser.close().catch(() => {});
  } catch (_) {}

  writeRunJson({
    status: "failed",
    exit_code: 1,
    error: String(err && err.message ? err.message : err),
  });
  process.exit(1);
}
