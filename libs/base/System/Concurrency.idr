||| Concurrency primitives, e.g. threads, mutexes, etc.
|||
||| N.B.: At the moment this is pretty fundamentally tied to the Scheme RTS.
||| Given that different back ends will have entirely different threading
||| models, it might be unavoidable, but we might want to think about possible
||| primitives that back ends should support.
|||
||| The RefC backend implements these in terms of green threads: user level
||| threads that run in parallel on a pool of OS threads (one per processor,
||| or `IDRIS2_WORKERS`).
|||
||| The JavaScript back ends have a single thread and no `fork`: `fork` and
||| `System.Future` stop the program with an error.  The other primitives work
||| as they do in a program without a second thread; those that would have to
||| wait for another thread (a `channelGet` on an empty channel, a
||| `semaphoreWait` at zero, a `conditionWait`) stop the program with an
||| error instead of hanging.
module System.Concurrency

import System.Info

%default total


-- Thread mailboxes

%foreign "scheme:blodwen-set-thread-data"
         "RefC:refc_setThreadData"
         "javascript:support:setThreadData,support_concurrency"
prim__setThreadData : {a : Type} -> a -> PrimIO ()
%foreign "scheme:blodwen-get-thread-data"
         "RefC:refc_getThreadData"
         "javascript:support:getThreadData,support_concurrency"
prim__getThreadData : (a : Type) -> PrimIO a
%foreign "scheme,chez:get-thread-id"
         "RefC:refc_getThreadId"
         "javascript:support:getThreadId,support_concurrency"
prim__getThreadId : PrimIO Int

||| Set the data stored in a thread's parameter to the given value.
||| Currently only supported under the scheme, RefC and JavaScript backends.
%spec hio
export
setThreadData : {auto hio : HasIO io} -> {a : Type} -> a -> io ()
setThreadData val = primIO (prim__setThreadData val)

||| Get the data stored in a thread's parameter.
||| Currently only supported under the scheme, RefC and JavaScript backends.
%spec hio
export
getThreadData : {auto hio : HasIO io} -> (a : Type) -> io a
getThreadData a = primIO (prim__getThreadData a)

||| Get the thread id of the current thread (chez backend).
%spec hio
export
getThreadId : {auto hio : HasIO io} -> io Int
getThreadId = primIO prim__getThreadId


-- Mutexes

export
data Mutex : Type where [external]

%foreign "scheme:blodwen-make-mutex"
         "RefC:refc_makeMutex"
         "javascript:support:makeMutex,support_concurrency"
prim__makeMutex : PrimIO Mutex
%foreign "scheme:blodwen-mutex-acquire"
         "RefC:refc_mutexAcquire"
         "javascript:support:mutexAcquire,support_concurrency"
prim__mutexAcquire : Mutex -> PrimIO ()
%foreign "scheme:blodwen-mutex-release"
         "RefC:refc_mutexRelease"
         "javascript:support:mutexRelease,support_concurrency"
prim__mutexRelease : Mutex -> PrimIO ()

||| Creates and returns a new mutex.
%spec hio
export
makeMutex : {auto hio : HasIO io} -> io Mutex
makeMutex = primIO prim__makeMutex

||| Acquires the mutex identified by `mutex`. The thread blocks until the mutex
||| has been acquired.
|||
||| Mutexes are recursive in Posix threads terminology, which means that the
||| calling thread can use mutex-acquire to (re)acquire a mutex it already has.
||| In this case, an equal number of mutex-release calls is necessary to release
||| the mutex.
%spec hio
export
mutexAcquire : {auto hio : HasIO io} -> Mutex -> io ()
mutexAcquire m = primIO (prim__mutexAcquire m)

||| Releases the mutex identified by `mutex`. Unpredictable behavior results if
||| the mutex is not owned by the calling thread.
%spec hio
export
mutexRelease : {auto hio : HasIO io} -> Mutex -> io ()
mutexRelease m = primIO (prim__mutexRelease m)


-- Condition variables

export
data Condition : Type where [external]

%foreign "scheme,racket:blodwen-make-cv"
         "scheme,chez:blodwen-make-condition"
         "RefC:refc_makeCondition"
         "javascript:support:makeCondition,support_concurrency"
