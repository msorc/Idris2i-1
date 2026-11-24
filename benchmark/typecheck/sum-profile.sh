#!/usr/bin/env bash
# Sum the profiles that `idris2i-1 --timing-summary` printed, in one log or
# several (a build with --jobs prints one profile per process: they are all
# added up), and print them as tables.
#
# Usage: sum-profile.sh [-m MODULES] [-d DECLS] LOG...
#   -m N   show the N most expensive modules (default: 10)
#   -d N   show the N most expensive declarations of each of the 2 most
#          expensive modules (default: 10)
#
# Times are in milliseconds of processor time. "incl" counts the timers run
# inside a timer, "self" does not: the self times add up to the timed total,
# and the time of the process that no timer saw is "untimed".

set -u
MODS=10
DECLS=10
while getopts ":m:d:h" opt; do
  case "$opt" in
    m) MODS="$OPTARG" ;;
    d) DECLS="$OPTARG" ;;
    h) sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "usage: $0 [-m N] [-d N] LOG..." >&2; exit 1 ;;
  esac
done
shift $((OPTIND - 1))

cat "$@" | awk -v mods="$MODS" -v decls="$DECLS" '
function ms(us) { return sprintf("%.0f", us / 1000) }
function kv(s, key,   n, a, i, p) {
  n = split(s, a, " ")
  for (i = 1; i <= n; i++) { p = index(a[i], "="); if (substr(a[i], 1, p - 1) == key) return substr(a[i], p + 1) }
  return 0
}
$1 == "PROFILE" && $2 == "process" {
  procs++; cpu += kv($0, "cpu"); timed += kv($0, "timed"); untimed += kv($0, "untimed")
  r = kv($0, "peak_rss_kib"); if (r + 0 > rss) rss = r + 0
}
$1 == "PROFILE" && $2 == "timer" {
  k = $3; tcalls[k] += kv($0, "calls"); tincl[k] += kv($0, "incl"); tself[k] += kv($0, "self")
}
$1 == "PROFILE" && $2 == "counter" { cnt[$3] += $4 }
$1 == "PROFILE" && $2 == "module" {
  m = $3; mcpu[m] = kv($0, "cpu"); mline[m] = $0
}
$1 == "PROFILE" && $2 == "decl" {
  m = $3; nd[m]++; dline[m, nd[m]] = $0
}
END {
  printf "processes: %d   cpu: %s ms   timed: %s ms   untimed (start-up, driver, ...): %s ms   peak RSS of one process: %d MiB\n\n", procs, ms(cpu), ms(timed), ms(untimed), rss / 1024
  printf "%-26s %10s %10s %7s %10s %7s\n", "timer", "calls", "incl_ms", "incl%", "self_ms", "self%"
  n = 0
  for (k in tself) keys[++n] = k
  # sort by self time
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (tself[keys[j]] > tself[keys[i]]) { t = keys[i]; keys[i] = keys[j]; keys[j] = t }
  for (i = 1; i <= n; i++) { k = keys[i]
    printf "%-26s %10d %10s %6.1f%% %10s %6.1f%%\n", k, tcalls[k], ms(tincl[k]), cpu ? 100 * tincl[k] / cpu : 0, ms(tself[k]), cpu ? 100 * tself[k] / cpu : 0 }
  printf "%-26s %10s %10s %7s %10s %6.1f%%\n\n", "(untimed)", "", "", "", ms(untimed), cpu ? 100 * untimed / cpu : 0
  printf "%-40s %14s\n", "counter", "value"
  n = 0
  for (k in cnt) ckeys[++n] = k
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (ckeys[j] < ckeys[i]) { t = ckeys[i]; ckeys[i] = ckeys[j]; ckeys[j] = t }
  for (i = 1; i <= n; i++) printf "%-40s %14d\n", ckeys[i], cnt[ckeys[i]]
  n = 0
  for (m in mcpu) mkeys[++n] = m
  for (i = 1; i <= n; i++) for (j = i + 1; j <= n; j++) if (mcpu[mkeys[j]] + 0 > mcpu[mkeys[i]] + 0) { t = mkeys[i]; mkeys[i] = mkeys[j]; mkeys[j] = t }
  printf "\n%d modules built; the most expensive (self times by timer, in microseconds; #counters):\n", n
  for (i = 1; i <= n && i <= mods; i++) { m = mkeys[i]
    line = mline[m]; sub(/^PROFILE module [^ ]* /, "", line)
    printf "%2d. %s  %s ms  %s\n", i, m, ms(mcpu[m]), line }
  for (i = 1; i <= n && i <= 2; i++) { m = mkeys[i]
    printf "\nthe most expensive declarations of %s:\n", m
    for (j = 1; j <= nd[m] && j <= decls; j++) { line = dline[m, j]; sub(/^PROFILE decl [^ ]* /, "", line); printf "  %s\n", line } }
}'
