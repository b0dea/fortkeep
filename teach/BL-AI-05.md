# BL-AI-05 · MCP servers pinned to a version

**Why:** An MCP server starts every time the agent starts. `npx -y some-server` fetches whatever version is newest at that moment, so a hijacked release runs on your next session, with the agent's access.

**Real attack:** In September 2025 a fake copy of Postmark's email MCP server on npm behaved normally for 15 versions, then version 1.0.16 quietly copied every email it sent to an outside address. Anyone pinned to an earlier version never received that change. ([source](https://www.theregister.com/2025/09/29/postmark_mcp_server_code_hijacked/))

**Check it yourself:** in your Claude Code MCP config (`claude mcp list`, or `~/.claude.json`), every `npx`, `uvx`, `bunx` or `pnpm dlx` server names an exact version: `pkg@1.2.3` or `pkg==1.2.3`.

**How to fix:** for each server the agent names, look up the version you're using and pin it: remove and re-add it with `claude mcp add … -- npx -y pkg@1.2.3`. Update deliberately, not automatically.

**What the agent is doing:** reading your MCP server list and reporting only the names of unpinned servers. Their arguments and settings, which can hold tokens, are never shown.
