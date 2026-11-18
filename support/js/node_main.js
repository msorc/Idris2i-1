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
  // (only a terminal is looked at: `process.stdout` of a pipe would make the
  // pipe non-blocking)
  const tty = (fd, s) => require('tty').isatty(fd)
    ? { isTTY: true, columns: s().columns, rows: s().rows } : {}
  let worker
  try {
    worker = new wt.Worker(__filename, {
      argv: process.argv.slice(2),
      env: wt.SHARE_ENV,
      workerData: { __idris2Main: shared, stdout: tty(1, () => process.stdout),
                    stderr: tty(2, () => process.stderr) },
      resourceLimits: { stackSizeMb: mb }
    })
  } catch (e) {
    // No thread with a stack of this size: run on the main thread.
    return false
  }
  const listeners = new Map()
  worker.on('message', m => {
    if (m === null || typeof m !== 'object' || m.__idris2Rpc === undefined) return
    const r = m.__idris2Rpc
    try {
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
        case 'unlisten': {
          const h = listeners.get(r.signal)
          if (h !== undefined) process.removeListener(r.signal, h)
          listeners.delete(r.signal)
          break
        }
      }
      __idris2_rpcAnswer(shared, { ok: true })
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
  }

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
