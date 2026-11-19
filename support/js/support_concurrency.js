// Threads on the JavaScript back ends: `fork`, System.Concurrency and
// System.Future.
//
// A JavaScript program runs in one thread, and what runs in another thread
// (a Worker) shares no objects with it, so there is no way to run an Idris
// function, which is a closure over the heap, in a second thread.  `fork` and
// the futures of System.Future therefore stop the program with an error.
//
// With only one thread, the other primitives still have a meaning, and have
// it here: a mutex is a recursive lock that nobody else wants, a semaphore a
// counter, a channel a one-element queue, thread data a variable.  What
// would have to wait for a second thread to act (a `semaphoreWait` on a
// semaphore at zero, a `channelGet` on an empty channel, a `conditionWait`,
// a `barrierWait` for more threads than one) can never finish, and stops the
// program with an error instead of hanging.  The waits with a timeout wait
// for the timeout, as they do with no other thread in the program.

function support_concurrency_fatal(msg) {
  if (typeof process !== 'undefined' && process.stderr && process.exit) {
    process.stderr.write('Error: ' + msg + '\n')
    process.exit(1)
  }
  throw new IdrisError(msg)
}

function support_concurrency_noThreads(what) {
  support_concurrency_fatal(what + ': threads are not supported on the JavaScript back ends '
    + '(a JavaScript program has a single thread, which shares no heap with any other)')
}

function support_concurrency_wouldBlock(what, why) {
  support_concurrency_fatal(what + ' would wait forever: ' + why
    + ' (the JavaScript back ends have a single thread, so nothing else can run in the meantime)')
}

function support_concurrency_fork(_prog) {
  support_concurrency_noThreads('fork')
}

function support_concurrency_threadWait(_thread) {
  support_concurrency_noThreads('threadWait')
}

function support_concurrency_makeFuture(_ty, _thunk) {
  support_concurrency_noThreads('System.Future.fork')
}

function support_concurrency_awaitFuture(_ty, _future) {
  support_concurrency_noThreads('System.Future.await')
}

// Waits `ms` milliseconds (Atomics.wait does not run on the main thread of
// a browser: spin there).
function support_concurrency_sleepMs(ms) {
  if (!(ms > 0)) return
  try {
    Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)
  } catch (e) {
    const end = Date.now() + ms
    while (Date.now() < end) { }
  }
}

// Thread data and thread id: the one thread is thread 0.

let support_concurrency_threadData = undefined

function support_concurrency_setThreadData(_ty, value) {
  support_concurrency_threadData = value
}

function support_concurrency_getThreadData(_ty) {
  return support_concurrency_threadData
}

function support_concurrency_getThreadId() {
  return 0
}

// Mutexes are recursive: `count` is how many times the one thread has
// acquired it.

function support_concurrency_makeMutex() {
  return { count: 0 }
}

function support_concurrency_mutexAcquire(mutex) {
  mutex.count++
}

function support_concurrency_mutexRelease(mutex) {
  if (mutex.count === 0)
    support_concurrency_fatal('mutexRelease: the mutex is not held by the calling thread')
  mutex.count--
}

// Condition variables have no waiting threads.

function support_concurrency_makeCondition() {
  return { }
}

function support_concurrency_conditionWait(_cond, _mutex) {
  support_concurrency_wouldBlock('conditionWait', 'no other thread can signal the condition')
}

function support_concurrency_conditionWaitTimeout(_cond, _mutex, microseconds) {
  support_concurrency_sleepMs(microseconds / 1000)
}

function support_concurrency_conditionSignal(_cond) { }

function support_concurrency_conditionBroadcast(_cond) { }

// Semaphores

function support_concurrency_makeSemaphore(init) {
  return { count: init }
}

function support_concurrency_semaphorePost(sema) {
  sema.count++
}

function support_concurrency_semaphoreWait(sema) {
  if (sema.count <= 0)
    support_concurrency_wouldBlock('semaphoreWait', 'the semaphore is at zero and no other thread can post it')
  sema.count--
}

// Barriers: `waiting` threads have arrived of the `size` it needs.

function support_concurrency_makeBarrier(size) {
  return { size: size, waiting: 0 }
}

function support_concurrency_barrierWait(barrier) {
  barrier.waiting++
  if (barrier.waiting !== barrier.size)
    support_concurrency_wouldBlock('barrierWait', 'the barrier needs '
      + barrier.size + ' threads and no other thread can arrive')
}

// Channels hold at most one value, and a put waits until it has been taken.

function support_concurrency_makeChannel(_ty) {
  return { full: false, value: undefined }
}

function support_concurrency_channelPut(_ty, chan, value) {
  if (chan.full)
    support_concurrency_wouldBlock('channelPut', 'the channel is full and no other thread can take its value')
  chan.value = value
  chan.full = true
}

function support_concurrency_take(chan) {
  const v = chan.value
  chan.value = undefined
  chan.full = false
  return v
}

function support_concurrency_channelGet(_ty, chan) {
  if (!chan.full)
    support_concurrency_wouldBlock('channelGet', 'the channel is empty and no other thread can send to it')
  return support_concurrency_take(chan)
}

// A `Maybe`: Nothing is `{h: 0}`, Just x is `{a1: x}`.

function support_concurrency_channelGetNonBlocking(_ty, chan) {
  return chan.full ? { a1: support_concurrency_take(chan) } : { h: 0 }
}

function support_concurrency_channelGetWithTimeout(_ty, chan, milliseconds) {
  if (!chan.full) {
    support_concurrency_sleepMs(milliseconds)
    return { h: 0 }
  }
  return { a1: support_concurrency_take(chan) }
}
