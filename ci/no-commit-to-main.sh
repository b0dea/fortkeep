#!/bin/bash
# lefthook pre-commit: refuses a commit made directly on main. Work on a branch, then merge.
case "$(git symbolic-ref --short -q HEAD)" in
  main|master) echo "no-commit-to-main: commit on a branch, then merge it into main" >&2; exit 1 ;;
esac
exit 0
