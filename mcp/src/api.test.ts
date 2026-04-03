import { describe, it, expect } from "vitest";
import { formatJsonBody } from "./api.js";

describe("formatJsonBody", () => {
  it("pretty-prints JSON", () => {
    expect(formatJsonBody('{"a":1}')).toBe("{\n  \"a\": 1\n}");
  });

  it("returns non-JSON as-is", () => {
    expect(formatJsonBody("plain")).toBe("plain");
  });
});
