// Running the main expression of a program on a large stack (Node only).
//
// The stack of the main thread of Node is about 1MB, which much of the
// library (`foldr`, `sort`, monadic code, ...) uses up on lists of a few
// thousand elements.  Node cannot grow it, and `--stack-size` beyond the
// stack that the operating system gave the thread crashes the process.  So,
// when the program is run as a script, the main thread starts a worker thread
// with a stack of its own (1GB unless the environment variable
// IDRIS2_MAIN_STACK_SIZE gives another size in bytes; 0 runs the program on
// the main thread), runs the program there and waits for it.
//
// The worker behaves like the main thread as far as the support code can
// tell: output to stdout and stderr is written synchronously, the exit code
// and uncaught exceptions are passed on, and what only the main thread can
// do (change the working directory, listen to signals) is forwarded to it.

const __idris2_mainDefaultStackMb = 1024

// The signals that System.Signal collects (see support_system_signal.js):
// bit n is set when signal number n has arrived and not been handled yet.
// It is shared by the main thread, which receives the signals, and the
// worker that runs `main`, so that the worker sees a signal at once (the
// event loop of the worker does not run while `main` does).
let __idris2_signalWord = null

function __idris2_signalBits() {
  if (__idris2_signalWord === null)
    __idris2_signalWord = new Int32Array(new SharedArrayBuffer(4))
  return __idris2_signalWord
}

function __idris2_markSignal(num) {
  const bits = __idris2_signalBits()
  Atomics.or(bits, 0, 1 << num)
  Atomics.notify(bits, 0)
}

// What System.Signal does with a signal on the main thread: 'collect' it,
// 'ignore' it, or leave it to its 'default' action.  (Only the listener of
// System.Signal is replaced: listeners that other code added stay.)
const __idris2_signalHandlers = new Map()

function __idris2_setSignal(name, num, mode) {
  const old = __idris2_signalHandlers.get(name)
  const h = mode === 'collect' ? () => __idris2_markSignal(num)
          : mode === 'ignore' ? () => {} : undefined
  if (h !== undefined) process.on(name, h)  // (may throw: SIGKILL, SIGSTOP)
  if (old !== undefined) process.removeListener(name, old)
  if (h !== undefined) __idris2_signalHandlers.set(name, h)
  else __idris2_signalHandlers.delete(name)
}

// The same, from the thread that runs `main` (set to an RPC to the main
// thread in the worker).
let __idris2_controlSignal = __idris2_setSignal

// The request to the main thread, as a function that waits for the answer
// and returns its value: null when `main` runs on the main thread.
let __idris2_rpc = null

// The child processes that System.File's popen and popen2 started (on the
// main thread, whose event loop runs while `main` waits in its worker, and
// sees them exit), by process id: { child, status, waiters }.
const __idris2_children = new Map()

function __idris2_signalNumber(name) {
  const n = require('os').constants.signals[name]
  return n === undefined ? 1 : n
}

// A child process `sh -c cmd` whose stdin and stdout are each a 'pipe' (a
// descriptor of the process that the worker reads or writes with `fs`) or
// 'inherit'.  The streams of the pipes are not read here: libuv would take
// the data from the pipe into memory.  Returns the process id and the
// descriptors (-1 for what is inherited).
function __idris2_spawnChild(cmd, stdin, stdout) {
  const child = require('child_process').spawn('/bin/sh', ['-c', cmd],
    { stdio: [stdin, stdout, 'inherit'] })
  child.on('error', () => {})
  if (child.pid === undefined) {
    const e = new Error('spawn /bin/sh ENOENT')
    e.code = 'ENOENT'
    e.errno = -2
    throw e
  }
  const entry = { child: child, status: null, waiters: [] }
  child.on('exit', (code, signal) => {
    entry.status = code !== null ? code : 128 + __idris2_signalNumber(signal)
    for (const w of entry.waiters) w(entry.status)
    entry.waiters = []
  })
  __idris2_children.set(child.pid, entry)
  if (child.stdout !== null) child.stdout._handle.readStop()
  return { pid: child.pid,
           in: child.stdin !== null ? child.stdin._handle.fd : -1,
           out: child.stdout !== null ? child.stdout._handle.fd : -1 }
}

// Calls `reply` with the exit status of the child, once it has exited.
function __idris2_waitChild(pid, reply) {
  const entry = __idris2_children.get(pid)
  if (entry === undefined) {
    const e = new Error('no child process ' + pid)
    e.code = 'ECHILD'
    throw e
  }
  __idris2_children.delete(pid)
  if (entry.status !== null) reply(entry.status)
  else entry.waiters.push(reply)
}

