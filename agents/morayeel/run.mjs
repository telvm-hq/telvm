/**
 * Playwright Chromium lab: visit TARGET_URL, persist storageState + HAR + run.json.
 * MORAYEEL_CAPTURE=oneshot (default): single navigation then exit.
 * MORAYEEL_CAPTURE=session: CDP + periodic storageState until signal, sentinel file, or optional max time.
 * MORAYEEL_HEADLESS=1 (default): headless Chromium. Set to 0/false/off for a visible window (local dev; Docker needs a display).
 */
import { chromium } from "playwright";
import fs from "fs";
import path from "path";

const outDir = process.env.OUT_DIR || "/artifacts/run";
/** When unset: host demos hit companion UI. Docker image sets TARGET_URL to morayeel_lab via ENV. */
const targetUrl = process.env.TARGET_URL || "http://127.0.0.1:4000/";

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
const captureModeRaw = (process.env.MORAYEEL_CAPTURE || "oneshot").toLowerCase();
const captureMode = captureModeRaw === "session" ? "session" : "oneshot";
const cdpPort = Math.max(1, Math.min(65535, parseInt(process.env.MORAYEEL_CDP_PORT || "9222", 10) || 9222));
const snapshotMs = Math.max(1000, parseInt(process.env.MORAYEEL_STORAGE_SNAPSHOT_MS || "30000", 10) || 30000);
const maxSessionMs = Math.max(0, parseInt(process.env.MORAYEEL_SESSION_MAX_MS || "0", 10) || 0);

/** Default headless; MORAYEEL_HEADLESS=0|false|no|off opens a real browser window (host use). */
function envHeadless() {
  const v = (process.env.MORAYEEL_HEADLESS ?? "1").toString().trim().toLowerCase();
  if (v === "0" || v === "false" || v === "no" || v === "off") return false;
  return true;
}
const headlessUi = envHeadless();

const contextOpts = {
  recordHar: { path: path.join(outDir, "network.har"), mode: "full" },
};

if (proxyServer) {
  contextOpts.proxy = { server: proxyServer };
}

let browser;
let context;
let page;

function targetHostname() {
  try {
    return new URL(targetUrl).hostname;
  } catch {
    return "";
  }
}

function waitForShutdown(sentinelPath) {
  return new Promise((resolve) => {
    let done = false;
    const resolveOnce = (reason) => {
      if (done) return;
      done = true;
      clearInterval(poller);
      try {
        watcher?.close();
      } catch (_) {}
      process.off("SIGINT", onSig);
      process.off("SIGTERM", onSig);
      resolve(reason);
    };

    const onSig = () => resolveOnce("signal");
    process.once("SIGINT", onSig);
    process.once("SIGTERM", onSig);

    const checkSentinel = () => {
      try {
        if (fs.existsSync(sentinelPath)) resolveOnce("sentinel");
      } catch (_) {}
    };

    const poller = setInterval(checkSentinel, 500);

    let watcher;
    try {
      watcher = fs.watch(outDir, (_evt, name) => {
        if (name === "morayeel.done" || name === null) checkSentinel();
      });
    } catch (e) {
      log(`fs.watch: ${e}`);
    }

    checkSentinel();
  });
}

try {
  log(`TARGET_URL=${targetUrl}`);
  log(`proxy=${proxyServer || "(none)"}`);
  log(`MORAYEEL_CAPTURE=${captureMode}`);
  log(`MORAYEEL_HEADLESS=${headlessUi}`);

  const launchOpts = { headless: headlessUi };
  if (captureMode === "session") {
    launchOpts.args = [
      `--remote-debugging-port=${cdpPort}`,
      "--remote-debugging-address=0.0.0.0",
    ];
  }

  browser = await chromium.launch(launchOpts);
  context = await browser.newContext(contextOpts);

  const requestStats = { get: 0, post: 0, post_to_target_host: 0 };
  const th = targetHostname();
  if (captureMode === "session" && th) {
    context.on("request", (req) => {
      const m = req.method().toUpperCase();
      if (m === "GET") requestStats.get += 1;
      else if (m === "POST") {
        requestStats.post += 1;
        try {
          if (new URL(req.url()).hostname === th) requestStats.post_to_target_host += 1;
        } catch (_) {}
      }
    });
  }

  page = await context.newPage();

  await page.goto(targetUrl, { waitUntil: "load", timeout: 60_000 });
  await page.waitForLoadState("networkidle", { timeout: 8_000 }).catch(() => {});
  log(`navigation ok title=${await page.title()}`);

  const storagePath = path.join(outDir, "storageState.json");

  if (captureMode === "oneshot") {
    await context.storageState({ path: storagePath });
    await context.close();
    await browser.close();

    writeRunJson({
      status: "passed",
      exit_code: 0,
      capture: { version: 1, mode: "oneshot", headless: headlessUi },
    });
    process.exit(0);
  }

  log(
    `CDP on 0.0.0.0:${cdpPort} — map with docker -p ${cdpPort}:${cdpPort}, then open chrome://inspect or curl http://127.0.0.1:${cdpPort}/json/version`
  );
  log("SECURITY: remote debugging is full browser control; never expose this port publicly.");

  let snapshotCount = 0;
  let snapBusy = false;

  async function snapshot() {
    if (snapBusy) return;
    snapBusy = true;
    try {
      await context.storageState({ path: storagePath });
      snapshotCount += 1;
      log(`storageState snapshot #${snapshotCount}`);
    } finally {
      snapBusy = false;
    }
  }

  await snapshot();

  const sentinelPath = path.join(outDir, "morayeel.done");
  log(`session active; create ${sentinelPath} or send SIGINT/SIGTERM to finalize HAR`);
  log(`periodic snapshots every ${snapshotMs}ms`);

  const snapshotTimer = setInterval(() => {
    snapshot().catch((e) => log(`snapshot error: ${e}`));
  }, snapshotMs);

  const sessionStartedAt = new Date().toISOString();

  const racers = [waitForShutdown(sentinelPath)];
  if (maxSessionMs > 0) {
    racers.push(
      new Promise((resolve) => {
        setTimeout(() => resolve("timeout"), maxSessionMs);
      })
    );
  }
  const shutdownReason = await Promise.race(racers);

  clearInterval(snapshotTimer);
  await snapshot().catch((e) => log(`final snapshot error: ${e}`));

  await context.close();
  await browser.close();

  const sessionFinishedAt = new Date().toISOString();

  writeRunJson({
    status: "passed",
    exit_code: 0,
    capture: {
      version: 1,
      mode: "session",
      headless: headlessUi,
      request_summary: requestStats,
      session: {
        cdp_port: cdpPort,
        snapshot_count: snapshotCount,
        shutdown_reason: shutdownReason,
        started_at: sessionStartedAt,
        finished_at: sessionFinishedAt,
      },
    },
  });
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
    capture: { version: 1, mode: captureMode, headless: headlessUi },
  });
  process.exit(1);
}
