const support_system_child_process = require('child_process')
const support_system_os = require('os')

// The exit status of `cmd` as a shell reports it, as `idris2_system` of the
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
