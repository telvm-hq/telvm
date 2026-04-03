/**
 * telvm MCP server — stdio transport, tools map to GET/POST/DELETE on /telvm/api.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import * as z from "zod";
import { apiFetch, formatJsonBody, getBaseUrl, textResult } from "./api.js";

function toolText(text: string) {
  return { content: [{ type: "text" as const, text }] };
}

async function main() {
  const server = new McpServer(
    {
      name: "telvm-mcp",
      version: "0.1.0",
    },
    {
      instructions: `telvm Machine API bridge. Companion base URL: ${getBaseUrl()} (override with TELVM_BASE_URL). Requires Docker running with telvm companion on localhost:4000. No API authentication in v0.1.0.`,
    }
  );

  server.registerTool(
    "telvm_list_machines",
    {
      description:
        "List lab containers (label telvm.vm_manager_lab=true). GET /telvm/api/machines.",
    },
    async () => {
      const r = await apiFetch("/telvm/api/machines");
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_get_machine",
    {
      description: "Get one machine by Docker container id. GET /telvm/api/machines/:id.",
      inputSchema: {
        id: z.string().min(1).describe("Container id (full id or inspect id)"),
      },
    },
    async ({ id }) => {
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}`);
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_create_machine",
    {
      description:
        "Create and start a lab container. POST /telvm/api/machines. Optional image, cmd (argv array), workspace, use_image_cmd.",
      inputSchema: {
        image: z.string().optional().describe("Docker image ref"),
        cmd: z.array(z.string()).optional().describe("Container command argv"),
        workspace: z.string().optional(),
        use_image_cmd: z.boolean().optional().describe("If true, use image default CMD"),
      },
    },
    async (args) => {
      const body: Record<string, unknown> = {};
      if (args.image != null) body.image = args.image;
      if (args.cmd != null) body.cmd = args.cmd;
      if (args.workspace != null) body.workspace = args.workspace;
      if (args.use_image_cmd != null) body.use_image_cmd = args.use_image_cmd;

      const r = await apiFetch("/telvm/api/machines", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body),
      });
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_exec",
    {
      description:
        "Run a command inside a container. POST /telvm/api/machines/:id/exec. cmd must be a non-empty argv array.",
      inputSchema: {
        id: z.string().min(1).describe("Container id"),
        cmd: z.array(z.string()).min(1).describe("Argv array, e.g. [\"sh\",\"-c\",\"ls -la\"]"),
        workdir: z.string().optional().describe("Working directory inside container"),
      },
    },
    async ({ id, cmd, workdir }) => {
      const payload: Record<string, unknown> = { cmd };
      if (workdir != null) payload.workdir = workdir;
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}/exec`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_delete_machine",
    {
      description: "Stop and remove a lab container. DELETE /telvm/api/machines/:id.",
      inputSchema: {
        id: z.string().min(1).describe("Container id"),
      },
    },
    async ({ id }) => {
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}`, {
        method: "DELETE",
      });
      if (r.status === 204) {
        return toolText("Deleted (HTTP 204).");
      }
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_machine_logs",
    {
      description: "Tail container logs. GET /telvm/api/machines/:id/logs?tail=n.",
      inputSchema: {
        id: z.string().min(1),
        tail: z.number().int().min(1).max(10000).optional().describe("Max lines (default 500)"),
      },
    },
    async ({ id, tail }) => {
      const q = tail != null ? `?tail=${tail}` : "";
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}/logs${q}`);
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_machine_stats",
    {
      description: "One-shot container stats. GET /telvm/api/machines/:id/stats (optional raw=1).",
      inputSchema: {
        id: z.string().min(1),
        raw: z.boolean().optional().describe("If true, raw Docker stats JSON"),
      },
    },
    async ({ id, raw }) => {
      const q = raw === true ? "?raw=1" : "";
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}/stats${q}`);
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_restart_machine",
    {
      description: "Restart container. POST /telvm/api/machines/:id/restart",
      inputSchema: {
        id: z.string().min(1),
        timeout_sec: z.number().int().min(1).optional().describe("Optional timeout query t="),
      },
    },
    async ({ id, timeout_sec }) => {
      const q =
        timeout_sec != null ? `?t=${encodeURIComponent(String(timeout_sec))}` : "";
      const r = await apiFetch(
        `/telvm/api/machines/${encodeURIComponent(id)}/restart${q}`,
        { method: "POST" }
      );
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_pause_machine",
    {
      description: "Pause container (cgroup freeze). POST /telvm/api/machines/:id/pause",
      inputSchema: { id: z.string().min(1) },
    },
    async ({ id }) => {
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}/pause`, {
        method: "POST",
      });
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  server.registerTool(
    "telvm_unpause_machine",
    {
      description: "Resume paused container. POST /telvm/api/machines/:id/unpause",
      inputSchema: { id: z.string().min(1) },
    },
    async ({ id }) => {
      const r = await apiFetch(`/telvm/api/machines/${encodeURIComponent(id)}/unpause`, {
        method: "POST",
      });
      return toolText(textResult(r.bodyText, r.status, r.ok));
    }
  );

  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
