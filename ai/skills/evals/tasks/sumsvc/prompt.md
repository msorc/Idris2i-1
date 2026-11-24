Write a small HTTP service in Idris2i-1, as a package: `sumsvc.ipkg` in the current
directory, sources under `src/`, so that `idris2i-1 --build sumsvc.ipkg` produces
`build/exec/sumsvc`.

`sumsvc PORT` listens on `127.0.0.1:PORT` and serves until it is killed:

- `GET /health` answers 200 with the body `ok`
- `POST /sum` with a JSON body like `{"xs": [1, 2, 3]}` answers 200 with the JSON
  `{"sum": 6}` (the numbers are integers, the list may be empty)
- `POST /sum` with a body that is not JSON of that shape answers 400
- `GET /count` answers 200 with the JSON `{"requests": N}`, where N is the number of
  `/sum` requests answered with 200 so far
- any other path answers 404

Requests can arrive in parallel; the count must not lose updates. Use the HTTP and
JSON libraries that come with this compiler, not sockets by hand.