function __idris2_closeChildPipe(pid, which) {
  const entry = __idris2_children.get(pid)
  if (entry === undefined) return
  const stream = which === 'in' ? entry.child.stdin : entry.child.stdout
  if (stream !== null) stream.destroy()
}

function __idris2_mainStackMb() {
  const s = process.env.IDRIS2_MAIN_STACK_SIZE
  if (s === undefined || s === '') return __idris2_mainDefaultStackMb
  const n = Number(s)
  if (!Number.isFinite(n) || n < 0) return __idris2_mainDefaultStackMb
  return Math.ceil(n / 1048576)
}

// What the worker asks the main thread to do, synchronously: the worker
// posts a request and waits on the first word of `shared` until the main
// thread has written the answer (its length in the second word, then the
// answer as JSON).
const __idris2_rpcSize = 65536

function __idris2_rpcAnswer(shared, answer) {
  const flag = new Int32Array(shared, 0, 2)
  const bytes = Buffer.from(JSON.stringify(answer), 'utf8')
  const n = Math.min(bytes.length, __idris2_rpcSize)
  bytes.copy(Buffer.from(shared, 8, __idris2_rpcSize), 0, 0, n)
  flag[1] = n
  Atomics.store(flag, 0, 1)
  Atomics.notify(flag, 0)
}

function __idris2_runInWorker(wt, mb) {
  const shared = new SharedArrayBuffer(8 + __idris2_rpcSize)
  const signals = new SharedArrayBuffer(4)
  __idris2_signalWord = new Int32Array(signals)
  // (only a terminal is looked at: `process.stdout` of a pipe would make the
  // pipe non-blocking)
  const tty = (fd, s) => require('tty').isatty(fd)
    ? { isTTY: true, columns: s().columns, rows: s().rows } : {}
  let worker
  try {
    worker = new wt.Worker(__filename, {
      argv: process.argv.slice(2),
      env: wt.SHARE_ENV,
      stdin: true,
      workerData: { __idris2Main: shared, signals: signals,
                    stdout: tty(1, () => process.stdout),
                    stderr: tty(2, () => process.stderr) },
      resourceLimits: { stackSizeMb: mb }
    })
  } catch (e) {
    // No thread with a stack of this size: run on the main thread.
    return false
  }
  const listeners = new Map()
  let stdinForwarded = false
  worker.on('message', m => {
    if (m === null || typeof m !== 'object' || m.__idris2Rpc === undefined) return
    const r = m.__idris2Rpc
    try {
      let value
      switch (r.op) {
        case 'chdir':
          process.chdir(r.dir)
          break
        case 'listen':
          if (!listeners.has(r.signal)) {
            const h = () => worker.postMessage({ __idris2Signal: r.signal })
            listeners.set(r.signal, h)
            process.on(r.signal, h)
          }
          break
        case 'signal':
          __idris2_setSignal(r.signal, r.num, r.mode)
          break
        case 'stdin':
          // The worker reads `process.stdin`: pass on what the main thread
          // reads from fd 0.
          if (!stdinForwarded) {
            stdinForwarded = true
            process.stdin.pipe(worker.stdin)
          }
          break
        case 'unlisten': {
          const h = listeners.get(r.signal)
          if (h !== undefined) process.removeListener(r.signal, h)
          listeners.delete(r.signal)
          break
        }
        case 'spawn':
          value = __idris2_spawnChild(r.cmd, r.stdin, r.stdout)
          break
        case 'closePipe':
          __idris2_closeChildPipe(r.pid, r.which)
          break
        case 'wait':
          // answered when the child has exited
          __idris2_waitChild(r.pid, status => __idris2_rpcAnswer(shared, { ok: true, value: status }))
          return
      }
      __idris2_rpcAnswer(shared, { ok: true, value: value })
    } catch (e) {
      __idris2_rpcAnswer(shared, { ok: false, message: e.message, code: e.code, errno: e.errno })
    }
  })
  worker.on('error', e => {
    console.error(e)
    process.exitCode = 1
  })
  worker.on('exit', code => process.exit(code))
  return true
}

