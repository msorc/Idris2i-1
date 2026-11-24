const support_system_child_process = require('child_process')
const support_system_os = require('os')

// The exit status of `cmd` as a shell reports it, as `idris2i_1_system` of the
// C support library: the exit code when it exited, 128 + the number of the
// signal when it was killed by one, -1 when it could not be run.
function support_system_spawnSync(cmd) {
  const options = { shell: true, stdio: 'inherit' }
  const { status, signal, error } =
    support_system_child_process.spawnSync(cmd, [], options)
  if (error !== undefined) {
    return -1
  }
  if (status !== null) {
    return status
  }
  const signum = support_system_os.constants.signals[signal]
  return signum === undefined ? -1 : 128 + signum
}

// call with overwrite == 0 to avoid overwriting an existing variable.
function support_system_setEnv(name, value, overwrite) {
  if (overwrite == 0 && process.env[name]) {
    return 0
  }
  process.env[name] = value
  return 0
}

function support_system_unsetEnv(name) {
  delete process.env[name]
  return 0
}

function support_system_getErrno() {
  return process.__lasterr === undefined ? 0 : -process.__lasterr.errno || 0
}

// Sleeping blocks the thread (Atomics.wait works on the main thread of Node
// too).  With `main` in its worker thread, a signal that System.Signal
// collects wakes the sleep up, as it interrupts `sleep` in C.
function support_system_sleepMs(ms) {
  const bits = __idris2i_1_signalBits()
  const t0 = Date.now()
  let left = ms
  const seen = Atomics.load(bits, 0)
  while (left > 0) {
    if (Atomics.wait(bits, 0, seen, left) !== 'timed-out') return
    left = ms - (Date.now() - t0)
  }
}

function support_system_sleep(sec) {
  support_system_sleepMs(sec * 1000)
}

function support_system_usleep(usec) {
  support_system_sleepMs(usec / 1000)
}

// The environment variable number `i` as "NAME=value", null after the last.
function support_system_getEnvPair(i) {
  const keys = Object.keys(process.env)
  return i < keys.length ? keys[i] + '=' + process.env[keys[i]] : null
}

// Raw mode of the terminal on stdin, with stty (which works on the main
// thread and in a worker alike): echo and canonical mode off, as in C.
let support_system_initialStty = null

function support_system_stty(args) {
  return support_system_child_process.spawnSync('stty', args,
    { stdio: [0, 'pipe', 'pipe'], encoding: 'utf8' })
}

function support_system_enableRawMode() {
  if (process.platform === 'win32') return -1
  if (!require('tty').isatty(0)) {
    process.__lasterr = { errno: -support_system_os.constants.errno.ENOTTY }
    return -1
  }
  if (support_system_initialStty === null) {
    const r = support_system_stty(['-g'])
    if (r.error !== undefined || r.status !== 0) return -1
    support_system_initialStty = r.stdout.trim()
  }
  const r = support_system_stty(['-echo', '-icanon'])
  return r.error === undefined && r.status === 0 ? 0 : -1
}

function support_system_resetRawMode() {
  if (support_system_initialStty !== null)
    support_system_stty([support_system_initialStty])
}

function support_system_strerror(errno) {
  const util = require('util')
  try {
    if (typeof util.getSystemErrorMessage === 'function')
      return util.getSystemErrorMessage(-errno)
  } catch (e) { }
  return 'Error code: ' + errno
}
