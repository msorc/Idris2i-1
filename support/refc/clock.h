#pragma once

#include <time.h>

#include "cBackend.h"

Idris2i_1_Value *clockTimeMonotonic();
Idris2i_1_Value *clockTimeUtc();
Idris2i_1_Value *clockTimeProcess();
Idris2i_1_Value *clockTimeThread();
Idris2i_1_Value *clockTimeGcCpu();
Idris2i_1_Value *clockTimeGcReal();

int clockValid(Idris2i_1_Value *clock);
uint64_t clockSecond(Idris2i_1_Value *clock);
uint64_t clockNanosecond(Idris2i_1_Value *clock);
