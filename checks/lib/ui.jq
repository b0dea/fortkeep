# The Terminal look of fortkeep's results: colour, a symbol per status, the score bar, and lines wrapped to the
# terminal's width. bin/fortkeep uses it only for a person at a terminal (checks/lib/ui.sh, ui_on); everything else
# gets plain text. Load it as results.jq says, with include "ui".
include "results";

def esc($c): "\u001b[\($c)m\(.)\u001b[0m";
def bold: esc("1"); def gray: esc("90"); def red: esc("31"); def green: esc("32"); def yellow: esc("33");
def cyan: esc("36"); def purple: esc("1;35");

def paint($status): if $status == "PASS" then green elif $status == "FAIL" then red elif $status == "ERROR" then yellow
  elif $status == "ACCEPTED" then cyan else gray end;
def mark: . as $s | {PASS: "✓", FAIL: "✗", ERROR: "!", ACCEPTED: "○", NA: "–"}[$s] // "?" | paint($s);
def repeat($n): if $n > 0 then . * $n else "" end;
def clean: tostring | gsub("[[:cntrl:]]"; " ");

# A string as lines of at most $w characters, broken at spaces. A word longer than a line keeps a line of its own
# rather than being cut: paths and commands stay whole for copying.
def wrap($w): reduce (split(" ")[] | select(. != "")) as $word ([];
    if length > 0 and (.[-1] | length) + 1 + ($word | length) <= $w then .[length - 1] += " " + $word
    else . + [$word] end)
  | if length == 0 then [""] else . end;
def indent($n): (" " | repeat($n)) + .;
# TEXT wrapped to $w, its first line after a label of $n characters (already printed) and the rest indented to it.
def hang($n; $w): wrap([$w - $n, 20] | max) | (.[0]), (.[1:][] | indent($n));

def count(f): [.[] | select(f)] | length;
def tint($c): if $c == "bold" then bold elif $c == "red" then red elif $c == "yellow" then yellow elif $c == "cyan" then cyan
  else gray end;

# The score: a bar, then "52 of 66 met · 3 urgent · 4 to fix ...", wrapped to $w after the bar. Met is PASS, out of
# the controls that apply (all but NA). Urgent FAILs count as urgent, not as "to fix". The bar is at most $barw wide,
# and gives up width (down to 10) when that keeps the text on one line.
def score($ctl; $barw; $w):
  [.[] | select(.status != "NA")] as $apply
  | ($apply | length) as $n | ($apply | count(.status == "PASS")) as $met
  | [["\($met) of \($n) met", "bold"],
     (count(urgent($ctl)) | select(. > 0) | ["\(.) urgent", "red"]),
     (count(.status == "FAIL" and (urgent($ctl) | not)) | select(. > 0) | ["\(.) to fix", "red"]),
     (count(.status == "ERROR") | select(. > 0) | ["\(.) couldn't check", "yellow"]),
     (count(.status == "ACCEPTED") | select(. > 0) | ["\(.) accepted", "cyan"]),
     (count(.status == "NA") | select(. > 0) | ["\(.) don't apply", "gray"])] as $parts
  | ($w - 4 - ($parts | map(.[0]) | join(" · ") | length)) as $fit
  | (if $fit >= $barw or $fit < 10 then $barw else $fit end) as $bw
  | (if $n > 0 then ($met * $bw / $n | floor) else 0 end) as $full
  | ([$w - $bw - 4, 20] | max) as $room
  # The parts in lines of at most $room characters, never splitting a part.
  | (reduce $parts[] as $p ([];
      if length > 0 and (.[-1] | map(.[0] | length + 3) | add) + ($p[0] | length) <= $room then .[length - 1] += [$p]
      else . + [[$p]] end)
     | map(map(. as [$t, $c] | $t | tint($c))) | map(join(" · " | gray))) as $lines
  | ("█" | repeat($full) | green) + ("░" | repeat($bw - $full) | gray) + "  " + $lines[0],
    ($lines[1:][] | indent($bw + 4));

# One result: its symbol, status, id and title, then its evidence or reason under the id. Titles wrap under the
# title column (23), evidence under the id column (13).
def row($w):
  (.status | clean) as $s
  | [.title | clean | hang(23; $w)] as $t
  | "  \($s | mark) \($s + "        " | .[0:8] | paint($s)) \(.id | clean)  \($t[0])",
    $t[1:][],
    (if $s == "PASS" then empty
     elif $s == "ACCEPTED" then "your reason: \(.note // "" | clean)"
     elif (.evidence // "") != "" then .evidence | clean
     else empty end
     | wrap([$w - 13, 20] | max)[] | indent(13) | gray);

# A closing line: LABEL (8 characters, already styled) and TEXT wrapped after it.
def closing($label; $w): [hang(8; $w)] | $label + .[0], .[1:][];

# The whole of `fortkeep check` for a terminal: the header, the score, the results in results.jq's order with one
# heading per group, and what to do next. $picked: the results to show; .results: all of them, for the score.
def check_view($ctl; $picked; $w; $when; $self):
  ([$picked[] | .status == "FAIL" or .status == "ERROR"] | any) as $failing
  | ([$picked[] | urgent($ctl)] | any) as $urgent
  | ("fortkeep check" | bold) + ("  \($when) · macOS \(.macos | clean)" | gray),
    "",
    (.results | score($ctl; 20; $w - 2) | indent(2)),
    "",
    ($picked | map(. + {group: group($ctl)}) | group_by(.group) | sort_by(.[0].group | group_rank) | .[]
     | (.[0].group | clean) as $g
     | (if $g == "URGENT" then ("➤ URGENT" | esc("1;31")) + ("  may mean this Mac is compromised now" | gray)
        else "➤ \($g)" | purple end),
       (ordered($ctl)[] | row($w)),
       ""),
    (if $urgent then
       ("this may mean the Mac is compromised now." | closing("Urgent: " | esc("1;31"); $w)),
       ("read \($self)/docs/if-red.md before anything else, or type /if-red in your agent." | closing("Next:   " | bold; $w))
     elif $failing then
       "fortkeep agent, then type /fix (in Codex, $fix). Why one matters: fortkeep explain ID." | closing("Next:   " | bold; $w)
     else
       "nothing to fix; check again now and then with fortkeep check." | closing("Next:   " | bold; $w)
     end);
