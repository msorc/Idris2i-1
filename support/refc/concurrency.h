#pragma once

#include "_datatypes.h"

#include <stdint.h>

// ---------------------------------------------------------------------------
// Synchronisation primitives for the RefC backend.
//
// These are implemented in terms of green threads (see threads.h) rather than
// in terms of OS threads, so that they cooperate with the RefC scheduler.
//
// Note that the type arguments of the external data types (the element type
// of a channel, for instance) are erased, but they are still passed to the
// FFI functions, so they appear as an extra leading argument.
// ---------------------------------------------------------------------------

// Mutexes

void *refc_makeMutex(void);
void refc_mutexAcquire(Idris2_Value *mutex);
void refc_mutexRelease(Idris2_Value *mutex);

// Condition variables

void *refc_makeCondition(void);
void refc_conditionWait(Idris2_Value *condition, Idris2_Value *mutex);
void refc_conditionWaitTimeout(Idris2_Value *condition, Idris2_Value *mutex,
                                int64_t timeout_us);
void refc_conditionSignal(Idris2_Value *condition);
void refc_conditionBroadcast(Idris2_Value *condition);

// Semaphores

void *refc_makeSemaphore(int64_t count);
void refc_semaphorePost(Idris2_Value *semaphore);
void refc_semaphoreWait(Idris2_Value *semaphore);

// Barriers

void *refc_makeBarrier(int64_t num_threads);
void refc_barrierWait(Idris2_Value *barrier);

// Channels

void *refc_makeChannel(Idris2_Value *erased);
void *refc_channelGet(Idris2_Value *erased, Idris2_Value *channel);
void *refc_channelGetNonBlocking(Idris2_Value *erased, Idris2_Value *channel);
void *refc_channelGetWithTimeout(Idris2_Value *erased, Idris2_Value *channel,
                                 int64_t timeout_ms);
void refc_channelPut(Idris2_Value *erased, Idris2_Value *channel,
                     Idris2_Value *value);

// Thread local data

int64_t refc_getThreadId(void);
void refc_setThreadData(Idris2_Value *erased, Idris2_Value *value);
void *refc_getThreadData(Idris2_Value *erased);

// Sleeping.  Unlike the system calls, these do not block the other green
// threads.

void refc_sleep(int64_t seconds);
void refc_usleep(int64_t microseconds);
