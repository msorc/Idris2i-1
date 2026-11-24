const support_system_file_fs = require('fs')

// See System/File/Error.idr for return values
function support_system_file_fileErrno(){
  const n = process.__lasterr===undefined?0:process.__lasterr.errno || 0
  if (process.platform == 'win32') {
    switch(n) {
      // these are documented in include/uv/errno.h of libuv
      case -4058: return 2
      case -4048: return 3
      case -4075: return 4
      default: return -n + 5
    }
  } else {
    switch(n){
      case -2: return 2
      case -13: return 3
      case -17: return 4
      default: return -n + 5
    }
  }
}

// A file is an object { fd, buffer, name, eof }, plus `err` once a read or a
// write failed (`ferror`) and `chunked` when it may be read ahead.
//
// Reads go through `buffer`, the bytes read from `fd` and not consumed yet.
// Only a file that `openFile` opened for reading only, and that is a regular
// file, is read in chunks: everything else (stdin, pipes, terminals, files
// open for writing too) is read a byte at a time, so that no byte is taken
// from the descriptor before it is consumed (a child process that inherits
// stdin, or a write to a file open for reading and writing, sees the same
// position as with C).

const support_system_file_chunkSize = 65536

// stdin, stdout and stderr: one object each, so that what one read leaves in
// the buffer and the end-of-file indicator are seen by the next.
const support_system_file_stdinFile =
  { fd: 0, buffer: Buffer.alloc(0), name: '<stdin>', eof: false }
const support_system_file_stdoutFile =
  { fd: 1, buffer: Buffer.alloc(0), name: '<stdout>', eof: false }
const support_system_file_stderrFile =
  { fd: 2, buffer: Buffer.alloc(0), name: '<stderr>', eof: false }

function support_system_file_stdin() { return support_system_file_stdinFile }
function support_system_file_stdout() { return support_system_file_stdoutFile }
function support_system_file_stderr() { return support_system_file_stderrFile }

// Waits a millisecond (when a descriptor that is not blocking has no data).
function support_system_file_pause() {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 1)
}

// `readSync` into `buf` at `off`, at most `len` bytes: the number of bytes
// read, 0 at the end of the input, -1 on an error (the error is recorded).
// Once the end has been seen, it stays (as with stdio in C: on a terminal,
// a read after a ^D does not wait for more input).
function support_system_file_readRaw(file_ptr, buf, off, len) {
  if (file_ptr.eof) return 0
  for (;;) {
    try {
      return support_system_file_fs.readSync(file_ptr.fd, buf, off, len, null)
    } catch (e) {
      if (e.code === 'EAGAIN') { support_system_file_pause(); continue }
      // (a terminal at its end on Windows)
      if (e.code === 'EOF') return 0
      process.__lasterr = e
      file_ptr.err = true
      return -1
    }
  }
}

// Makes the buffer hold at least one byte more than `have` bytes: false at the
// end of the input or on an error (then `eof` or `err` is set).
function support_system_file_fill(file_ptr, have) {
  const n = file_ptr.chunked ? support_system_file_chunkSize : 1
  const more = Buffer.allocUnsafe(n)
  const got = support_system_file_readRaw(file_ptr, more, 0, n)
  if (got <= 0) {
    if (got === 0) file_ptr.eof = true
    return false
  }
  file_ptr.buffer = have === 0 && file_ptr.buffer.length === 0
    ? more.subarray(0, got)
    : Buffer.concat([file_ptr.buffer, more.subarray(0, got)])
  return true
}

// The bytes up to and including the next newline (or up to the end of the
// input), taken out of the buffer: null if there are none.
function support_system_file_takeLine(file_ptr) {
  const LF = 0x0a
  let from = 0
  let lineEnd = file_ptr.buffer.indexOf(LF)
  if (lineEnd === -1 && !file_ptr.chunked) {
    // A byte at a time: collect them in a growing buffer (not with a concat
    // per byte, which is quadratic in the length of the line).
    let acc = Buffer.allocUnsafe(Math.max(64, file_ptr.buffer.length * 2))
    let len = file_ptr.buffer.copy(acc, 0)
    file_ptr.buffer = Buffer.alloc(0)
    for (;;) {
      if (len === acc.length) {
        const bigger = Buffer.allocUnsafe(acc.length * 2)
        acc.copy(bigger, 0, 0, len)
        acc = bigger
      }
      const got = support_system_file_readRaw(file_ptr, acc, len, 1)
      if (got <= 0) {
        if (got === 0) file_ptr.eof = true
        return len === 0 ? null : acc.subarray(0, len)
      }
      len++
      if (acc[len - 1] === LF) return acc.subarray(0, len)
    }
  }
  while (lineEnd === -1) {
    from = file_ptr.buffer.length
    if (!support_system_file_fill(file_ptr, from)) {
      const rest = file_ptr.buffer
      file_ptr.buffer = Buffer.alloc(0)
      return rest.length === 0 ? null : rest
    }
    lineEnd = file_ptr.buffer.indexOf(LF, from)
  }
  const line = file_ptr.buffer.subarray(0, lineEnd + 1)
  file_ptr.buffer = file_ptr.buffer.subarray(lineEnd + 1)
  return line
}