prim__makeCondition : PrimIO Condition
%foreign "scheme,racket:blodwen-cv-wait"
         "scheme,chez:blodwen-condition-wait"
         "RefC:refc_conditionWait"
         "javascript:support:conditionWait,support_concurrency"
prim__conditionWait : Condition -> Mutex -> PrimIO ()
%foreign "scheme,chez:blodwen-condition-wait-timeout"
--         "scheme,racket:blodwen-cv-wait-timeout"
         "RefC:refc_conditionWaitTimeout"
         "javascript:support:conditionWaitTimeout,support_concurrency"
prim__conditionWaitTimeout : Condition -> Mutex -> Int -> PrimIO ()
%foreign "scheme,racket:blodwen-cv-signal"
         "scheme,chez:blodwen-condition-signal"
         "RefC:refc_conditionSignal"
         "javascript:support:conditionSignal,support_concurrency"
prim__conditionSignal : Condition -> PrimIO ()
%foreign "scheme,racket:blodwen-cv-broadcast"
         "scheme,chez:blodwen-condition-broadcast"
         "RefC:refc_conditionBroadcast"
         "javascript:support:conditionBroadcast,support_concurrency"
prim__conditionBroadcast : Condition -> PrimIO ()


||| Creates and returns a new condition variable.
%spec hio
export
makeCondition : {auto hio : HasIO io} -> io Condition
makeCondition = primIO prim__makeCondition

||| Waits up to the specified timeout for the condition identified by the
||| condition variable `cond`. The calling thread must have acquired the mutex
||| identified by `mutex` at the time `conditionWait` is called. The mutex is
||| released as a side effect of the call to `conditionWait`. When a thread is
||| later released from the condition variable by one of the procedures
||| described below, the mutex is reacquired and `conditionWait` returns.
%spec hio
export
conditionWait : {auto hio : HasIO io} -> Condition -> Mutex -> io ()
conditionWait cond mutex = primIO (prim__conditionWait cond mutex)

||| Variant of `conditionWait` with a timeout in microseconds.
||| When the timeout expires, the thread is released, `mutex` is reacquired, and
||| `conditionWaitTimeout` returns.
%spec hio
export
conditionWaitTimeout : {auto hio : HasIO io} -> Condition -> Mutex -> Int -> io ()
conditionWaitTimeout cond mutex timeout = primIO (prim__conditionWaitTimeout cond mutex timeout)

||| Releases one of the threads waiting for the condition identified by `cond`.
%spec hio
export
conditionSignal : {auto hio : HasIO io} -> Condition -> io ()
conditionSignal c = primIO (prim__conditionSignal c)

||| Releases all of the threads waiting for the condition identified by `cond`.
%spec hio
export
conditionBroadcast : {auto hio : HasIO io} -> Condition -> io ()
conditionBroadcast c = primIO (prim__conditionBroadcast c)


-- Semaphores

export
data Semaphore : Type where [external]

%foreign "scheme:blodwen-make-semaphore"
         "RefC:refc_makeSemaphore"
         "javascript:support:makeSemaphore,support_concurrency"
prim__makeSemaphore : Int -> PrimIO Semaphore
%foreign "scheme:blodwen-semaphore-post"
         "RefC:refc_semaphorePost"
         "javascript:support:semaphorePost,support_concurrency"
prim__semaphorePost : Semaphore -> PrimIO ()
%foreign "scheme:blodwen-semaphore-wait"
         "RefC:refc_semaphoreWait"
         "javascript:support:semaphoreWait,support_concurrency"
prim__semaphoreWait : Semaphore -> PrimIO ()


||| Creates and returns a new semaphore with the counter initially set to `init`.
%spec hio
export
makeSemaphore : {auto hio : HasIO io} -> Int -> io Semaphore
makeSemaphore init = primIO (prim__makeSemaphore init)

||| Increments the semaphore's internal counter.
%spec hio
export
semaphorePost : {auto hio : HasIO io} -> Semaphore -> io ()
semaphorePost sema = primIO (prim__semaphorePost sema)

||| Blocks until the internal counter for semaphore sema is non-zero. When the
||| counter is non-zero, it is decremented and `semaphoreWait` returns.
%spec hio
export
semaphoreWait : {auto hio : HasIO io} -> Semaphore -> io ()
semaphoreWait sema = primIO (prim__semaphoreWait sema)


