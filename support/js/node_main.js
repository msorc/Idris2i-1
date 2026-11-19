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

// The child processes that System.File's popen and popen2 started, by
// process id: { child, status, waiters } for those that the main thread
// started (its event loop runs while `main` waits in its worker, and sees
// them exit), { statusFd } for those that a monitor process waits for when
// `main` runs on the main thread (see `__idris2_spawnMonitored`).
const __idris2_children = new Map()

function __idris2_signalNumber(name) {
  const n = require('os').constants.signals[name]
  return n === undefined ? 1 : n
}

// A pipe from public API: Node can make a pipe for a child process, but it
// hands it over as a stream, whose descriptor is not public (the descriptor
// is needed: the thread that runs `main` reads and writes it with `fs`, as
// any file).  So the pipe is a FIFO, made by the POSIX utility `mkfifo` (Node
// cannot make one) in a directory of its own, and opened at both ends with
// `fs.openSync`; then the FIFO and the directory are removed.  Opening an end
// of a FIFO blocks until the other end is open too, except to read with
// O_NONBLOCK: the first descriptor, which is closed again once the others are
// open, lets the other two be opened without waiting.  `r` and `w` are
// blocking descriptors (with O_CLOEXEC, as `fs` opens them all, so a child
// gets only those it is given).
function __idris2_makePipe() {
  const fs = require('fs')
  const dir = fs.mkdtempSync(require('path').join(require('os').tmpdir(), 'idris2-pipe-'))
  const path = require('path').join(dir, 'p')
  try {
    const made = require('child_process').spawnSync('mkfifo', ['-m', '600', path], { stdio: 'ignore' })
    if (made.error !== undefined || made.status !== 0) {
      const e = new Error('mkfifo ' + path + ' failed'
                          + (made.error !== undefined ? ': ' + made.error.message : ''))
      e.code = made.error !== undefined ? made.error.code : 'EIO'
      e.errno = made.error !== undefined ? made.error.errno : -5
      throw e
    }
    const c = fs.constants
    const opener = fs.openSync(path, c.O_RDONLY | c.O_NONBLOCK)
    try {
      const w = fs.openSync(path, c.O_WRONLY)
      const r = fs.openSync(path, c.O_RDONLY)
      return { r: r, w: w }
    } finally {
      fs.closeSync(opener)
    }
  } finally {
    try { fs.unlinkSync(path) } catch (e) {}
    try { fs.rmdirSync(dir) } catch (e) {}
  }
}

function __idris2_closeFds(fds) {
  for (const fd of fds) {
    try { require('fs').closeSync(fd) } catch (e) {}
  }
}

// The pipes of a child process `sh -c cmd` whose stdin and stdout are each a
// 'pipe' or 'inherit': the `stdio` of the child, the descriptors that the
// program keeps (-1 for what is inherited), and those that the parent closes
// once the child has them.
function __idris2_childPipes(stdin, stdout) {
  const p = { stdio: ['inherit', 'inherit'], in: -1, out: -1, childEnds: [] }
  try {
    if (stdin === 'pipe') {
      const i = __idris2_makePipe()
      p.stdio[0] = i.r; p.in = i.w; p.childEnds.push(i.r)
    }
    if (stdout === 'pipe') {
      const o = __idris2_makePipe()
      p.stdio[1] = o.w; p.out = o.r; p.childEnds.push(o.w)
    }
    return p
  } catch (e) {
    __idris2_closeFds(p.childEnds.concat([p.in, p.out].filter(fd => fd >= 0)))
    throw e
  }
}

function __idris2_spawnError() {
  const e = new Error('spawn /bin/sh ENOENT')
  e.code = 'ENOENT'
  e.errno = -2
  return e
}

// A child process `sh -c cmd` whose stdin and stdout are each a 'pipe' or
// 'inherit', started from the thread that runs `main`: the process id and
// the descriptors of the pipes for the program (-1 for what is inherited).
// The pipes are made here (so the descriptors are of this thread, which may
// close them; a worker thread warns when it closes one that another thread
// opened), and the child is started by the main thread or, when `main` runs
// there, by a monitor process (see below).
function __idris2_startChild(cmd, stdin, stdout) {
  const p = __idris2_childPipes(stdin, stdout)
  let pid
  try {
    pid = __idris2_rpc !== null
      ? __idris2_rpc({ op: 'spawn', cmd: cmd, stdio: p.stdio })
      : __idris2_spawnMonitored(cmd, p.stdio)
  } catch (e) {
    __idris2_closeFds([p.in, p.out].filter(fd => fd >= 0))
    throw e
  } finally {
    __idris2_closeFds(p.childEnds)
  }
  return { pid: pid, in: p.in, out: p.out }
}

