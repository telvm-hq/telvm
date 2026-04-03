/**
 * Thin HTTP client for the telvm companion Machine API.
 * @see https://github.com/telvm-hq/telvm/blob/main/docs/agent-api.md
 */

export function getBaseUrl(): string {
  const raw = process.env.TELVM_BASE_URL ?? "http://localhost:4000";
  return raw.replace(/\/$/, "");
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
