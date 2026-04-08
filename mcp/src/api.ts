/**
 * Thin HTTP client for the telvm companion Machine API.
 * @see https://github.com/telvm-hq/telvm/blob/main/docs/agent-api.md
 */

export function getBaseUrl(): string {
  const raw = process.env.TELVM_BASE_URL ?? "http://localhost:4000";
  return raw.replace(/\/$/, "");
}

export function getNetworkAgentUrl(): string {
  const raw = process.env.TELVM_NETWORK_AGENT_URL ?? "";
  return raw.replace(/\/$/, "");
}

export function getNetworkAgentToken(): string {
  return process.env.TELVM_NETWORK_AGENT_TOKEN ?? "";
}

export async function networkAgentFetch(
  path: string,
  init?: RequestInit
): Promise<ApiResult> {
  const base = getNetworkAgentUrl();
  if (!base) {
    return {
      ok: false,
      status: 0,
      bodyText: "TELVM_NETWORK_AGENT_URL not configured. Set it to the network agent base URL (e.g. http://192.168.137.1:9225).",
    };
  }
  const url = `${base}${path.startsWith("/") ? path : `/${path}`}`;
  const token = getNetworkAgentToken();
  const headers: Record<string, string> = {
    Accept: "application/json",
    ...((init?.headers as Record<string, string>) ?? {}),
  };
  if (token) {
    headers["Authorization"] = `Bearer ${token}`;
  }
  try {
    const res = await fetch(url, { ...init, headers });
    const bodyText = await res.text();
    return { ok: res.ok, status: res.status, bodyText };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new Error(
      `Cannot reach telvm network agent at ${base}: ${msg}. Is the PowerShell agent running?`
    );
  }
}

export type ApiResult = {
  ok: boolean;
  status: number;
  bodyText: string;
};

export async function apiFetch(
  path: string,
  init?: RequestInit
): Promise<ApiResult> {
  const url = `${getBaseUrl()}${path.startsWith("/") ? path : `/${path}`}`;
  try {
    const res = await fetch(url, {
      ...init,
      headers: {
        Accept: "application/json",
        ...init?.headers,
      },
    });
    const bodyText = await res.text();
    return { ok: res.ok, status: res.status, bodyText };
  } catch (e: unknown) {
    const msg = e instanceof Error ? e.message : String(e);
    throw new Error(
      `Cannot reach telvm companion at ${getBaseUrl()}: ${msg}. Is "docker compose up" running and companion listening on port 4000?`
    );
  }
}

export function formatJsonBody(bodyText: string): string {
  const t = bodyText.trim();
  if (!t) return "(empty response)";
  try {
    return JSON.stringify(JSON.parse(t), null, 2);
  } catch {
    return bodyText;
  }
}

export function textResult(bodyText: string, status: number, ok: boolean): string {
  const formatted = formatJsonBody(bodyText);
  if (ok) return formatted;
  return `HTTP ${status}\n${formatted}`;
}
