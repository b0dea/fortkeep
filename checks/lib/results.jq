# How devward orders and counts results, for every script that shows them. Load it with
#   jq -L <this folder> --slurpfile c controls.json 'include "results"; ($c[0] | controls_by_id) as $ctl | ...'

def controls_by_id: map({key: .id, value: .}) | from_entries;  # the controls list, as a map from id to control

# A result that may mean the Mac is compromised now: a FAIL of an urgent control, unless its evidence starts with the
# set-up step that control names in not_urgent_if.
def urgent($ctl): $ctl[.id] as $k | $k.urgent == true and .status == "FAIL"
  and (($k.not_urgent_if // null) as $n | $n == null or ((.evidence // "") | startswith($n) | not));

# The order every skill uses: the urgent results first, then MUST, SHOULD, NICE, and within each FAIL, ERROR,
# ACCEPTED, NA, PASS, then by id.
def group($ctl): if urgent($ctl) then "URGENT" else .level end;
def group_rank: {"URGENT": 0, "MUST": 1, "SHOULD": 2, "NICE": 3}[.] // 4;
def status_rank: {"FAIL": 0, "ERROR": 1, "ACCEPTED": 2, "NA": 3, "PASS": 4}[.] // 5;
def ordered($ctl): sort_by((group($ctl) | group_rank), (.status | status_rank), .id);

def tally: group_by(.status) | map({status: .[0].status, count: length});  # results → how many of each status
def tally_text: tally | map("\(.status) \(.count)") | join(" · ");          # "FAIL 2 · PASS 40"