// like `readLine` without the overhead of copying characters.
// returns int (success 0, failure -1) to align with the C counterpart.
function support_system_file_seekLine (file_ptr) {
  support_system_file_takeLine(file_ptr)
  return file_ptr.err ? -1 : 0
}

// The next line, with its newline; null at the end of the input (with
// nothing read) or on an error, as `idris2i_1_readLine` in C.
function support_system_file_readLine (file_ptr) {
  const line = support_system_file_takeLine(file_ptr)
  return line === null ? null : line.toString('utf-8')
}

// At most `max` bytes (fewer only at the end of the input), as a string;
// null if none could be read, as `idris2i_1_readChars` in C.
function support_system_file_readChars (max, file_ptr) {
  const parts = []
  let len = 0
  while (len < max) {
    if (file_ptr.buffer.length === 0 && !support_system_file_fill(file_ptr, 0)) break
    const n = Math.min(max - len, file_ptr.buffer.length)
    parts.push(file_ptr.buffer.subarray(0, n))
    file_ptr.buffer = file_ptr.buffer.subarray(n)
    len += n
  }
  return len === 0 ? null : Buffer.concat(parts, len).toString('utf-8')
}

// The next byte, -1 at the end of the input or on an error (`fgetc`).
function support_system_file_readChar (file_ptr) {
  if (file_ptr.buffer.length === 0 && !support_system_file_fill(file_ptr, 0)) return -1
  const c = file_ptr.buffer[0]
  file_ptr.buffer = file_ptr.buffer.subarray(1)
  return c
}

// `fread` into a Buffer: the bytes that were read ahead come first.
function support_system_file_readBufferData (file_ptr, buf, off, max) {
  let len = 0
  if (file_ptr.buffer.length > 0) {
    len = file_ptr.buffer.copy(buf, off, 0, Math.min(max, file_ptr.buffer.length))
    file_ptr.buffer = file_ptr.buffer.subarray(len)
  }
  while (len < max) {
    const got = support_system_file_readRaw(file_ptr, buf, off + len, max - len)
    if (got <= 0) {
      if (got === 0) file_ptr.eof = true
      break
    }
    len += got
  }
  return len === 0 && file_ptr.err ? -1 : len
}

function support_system_file_writeBufferData (file_ptr, buf, off, len) {
  try {
    let done = 0
    while (done < len) {
      try {
        done += support_system_file_fs.writeSync(file_ptr.fd, buf, off + done, len - done)
      } catch (e) {
        if (e.code !== 'EAGAIN') throw e
        support_system_file_pause()
      }
    }
    return done
  } catch (e) {
    process.__lasterr = e
    file_ptr.err = true
    return 0
  }
}

// 1 on success, 0 on an error, as `idris2i_1_writeLine` in C.
function support_system_file_writeLine (file_ptr, str) {
  const buf = Buffer.from(str, 'utf-8')
  return support_system_file_writeBufferData(file_ptr, buf, 0, buf.length) === buf.length ? 1 : 0
}

// A line of stdin without its line terminator, "" at the end of the input:
// as `idris2i_1_getStr` in C, which cuts the line at the first '\r' or '\n'.
function support_system_file_getStr () {
  const line = support_system_file_readLine(support_system_file_stdinFile)
  if (line === null) return ''
  const m = line.search(/[\r\n]/)
  return m === -1 ? line : line.slice(0, m)
}

// The next byte of stdin as a character, as `getchar` in C (which returns
// -1 at the end of the input).
function support_system_file_getChar() {
  return String.fromCharCode(support_system_file_readChar(support_system_file_stdinFile))
}

function support_system_file_parseMode(mode) {
  return mode.replace('b', '')
}

function support_system_file_openFile (n, m) {
  try {
    const mode = support_system_file_parseMode(m)
    const fd = support_system_file_fs.openSync(n, mode)
    const chunked = mode === 'r' && support_system_file_fs.fstatSync(fd).isFile()
    return { fd: fd, buffer: Buffer.alloc(0), name: n, eof: false, chunked: chunked }
  } catch (e) {
    process.__lasterr = e
    return null
  }
}

function support_system_file_chmod (filename, mode) {
  try {
    support_system_file_fs.chmodSync(filename, mode)
    return 0
  } catch (e) {
    process.__lasterr = e
    return 1
  }
}

function support_system_file_removeFile (filename) {
  try {
    support_system_file_fs.unlinkSync(filename)
    return 0
  } catch (e) {
    process.__lasterr = e
    return 1
  }
}

