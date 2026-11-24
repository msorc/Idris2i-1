#!/bin/sh
. "$(dirname "$0")/../../lib.sh"

REST="GET /health answers 200 ok
POST /sum adds the numbers
POST /sum with an empty list gives 0
POST /sum with malformed JSON answers 400
POST /sum with JSON of the wrong shape answers 400
GET /count counts the successful sums, also after 40 parallel requests
an unknown path answers 404"

rm -rf build
assert "idris2i-1 --build sumsvc.ipkg succeeds" "$IDRIS" --build sumsvc.ipkg
if [ ! -x build/exec/sumsvc ]; then
  echo "$REST" | while read -r t; do fail "$t" "no executable"; done
  exit 0
fi
port=$(python3 -c 'import socket; s = socket.socket(); s.bind(("127.0.0.1", 0)); print(s.getsockname()[1])')
./build/exec/sumsvc "$port" >"$GRADE_TMP/server.log" 2>&1 &
pid=$!
trap 'kill $pid 2>/dev/null; rm -rf "$GRADE_TMP"' EXIT
base=http://127.0.0.1:$port
i=0
until curl -s -o /dev/null "$base/health" || [ $i -ge 50 ]; do i=$((i + 1)); sleep 0.2; done

req() { # method path [body]: prints "STATUS BODY"
  if [ $# -ge 3 ]; then
    curl -s -m 10 -o "$GRADE_TMP/body" -w '%{http_code}' -X "$1" -H 'Content-Type: application/json' --data "$3" "$base$2"
  else
    curl -s -m 10 -o "$GRADE_TMP/body" -w '%{http_code}' -X "$1" "$base$2"
  fi
  printf ' %s' "$(cat "$GRADE_TMP/body" 2>/dev/null)"
}
json_is() { # actual "STATUS BODY", status, python expression over the parsed body `j`
  python3 -c '
import json, sys
status, _, body = sys.argv[1].partition(" ")
try:
    j = json.loads(body)
except Exception:
    sys.exit(1)
sys.exit(0 if status == sys.argv[2] and eval(sys.argv[3]) else 1)
' "$1" "$2" "$3"
}
expect() { # assertion, actual, condition result
  if [ "$3" -eq 0 ]; then pass "$1" "$2"; else fail "$1" "$2"; fi
}

r=$(req GET /health)
case $r in "200 ok"|"200 ok
") expect "GET /health answers 200 ok" "$r" 0 ;; *) expect "GET /health answers 200 ok" "$r" 1 ;; esac

r=$(req POST /sum '{"xs": [1, 2, 3]}'); json_is "$r" 200 'j == {"sum": 6}'; a=$?
r2=$(req POST /sum '{"xs":[-5,100,7]}'); json_is "$r2" 200 'j == {"sum": 102}'; b=$?
expect "POST /sum adds the numbers" "$r / $r2" $((a + b))

r=$(req POST /sum '{"xs": []}'); json_is "$r" 200 'j == {"sum": 0}'
expect "POST /sum with an empty list gives 0" "$r" $?

r=$(req POST /sum '{"xs": [1, 2'); case $r in 400*) c=0 ;; *) c=1 ;; esac
expect "POST /sum with malformed JSON answers 400" "$r" $c

r=$(req POST /sum '{"ys": [1]}'); case $r in 400*) a=0 ;; *) a=1 ;; esac
r2=$(req POST /sum '{"xs": "no"}'); case $r2 in 400*) b=0 ;; *) b=1 ;; esac
expect "POST /sum with JSON of the wrong shape answers 400" "$r / $r2" $((a + b))

for n in $(seq 40); do
  curl -s -m 10 -o /dev/null -X POST --data "{\"xs\": [$n]}" "$base/sum" &
done
wait $(jobs -p | grep -v "^$pid\$") 2>/dev/null
r=$(req GET /count); json_is "$r" 200 'j == {"requests": 43}'
expect "GET /count counts the successful sums, also after 40 parallel requests" "$r" $?

r=$(req GET /nowhere); case $r in 404*) c=0 ;; *) c=1 ;; esac
expect "an unknown path answers 404" "$r" $c
