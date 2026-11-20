#!/bin/bash
# The person's own LaunchAgents (~/Library/LaunchAgents): labels, schedules, scripts, loaded state.
fortkeep_user_agents() {  # label<TAB>plist, for each agent with a Label
  local p l
  for p in "$HOME/Library/LaunchAgents"/*.plist; do
    [ -f "$p" ] || continue
    l="$(plutil -extract Label raw "$p" 2>/dev/null)" || continue
    printf '%s\t%s\n' "$l" "$p"
  done
}

fortkeep_agent_loaded() { launchctl print "gui/$(id -u)/$1" >/dev/null 2>&1; }

fortkeep_agent_weekly() {  # PLIST — true if StartCalendarInterval (dict or array) has a Weekday
  plutil -convert json -o - "$1" 2>/dev/null | jq -e '(.StartCalendarInterval // {})
    | if type == "array" then any(.[]; type == "object" and has("Weekday")) else type == "object" and has("Weekday") end' >/dev/null 2>&1
}

fortkeep_agent_script() {  # PLIST — the file the job runs (the script, when a shell runs it; none for sh -c)
  plutil -convert json -o - "$1" 2>/dev/null | jq -er '(.ProgramArguments // []) as $a
    | if ($a[0] // "" | split("/") | last | IN("sh", "bash", "zsh")) and ($a[1] // null) != null then
        (first($a[1:][] | select(startswith("-") | not) // empty) // empty) as $s
        | if any($a[1:][]; test("^-[a-zA-Z]*c$")) then empty else $s end
      else ($a[0] // .Program // empty) end'
}

fortkeep_agent_command() {  # PLIST — the inline command of a shell job run with -c (or -lc), else nothing
  plutil -convert json -o - "$1" 2>/dev/null | jq -er '(.ProgramArguments // []) as $a
    | if ($a[0] // "" | split("/") | last | IN("sh", "bash", "zsh")) then
        first(range(1; $a | length) | select($a[.] | test("^-[a-zA-Z]*c$")) | $a[. + 1] // empty) // empty
      else empty end'
}
