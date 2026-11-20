// Runs this repo's guards (.claude/hooks/*) for OpenCode, the way Claude Code runs them from .claude/settings.json
// and Codex from .codex/hooks.json. Each script gets the event in Claude Code's shape. Throwing from
// tool.execute.before blocks the call and shows the reason to the model; a guard that can't run blocks too.
import { spawnSync } from "node:child_process"
import { join } from "node:path"

type Script = "session-start" | "guard" | "approval-recorder"

// Tools that touch no file and run no command: the question, todo and skill tools (guard.sh keeps the same set for
// Claude Code). Every other tool not handled below is refused, so a tool OpenCode adds later (or an MCP tool) can't
// list or read a private folder before a guard is written for it.
const UNGUARDED = new Set(["question", "todowrite", "todoread", "skill", "invalid"])

type Question = { question?: string; options?: { label?: string; description?: string }[]; multiple?: boolean }

export const Fortkeep = async ({ directory, worktree }: { directory: string; worktree: string }) => {
  const run = (script: Script, event: Record<string, unknown>) =>
    spawnSync("/bin/bash", [join(worktree, ".claude", "hooks", `${script}.sh`)], {
      input: JSON.stringify(event),
      encoding: "utf8",
      timeout: 30_000,
      env: { ...process.env, CLAUDE_PROJECT_DIR: worktree },
    })
  const guard = (tool_name: string, tool_input: Record<string, unknown>, cwd = directory) => {
    const r = run("guard", { hook_event_name: "PreToolUse", tool_name, tool_input, cwd })
    if (r.status !== 0) throw new Error(r.stderr?.trim() || `fortkeep: guard did not run (status ${r.status}, ${r.error ?? "no error"})`)
  }
  // The question tool's arguments, by call, for the approval recorder (older OpenCode passes no args after a call).
  const asked = new Map<string, { questions?: Question[] }>()

  // The session-start message (whether this copy is a signed release, last run) reaches the model with every request.
  const start = run("session-start", { hook_event_name: "SessionStart" })
  let message: string
  try {
    message = JSON.parse(start.stdout).hookSpecificOutput.additionalContext
  } catch {
    message = `WARNING: fortkeep's session-start check did not run (status ${start.status}): ${start.stderr?.trim() || "no output"}. Don't run fixes until it runs.`
  }

  return {
    "experimental.chat.system.transform": async (_input: unknown, output: { system: string[] }) => {
      output.system.push(message)
    },
    "tool.execute.before": async (input: { tool: string; callID?: string }, output: { args: any }) => {
      const a = output.args ?? {}
      switch (input.tool) {
        case "bash":
          guard("Bash", { command: a.command }, a.workdir ?? directory)
          break
        case "edit":
        case "write":
        case "multiedit":
          guard("Edit", { file_path: a.filePath })
          break
        case "apply_patch":
        case "patch":
          guard("apply_patch", { command: a.patchText })
          break
        case "read":
          guard("Read", { file_path: a.filePath })
          break
        case "list":
          // A folder listing: checked as a search of that folder, so a private folder and its parents are refused.
          guard("Glob", { pattern: "*", path: a.path ?? directory })
          break
        case "grep":
          guard("Grep", { pattern: a.pattern, path: a.path })
          break
        case "glob":
          guard("Glob", { pattern: a.pattern, path: a.path })
          break
        // Web fetch and search: guard.sh refuses them in a person's session, where a URL could carry results off the Mac.
        case "webfetch":
          guard("WebFetch", { url: a.url })
          break
        case "websearch":
          guard("WebSearch", { query: a.query })
          break
        case "question":
          if (input.callID) asked.set(input.callID, a)
          break
        default:
          if (!UNGUARDED.has(input.tool))
            throw new Error(`fortkeep: the ${input.tool} tool has no guard here, so it is refused. ` +
              "Use bash, read, grep, glob or list instead.")
      }
    },
    // The person's answers to the question tool, with the questions they answered, in Claude Code's shape: an
    // "Apply <ID>", "Undo <ID>", "Accept <ID>" or "Add private folder" to exactly the question checks/ask.sh prints
    // mints the approval token.
    "tool.execute.after": async (input: { tool: string; callID?: string; args?: any }, output: { metadata: any }) => {
      if (input.tool !== "question") return
      const args = input.args ?? (input.callID ? asked.get(input.callID) : undefined) ?? {}
      if (input.callID) asked.delete(input.callID)
      const questions: Question[] = args.questions ?? []
      const picked: string[][] = output.metadata?.answers ?? []
      const answers: Record<string, string> = {}
      questions.forEach((q, i) => {
        if (typeof q.question === "string") answers[q.question] = (picked[i] ?? []).join(", ")
      })
      const r = run("approval-recorder", {
        hook_event_name: "PostToolUse", tool_name: "question",
        tool_input: { questions: questions.map((q) => ({ ...q, multiSelect: q.multiple ?? false })) },
        tool_response: { answers },
      })
      if (r.status !== 0) throw new Error(`fortkeep: approval-recorder failed (status ${r.status}): ${r.stderr?.trim()}`)
    },
  }
}