-- Barriers

||| A barrier enables multiple threads to synchronize the beginning of some
||| computation.
export
data Barrier : Type where [external]

%foreign "scheme:blodwen-make-barrier"
         "RefC:refc_makeBarrier"
         "javascript:support:makeBarrier,support_concurrency"
prim__makeBarrier : Int -> PrimIO Barrier
%foreign "scheme:blodwen-barrier-wait"
         "RefC:refc_barrierWait"
         "javascript:support:barrierWait,support_concurrency"
prim__barrierWait : Barrier -> PrimIO ()

||| Creates a new barrier that can block a given number of threads.
|||
||| @ numThreads the number of threads to block
%spec hio
export
makeBarrier : {auto hio : HasIO io} -> (numThreads : Int) -> io Barrier
makeBarrier numThreads = primIO (prim__makeBarrier numThreads)

||| Blocks the current thread until all threads have rendezvoused here.
%spec hio
export
barrierWait : {auto hio : HasIO io} -> Barrier -> io ()
barrierWait barrier = primIO (prim__barrierWait barrier)


-- Channels

export
data Channel : Type -> Type where [external]

%foreign "scheme:blodwen-make-channel"
         "RefC:refc_makeChannel"
         "javascript:support:makeChannel,support_concurrency"
prim__makeChannel : PrimIO (Channel a)
%foreign "scheme:blodwen-channel-get"
         "RefC:refc_channelGet"
         "javascript:support:channelGet,support_concurrency"
prim__channelGet : Channel a -> PrimIO a
%foreign "scheme,chez:blodwen-channel-get-non-blocking"
         "RefC:refc_channelGetNonBlocking"
         "javascript:support:channelGetNonBlocking,support_concurrency"
prim__channelGetNonBlocking : Channel a -> PrimIO (Maybe a)
%foreign "scheme,chez:blodwen-channel-get-with-timeout"
         "RefC:refc_channelGetWithTimeout"
         "javascript:support:channelGetWithTimeout,support_concurrency"
prim__channelGetWithTimeout : Channel a -> Int -> PrimIO (Maybe a)
%foreign "scheme:blodwen-channel-put"
         "RefC:refc_channelPut"
         "javascript:support:channelPut,support_concurrency"
prim__channelPut : Channel a -> a -> PrimIO ()

||| Creates and returns a new `Channel`.
|||
||| The channel can be used with `channelGet` to receive a value through the
||| channel.
||| The channel can be used with `channelPut` to send a value through the
||| channel.
%spec hio
export
makeChannel : {auto hio : HasIO io} -> io (Channel a)
makeChannel = primIO prim__makeChannel

||| Blocks until a sender is ready to provide a value through `chan`. The result
||| is the sent value.
|||
||| @ chan the channel to receive on
%spec hio
export
channelGet : {auto hio : HasIO io} -> (chan : Channel a) -> io a
channelGet chan = primIO (prim__channelGet chan)

||| Non-blocking version of channelGet (chez backend).
|||
||| @ chan the channel to receive on
%spec hio
partial
export
channelGetNonBlocking : {auto hio : HasIO io} -> (chan : Channel a) -> io (Maybe a)
channelGetNonBlocking chan = primIO (prim__channelGetNonBlocking chan)

||| Timeout version of channelGet (chez backend).
||| Clamps minimum timeout to 25 ms on windows.
|||
||| @ chan the channel to receive on
||| @ milliseconds how many milliseconds to wait until timeout
%spec hio
partial
export
channelGetWithTimeout : {auto hio : HasIO io} -> (chan : Channel a) -> (milliseconds : Nat) -> io (Maybe a)
channelGetWithTimeout chan milliseconds =
  case os of
    "windows" =>
      let clampedms = if milliseconds > 25 then cast milliseconds else 25
        in primIO (prim__channelGetWithTimeout chan clampedms)
    _         =>
      primIO (prim__channelGetWithTimeout chan (cast milliseconds))

||| Puts a value on the given channel.
|||
||| @ chan the `Channel` to send the value over
||| @ val  the value to send
%spec hio
export
channelPut : {auto hio : HasIO io} -> (chan : Channel a) -> (val : a) -> io ()
channelPut chan val = primIO (prim__channelPut chan val)