// Inside the worker: make it look like the main thread.
function __idris2_setUpWorker(wt) {
  const fs = require('fs')
  const data = wt.workerData
  const shared = data.__idris2Main
  const flag = new Int32Array(shared, 0, 2)

  const rpc = request => {
    Atomics.store(flag, 0, 0)
    wt.parentPort.postMessage({ __idris2Rpc: request })
    Atomics.wait(flag, 0, 0)
    const answer = JSON.parse(Buffer.from(shared, 8, flag[1]).toString('utf8'))
    if (!answer.ok) {
      const e = new Error(answer.message)
      e.code = answer.code
      e.errno = answer.errno
      throw e
    }
    return answer.value
  }
  __idris2_rpc = rpc

  // Synchronous output, in order with the writes of `fs.writeSync`.
  const syncWrite = (stream, fd, tty) => {
    stream.write = function (chunk, encoding, cb) {
      if (typeof encoding === 'function') { cb = encoding; encoding = undefined }
      const buf = typeof chunk === 'string' ? Buffer.from(chunk, encoding || 'utf8') : chunk
      let off = 0
      while (off < buf.length) {
        try {
          off += fs.writeSync(fd, buf, off, buf.length - off)
        } catch (e) {
          if (e.code !== 'EAGAIN') throw e
        }
      }
      if (typeof cb === 'function') process.nextTick(cb)
      return true
    }
    for (const k of ['isTTY', 'columns', 'rows'])
      if (tty[k] !== undefined) Object.defineProperty(stream, k, { value: tty[k], configurable: true })
  }
  syncWrite(process.stdout, 1, data.stdout)
  syncWrite(process.stderr, 2, data.stderr)

  process.chdir = dir => rpc({ op: 'chdir', dir: String(dir) })

  __idris2_signalWord = new Int32Array(data.signals)
  __idris2_controlSignal = (name, num, mode) =>
    rpc({ op: 'signal', signal: name, num: num, mode: mode })

  // `process.stdin` of a worker gets what the main thread writes to
  // `worker.stdin`; the main thread starts reading fd 0 for it only when the
  // program first looks at `process.stdin` (from then on, reading stdin
  // with getLine or fGetLine as well gets some of the input in each).
  const stdinDesc = Object.getOwnPropertyDescriptor(process, 'stdin')
  if (stdinDesc !== undefined && stdinDesc.configurable) {
    let asked = false
    Object.defineProperty(process, 'stdin', {
      configurable: true, enumerable: stdinDesc.enumerable,
      get() {
        const s = stdinDesc.get ? stdinDesc.get.call(process) : stdinDesc.value
        if (!asked) { asked = true; rpc({ op: 'stdin' }) }
        return s
      }
    })
  }

  // Signals reach the main thread only.  The worker's listeners run when the
  // worker's event loop does, as they would on the main thread.
  const isSignal = ev => typeof ev === 'string' && /^SIG[A-Z0-9]+$/.test(ev)
  const signals = new (require('events'))()
  const on = process.on, removeListener = process.removeListener,
        removeAll = process.removeAllListeners
  process.on = process.addListener = function (ev, h) {
    if (!isSignal(ev)) return on.call(this, ev, h)
    rpc({ op: 'listen', signal: ev })
    signals.on(ev, h)
    return this
  }
  process.removeListener = process.off = function (ev, h) {
    if (!isSignal(ev)) return removeListener.call(this, ev, h)
    signals.removeListener(ev, h)
    if (signals.listenerCount(ev) === 0) rpc({ op: 'unlisten', signal: ev })
    return this
  }
  process.removeAllListeners = function (ev) {
    if (!isSignal(ev)) return removeAll.apply(this, arguments)
    signals.removeAllListeners(ev)
    rpc({ op: 'unlisten', signal: ev })
    return this
  }
  wt.parentPort.on('message', m => {
    if (m !== null && typeof m === 'object' && m.__idris2Signal !== undefined)
      signals.emit(m.__idris2Signal, m.__idris2Signal)
  })
  wt.parentPort.unref()
}

// Run `main`: in a worker with a large stack if this file is the script that
// Node runs, on the current thread otherwise.
function __idris2_runMain(main) {
  let wt
  try { wt = require('worker_threads') } catch (e) { wt = undefined }
  if (wt !== undefined && !wt.isMainThread) {
    if (wt.workerData !== null && typeof wt.workerData === 'object'
          && wt.workerData.__idris2Main !== undefined)
      __idris2_setUpWorker(wt)
    return main()
  }
  const mb = __idris2_mainStackMb()
  if (wt === undefined || mb === 0 || typeof __filename !== 'string'
        || require.main !== module)
    return main()
  if (!__idris2_runInWorker(wt, mb)) return main()
}