// Child processes: popen, pclose and popen2.
//
// The pipes are FIFOs that the program opened itself (see `__idris2i_1_makePipe`
// in node_main.js), which the thread that runs `main` reads and writes with
// `readSync` and `writeSync`, like any file.  So the child runs at the same
// time as the program and the pipes behave as in C: the child blocks when
// the pipe is full, and the program when it reads an empty one.  The child
// is started by the main thread, whose event loop runs while `main` waits in
// its worker and sees the child exit (see `__idris2i_1_spawnChild`); when `main`
// runs on the main thread (IDRIS2I_1_MAIN_STACK_SIZE=0), by a monitor process
// that waits for it and passes its exit status on through a pipe (see
// `__idris2i_1_spawnMonitored`).
//
// A file that is a pipe has `child` (the process id).

function support_system_file_fatal(msg) {
  process.stderr.write('Error: ' + msg + '\n')
  process.exit(1)
}

function support_system_file_pipeFile(fd, name, child, pipe) {
  return { fd: fd, buffer: Buffer.alloc(0), name: name, eof: false,
           chunked: pipe === 'out', child: child }
}

// The child that `sh -c cmd` starts, with a pipe to its stdin and/or from its
// stdout; null (and `lasterr`) if it could not be started.
function support_system_file_spawnChild(cmd, stdin, stdout) {
  try {
    return __idris2i_1_startChild(cmd, stdin, stdout)
  } catch (e) {
    process.__lasterr = e
    return null
  }
}

function support_system_file_popen (cmd, m) {
  const mode = support_system_file_parseMode(m)
  if (mode !== 'r' && mode !== 'w') {
    // C's popen fails with EINVAL for any other mode
    process.__lasterr = { errno: -require('os').constants.errno.EINVAL }
    return null
  }
  const reading = mode === 'r'
  const c = support_system_file_spawnChild(cmd, reading ? 'inherit' : 'pipe', reading ? 'pipe' : 'inherit')
  if (c === null) return null
  return support_system_file_pipeFile(reading ? c.out : c.in, cmd, c.pid, reading ? 'out' : 'in')
}

// Closes the descriptor of a file (once: a pipe of popen2 can be closed by
// the program, and again when it waits).
function support_system_file_close (file_ptr) {
  if (file_ptr.child !== undefined) {
    if (!file_ptr.closed) support_system_file_fs.closeSync(file_ptr.fd)
    file_ptr.closed = true
    return
  }
  support_system_file_fs.closeSync(file_ptr.fd)
}

// The exit status of the child once it has exited (the same as `system`:
// 128 + the signal that killed it).
function support_system_file_waitChild (pid) {
  try {
    if (__idris2i_1_rpc === null) return __idris2i_1_waitMonitored(pid)
    return __idris2i_1_rpc({ op: 'wait', pid: pid })
  } catch (e) {
    process.__lasterr = e
    return -1
  }
}

function support_system_file_pclose (file_ptr) {
  support_system_file_close(file_ptr)
  return support_system_file_waitChild(file_ptr.child)
}

// A subprocess: { pid, in, out }, where `in` is the file that the program
// writes (the child's stdin) and `out` the file that it reads.
function support_system_file_popen2 (cmd) {
  const c = support_system_file_spawnChild(cmd, 'pipe', 'pipe')
  if (c === null) return null
  return { pid: c.pid,
           in: support_system_file_pipeFile(c.in, cmd, c.pid, 'in'),
           out: support_system_file_pipeFile(c.out, cmd, c.pid, 'out') }
}

function support_system_file_popen2ChildPid (p) { return p.pid }

// (only Windows has a handler to wait with)
function support_system_file_popen2ChildHandler (p) { return null }

function support_system_file_popen2FileIn (p) { return p.in }

function support_system_file_popen2FileOut (p) { return p.out }

function support_system_file_popen2WaitByPid (pid) {
  return support_system_file_waitChild(pid)
}

function support_system_file_popen2WaitByHandler (handler) {
  support_system_file_fatal('popen2Wait: there is no process handler on this platform')
}

function support_system_file_filetime(file_ptr) {
  const {fd, name, exit_code} = file_ptr
  const st = support_system_file_fs.fstatSync(fd)
  const ft = {
    atime_sec : _truncInt32(Math.trunc(st.atimeMs / 1000)),
    atime_nsec : st.atimeMs * 1000000 % 1000000000,
    mtime_sec : _truncInt32(Math.trunc(st.mtimeMs / 1000)),
    mtime_nsec : st.mtimeMs * 1000000 % 1000000000,
    ctime_sec : _truncInt32(Math.trunc(st.ctimeMs / 1000)),
    ctime_nsec : st.mtimeMs * 1000000 % 1000000000
  };
  return ft
}
