// System.Signal on Node.
//
// Node delivers signals to listeners on the main thread (`process.on`), from
// its event loop.  The program runs synchronously, so a listener on the
// thread that runs `main` would only run after `main` has returned.  So the
// listeners live on the main thread (see `__idris2i_1_setSignal` in
// node_main.js) and record a signal in a word of memory shared with the
// thread that runs `main`, where handleNextCollectedSignal reads it.
//
// When `main` runs in its worker thread (the default), the main thread is
// idle and records signals from other processes as they arrive.  When it
// runs on the main thread (IDRIS2I_1_MAIN_STACK_SIZE=0, or the program loaded
// as a module), such signals are only recorded when `main` has returned;
// ignoring a signal works in both cases, and so do the signals that the
// program raises itself, which are handled synchronously, as `raise` in C.

const support_system_signal_signals = require('os').constants.signals

// The numbers of the signals, -1 for those this platform does not have.
function support_system_signal_number(name) {
  const n = support_system_signal_signals[name]
  return n === undefined ? -1 : n
}

function support_system_signal_sighup() { return support_system_signal_number('SIGHUP') }
function support_system_signal_sigint() { return support_system_signal_number('SIGINT') }
function support_system_signal_sigquit() { return support_system_signal_number('SIGQUIT') }
function support_system_signal_sigill() { return support_system_signal_number('SIGILL') }
function support_system_signal_sigtrap() { return support_system_signal_number('SIGTRAP') }
function support_system_signal_sigabrt() { return support_system_signal_number('SIGABRT') }
function support_system_signal_sigfpe() { return support_system_signal_number('SIGFPE') }
function support_system_signal_sigusr1() { return support_system_signal_number('SIGUSR1') }
function support_system_signal_sigsegv() { return support_system_signal_number('SIGSEGV') }
function support_system_signal_sigusr2() { return support_system_signal_number('SIGUSR2') }

function support_system_signal_name(signal) {
  for (const name in support_system_signal_signals)
    if (support_system_signal_signals[name] === signal) return name
  return undefined
}

// What this program does with each signal, by number ('collect' or
// 'ignore'; absent for the default action).
const support_system_signal_modes = new Map()

function support_system_signal_set(signal, mode) {
  const name = support_system_signal_name(signal)
  // (the collected signals are bits of a 32 bit word, as in C)
  if (name === undefined || (mode === 'collect' && (signal < 0 || signal >= 32)))
    return -1
  try {
    __idris2i_1_controlSignal(name, signal, mode)
  } catch (e) {
    process.__lasterr = e
    return -1
  }
  if (mode === 'default') support_system_signal_modes.delete(signal)
  else support_system_signal_modes.set(signal, mode)
  return 0
}

function support_system_signal_ignoreSignal(signal) {
  return support_system_signal_set(signal, 'ignore')
}

function support_system_signal_defaultSignal(signal) {
  return support_system_signal_set(signal, 'default')
}

function support_system_signal_collectSignal(signal) {
  return support_system_signal_set(signal, 'collect')
}

// The lowest collected signal that arrived (and forget it), -1 if none.
function support_system_signal_handleNextCollectedSignal() {
  const bits = __idris2i_1_signalBits()
  for (;;) {
    const v = Atomics.load(bits, 0)
    if (v === 0) return -1
    const n = 31 - Math.clz32(v & -v)
    if (Atomics.compareExchange(bits, 0, v, v & ~(1 << n)) === v) return n
  }
}

function support_system_signal_raiseSignal(signal) {
  const name = support_system_signal_name(signal)
  if (name === undefined) return -1
  switch (support_system_signal_modes.get(signal)) {
    case 'collect':
      __idris2i_1_markSignal(signal)
      return 0
    case 'ignore':
      return 0
  }
  try {
    process.kill(process.pid, name)
    return 0
  } catch (e) {
    process.__lasterr = e
    return -1
  }
}

function support_system_signal_sendSignal(pid, signal) {
  if (pid === process.pid) return support_system_signal_raiseSignal(signal)
  const name = support_system_signal_name(signal)
  if (name === undefined) return -1
  try {
    process.kill(pid, name)
    return 0
  } catch (e) {
    process.__lasterr = e
    return -1
  }
}