// Starts `sh -c cmd` with the stdin and stdout `stdio` (descriptors or
// 'inherit'), on the main thread, whose event loop runs while `main` waits
// in its worker and sees the child exit.  Returns the process id.
function __idris2_spawnChild(cmd, stdio) {
  const child = require('child_process').spawn('/bin/sh', ['-c', cmd],
    { stdio: [stdio[0], stdio[1], 'inherit'] })
  child.on('error', () => {})
  if (child.pid === undefined) throw __idris2_spawnError()
  const entry = { child: child, status: null, waiters: [] }
  child.on('exit', (code, signal) => {
    entry.status = code !== null ? code : 128 + __idris2_signalNumber(signal)
    for (const w of entry.waiters) w(entry.status)
    entry.waiters = []
  })
  __idris2_children.set(child.pid, entry)
  return child.pid
}

// The same when `main` runs on the main thread (IDRIS2_MAIN_STACK_SIZE=0),
// whose event loop does not run until `main` returns, so it would not see
// the child exit: another process waits for it.  A shell started with
// `spawnSync` starts this monitor (a Node process) in the background and
// exits at once; the monitor, which init adopts, starts `sh -c cmd` with the
// pipes, closes its own copies of them (a child sees the end of its input
// once the program closes the pipe) and writes to the pipe on its
// descriptor 3 the process id of the child and then its exit status.  The
// child is started by libuv, which gives it the default action of every
// signal (the background shell ignores SIGINT and SIGQUIT).
const __idris2_monitorCode = `
const fs = require('fs')
const c = require('child_process').spawn('/bin/sh', ['-c', process.argv[1]], { stdio: [0, 1, 2] })
c.on('error', () => {})
try { fs.closeSync(0) } catch (e) {}
try { fs.closeSync(1) } catch (e) {}
fs.writeSync(3, (c.pid === undefined ? -1 : c.pid) + '\\n')
if (c.pid !== undefined)
  c.on('exit', (code, signal) => {
    const n = signal === null ? 1 : require('os').constants.signals[signal]
    fs.writeSync(3, (code !== null ? code : 128 + (n === undefined ? 1 : n)) + '\\n')
  })
`

// A line from a blocking descriptor, without the newline; null at its end
// before a newline.
function __idris2_readLine(fd) {
  const fs = require('fs')
  const b = Buffer.alloc(1)
  let line = ''
  for (;;) {
    let n
    try { n = fs.readSync(fd, b, 0, 1, null) }
    catch (e) { if (e.code === 'EAGAIN' || e.code === 'EINTR') continue; throw e }
    if (n === 0) return null
    if (b[0] === 10) return line
    line += String.fromCharCode(b[0])
  }
}

function __idris2_spawnMonitored(cmd, stdio) {
  const st = __idris2_makePipe()
  let r
  try {
    r = require('child_process').spawnSync('/bin/sh',
      ['-c', '"$0" -e "$1" -- "$2" <&0 &', process.execPath, __idris2_monitorCode, cmd],
      { stdio: [stdio[0], stdio[1], 'inherit', st.w] })
  } finally {
    __idris2_closeFds([st.w])
  }
  const pid = r.error === undefined && r.status === 0 ? Number(__idris2_readLine(st.r)) : -1
  if (!(pid > 0)) {
    __idris2_closeFds([st.r])
    throw __idris2_spawnError()
  }
  __idris2_children.set(pid, { status: null, statusFd: st.r })
  return pid
}

// The exit status of a child that `__idris2_spawnMonitored` started, once it
// has exited.
function __idris2_waitMonitored(pid) {
  const entry = __idris2_children.get(pid)
  if (entry === undefined || entry.statusFd === undefined) {
    const e = new Error('no child process ' + pid)
    e.code = 'ECHILD'
    throw e
  }
  __idris2_children.delete(pid)
  const line = __idris2_readLine(entry.statusFd)
  __idris2_closeFds([entry.statusFd])
  if (line === null) {
    const e = new Error('the monitor of child process ' + pid + ' exited first')
    e.code = 'ECHILD'
    throw e
  }
  return Number(line)
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
          value = __idris2_spawnChild(r.cmd, r.stdio)
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
