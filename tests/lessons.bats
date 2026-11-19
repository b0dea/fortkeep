load helpers

# In teach mode the agent reads each lesson by these labels, so a lesson missing one leaves a gap mid-review.
@test "every lesson has the five labels the agent reads" {
  n=0; missing=""
  for f in "$REPO"/teach/*.md; do
    [ -f "$f" ] || continue
    n=$((n + 1))
    for l in 'Why:' 'Real attack:' 'Check it yourself:' 'How to fix:' 'What the agent is doing:'; do
      grep -q "^\*\*$l\*\*" "$f" || missing="$missing ${f##*/} ($l)"
    done
  done
  [ "$n" -gt 0 ]
  [ -z "$missing" ] || { echo "lessons missing a label:$missing"; false; }
}
