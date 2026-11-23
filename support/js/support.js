class IdrisError extends Error { }

function __prim_js2idris_array(x){
  let acc = { h:0 };

  for (let i = x.length-1; i>=0; i--) {
      acc = { a1:x[i], a2:acc };
  }
  return acc;
}

function __prim_idris2js_array(x){
  const result = Array();
  while (x.h === undefined) {
    result.push(x.a1); x = x.a2;
  }
  return result;
}

// The trampoline for the tail calls to unknown functions (see
// Compiler.ES.TailRec).  Such a call is made directly while there are fewer
// than 64 of them on the stack above the nearest caller that needs a value
// (`__res`); beyond that, it returns a pending call instead, which unwinds
// the stack up to that caller, where it is run.
//
// A pending call must never reach JavaScript code, which would take it for
// the value.  So the calls are counted only where every caller up to the one
// that runs the pending calls is Idris code: in `main` and in the functions
// given to foreign code (`__resFn`).  Elsewhere, outside Idris code and in
// the calls of foreign functions (see `wrapForeign` in Compiler.ES.Codegen),
// the count is `__tcNone`, from which it never gets to 64: an Idris function
// that JavaScript calls there (a closure that reached it in an `AnyPtr` or in
// a record, a %nomangle function, ...) makes all its tail calls directly.
//
// Where the count is set, it is restored when the call returns, but not
// when an exception goes through (nor do `__tcN` and `__res` restore it then,
// which would cost on every call): an exception is caught by JavaScript code,
// so in a call of a foreign function, which restores the count as it
// returns, in the caller of a function given to foreign code, whose wrapper
// restores it in a `finally` (`__resCall`), or outside Idris code, where the
// `__resCall` that ran `main` or the callback restored it.
class __TC { }
class __TC0 extends __TC {
  constructor(f) { super(); this.f = f }
  run() { return this.f() }
}
class __TC1 extends __TC {
  constructor(f, a) { super(); this.f = f; this.a = a }
  run() { return this.f(this.a) }
}
class __TC2 extends __TC {
  constructor(f, a, b) { super(); this.f = f; this.a = a; this.b = b }
  run() { return this.f(this.a, this.b) }
}
class __TC3 extends __TC {
  constructor(f, a, b, c) { super(); this.f = f; this.a = a; this.b = b; this.c = c }
  run() { return this.f(this.a, this.b, this.c) }
}
class __TCN extends __TC {
  constructor(f, as) { super(); this.f = f; this.as = as }
  run() { return this.f(...this.as) }
}

// The count of the calls made by `__tcN` (a small integer, which keeps the
// count a small integer for V8 however deep the calls go).
const __tcNone = -1000000000

// `depth` is the number of calls made by `__tcN` on the stack since the
// nearest `__res` (or `__tcNone` and above, see above).  (A field of an
// object costs less to read and write than a variable of the script, which
// matters in the calls of foreign functions, which set it twice.)
const __tc = { depth: __tcNone }

function __tc0(f) {
  if (__tc.depth >= 64) return new __TC0(f)
  __tc.depth++; const r = f(); __tc.depth--; return r
}
function __tc1(f, a) {
  if (__tc.depth >= 64) return new __TC1(f, a)
  __tc.depth++; const r = f(a); __tc.depth--; return r
}
function __tc2(f, a, b) {
  if (__tc.depth >= 64) return new __TC2(f, a, b)
  __tc.depth++; const r = f(a, b); __tc.depth--; return r
}
function __tc3(f, a, b, c) {
  if (__tc.depth >= 64) return new __TC3(f, a, b, c)
  __tc.depth++; const r = f(a, b, c); __tc.depth--; return r
}
function __tcN(f, as) {
  if (__tc.depth >= 64) return new __TCN(f, as)
  __tc.depth++; const r = f(...as); __tc.depth--; return r
}

// The value of `r`, once the pending calls are run.
function __res(r) {
  if (!(r instanceof __TC)) return r
  const depth = __tc.depth
  __tc.depth = 0
  do r = r.run(); while (r instanceof __TC)
  __tc.depth = depth
  return r
}

// The value of `r` once the pending calls are run, as a caller from
// JavaScript code (which has set the count to 0 and restores it).
function __resRun(r) {
  while (r instanceof __TC) r = r.run()
  return r
}

// The value of `f.apply(self, args)` from JavaScript code, as a caller that
// runs the pending calls.
function __resCall(f, self, args) {
  const depth = __tc.depth
  __tc.depth = 0
  try {
    return __resRun(f.apply(self, args))
  } finally {
    __tc.depth = depth
  }
}

// The wrapper that `__resFn` made of a function (a property of the
// function, which costs little more than making the wrapper, and of the
// wrapper itself), and the wrappers of the functions that cannot be given a
// property.
const __resFnKey = Symbol('idris2 resFn')
const __resFns = new WeakMap()

// A function given to foreign code, whose calls run the pending calls, also
// in the functions that it returns.  This is the function to call from
// JavaScript to get the trampoline in an Idris function that reached it in
// another way than as an argument of a function type of a foreign function.
// The same function always gets the same wrapper, which has the same length
// (so foreign code can recognise a function it was given before, as
// `removeEventListener` does, or look at its arity), and a wrapper is its own
// wrapper.  The wrapper passes on all the arguments it gets.  (Up to three
// parameters, it has them, which gives it its length, and passes on its
// `arguments`, which is as fast as rest parameters in a strict function;
// `Object.defineProperty` of the length would cost more than the rest.)
function __resFn(f) {
  if (typeof f !== 'function') return f
  let w = f[__resFnKey]
  if (w !== undefined) return w
  if ((w = __resFns.get(f)) !== undefined) return w
  switch (f.length) {
    case 0:
      w = function () {
        'use strict'
        const depth = __tc.depth; __tc.depth = 0
        try { return __resFn(__resRun(f.apply(this, arguments))) } finally { __tc.depth = depth }
      }
      break
    case 1:
      w = function (a) {
        'use strict'
        const depth = __tc.depth; __tc.depth = 0
        try { return __resFn(__resRun(f.apply(this, arguments))) } finally { __tc.depth = depth }
      }
      break
    case 2:
      w = function (a, b) {
        'use strict'
        const depth = __tc.depth; __tc.depth = 0
        try { return __resFn(__resRun(f.apply(this, arguments))) } finally { __tc.depth = depth }
      }
      break
    case 3:
      w = function (a, b, c) {
        'use strict'
        const depth = __tc.depth; __tc.depth = 0
        try { return __resFn(__resRun(f.apply(this, arguments))) } finally { __tc.depth = depth }
      }
      break
    default:
      w = function (...args) { return __resFn(__resCall(f, this, args)) }
      Object.defineProperty(w, 'length', { value: f.length })
  }
  // (a function that cannot be given a property, frozen for instance, has
  // its wrapper in `__resFns`)
  try { f[__resFnKey] = w } catch (e) { }
  if (f[__resFnKey] !== w) __resFns.set(f, w)
  w[__resFnKey] = w
  return w
}

function __lazy(thunk) {
  let res;
  return function () {
    if (thunk === undefined) return res;
    res = __res(thunk());
    thunk = undefined;
    return res;
  };
};

function __prim_stringIteratorNew(_str) {
  return 0
}

function __prim_stringIteratorToString(_, str, it, f) {
  return f(str.slice(it))
}

function __prim_stringIteratorNext(str, it) {
  if (it >= str.length)
    return {h: 0};
  else
    return {a1: str.charAt(it), a2: it + 1};
}

function __tailRec(f,ini) {
  let obj = ini;
  while(true){
    switch(obj.h){
      case 0: return obj.a1;
      default: obj = f(obj);
    }
  }
}

const _idrisworld = Symbol('idrisworld')

const _crashExp = x=>{throw new IdrisError(x)}

const _bigIntOfString = s=> {
  try {
    const idx = s.indexOf('.')
    return idx === -1 ? BigInt(s) : BigInt(s.slice(0, idx))
  } catch (e) { return 0n }
}

const _numberOfString = s=> {
  try {
    const res = Number(s);
    return isNaN(res) ? 0 : res;
  } catch (e) { return 0 }
}

const _intOfString = s=> Math.trunc(_numberOfString(s))

const _truncToChar = x=> String.fromCodePoint(
  (x >= 0 && x <= 55295) || (x >= 57344 && x <= 1114111) ? x : 0
)

// Int8
const _truncInt8 = x => {
  const res = x & 0xff;
  return res >= 0x80 ? res - 0x100 : res;
}

const _truncBigInt8 = x => Number(BigInt.asIntN(8, x))

// Euclidian Division
const _div = (a,b) => {
  const q = Math.trunc(a / b)
  const r = a % b
  return r < 0 ? (b > 0 ? q - 1 : q + 1) : q
}

const _divBigInt = (a,b) => {
  const q = a / b
  const r = a % b
  return r < 0n ? (b > 0n ? q - 1n : q + 1n) : q
}

// Euclidian Modulo
const _mod = (a,b) => {
  const r = a % b
  return r < 0 ? (b > 0 ? r + b : r - b) : r
}

const _modBigInt = (a,b) => {
  const r = a % b
  return r < 0n ? (b > 0n ? r + b : r - b) : r
}

const _add8s = (a,b) => _truncInt8(a + b)
const _sub8s = (a,b) => _truncInt8(a - b)
const _mul8s = (a,b) => _truncInt8(a * b)
const _div8s = (a,b) => _truncInt8(_div(a,b))
const _shl8s = (a,b) => _truncInt8(a << b)
const _shr8s = (a,b) => _truncInt8(a >> b)

// Int16
const _truncInt16 = x => {
  const res = x & 0xffff;
  return res >= 0x8000 ? res - 0x10000 : res;
}

const _truncBigInt16 = x => Number(BigInt.asIntN(16, x))

const _add16s = (a,b) => _truncInt16(a + b)
const _sub16s = (a,b) => _truncInt16(a - b)
const _mul16s = (a,b) => _truncInt16(a * b)
const _div16s = (a,b) => _truncInt16(_div(a,b))
const _shl16s = (a,b) => _truncInt16(a << b)
const _shr16s = (a,b) => _truncInt16(a >> b)

//Int32
const _truncInt32 = x => x & 0xffffffff

const _truncBigInt32 = x => Number(BigInt.asIntN(32, x))

const _add32s = (a,b) => _truncInt32(a + b)
const _sub32s = (a,b) => _truncInt32(a - b)
const _div32s = (a,b) => _truncInt32(_div(a,b))

const _mul32s = (a,b) => {
  const res = a * b;
  if (res <= Number.MIN_SAFE_INTEGER || res >= Number.MAX_SAFE_INTEGER) {
    return _truncInt32((a & 0xffff) * b + (b & 0xffff) * (a & 0xffff0000))
  } else {
    return _truncInt32(res)
  }
}

//Int64
const _truncBigInt64 = x => BigInt.asIntN(64, x)

const _add64s = (a,b) => _truncBigInt64(a + b)
const _sub64s = (a,b) => _truncBigInt64(a - b)
const _mul64s = (a,b) => _truncBigInt64(a * b)
const _shl64s = (a,b) => _truncBigInt64(a << b)
const _div64s = (a,b) => _truncBigInt64(_divBigInt(a,b))
const _shr64s = (a,b) => _truncBigInt64(a >> b)

//Bits8
const _truncUInt8 = x => x & 0xff

const _truncUBigInt8 = x => Number(BigInt.asUintN(8, x))

const _add8u = (a,b) => (a + b) & 0xff
const _sub8u = (a,b) => (a - b) & 0xff
const _mul8u = (a,b) => (a * b) & 0xff
const _div8u = (a,b) => Math.trunc(a / b)
const _shl8u = (a,b) => (a << b) & 0xff
const _shr8u = (a,b) => (a >> b) & 0xff

//Bits16
const _truncUInt16 = x => x & 0xffff

const _truncUBigInt16 = x => Number(BigInt.asUintN(16, x))

const _add16u = (a,b) => (a + b) & 0xffff
const _sub16u = (a,b) => (a - b) & 0xffff
const _mul16u = (a,b) => (a * b) & 0xffff
const _div16u = (a,b) => Math.trunc(a / b)
const _shl16u = (a,b) => (a << b) & 0xffff
const _shr16u = (a,b) => (a >> b) & 0xffff

//Bits32
const _truncUBigInt32 = x => Number(BigInt.asUintN(32, x))

const _truncUInt32 = x => {
  const res = x & -1;
  return res < 0 ? res + 0x100000000 : res;
}

const _add32u = (a,b) => _truncUInt32(a + b)
const _sub32u = (a,b) => _truncUInt32(a - b)
const _mul32u = (a,b) => _truncUInt32(_mul32s(a,b))
const _div32u = (a,b) => Math.trunc(a / b)

const _shl32u = (a,b) => _truncUInt32(a << b)
const _shr32u = (a,b) => _truncUInt32(a <= 0x7fffffff ? a >> b : (b == 0 ? a : (a >> b) ^ ((-0x80000000) >> (b-1))))
const _and32u = (a,b) => _truncUInt32(a & b)
const _or32u = (a,b)  => _truncUInt32(a | b)
const _xor32u = (a,b) => _truncUInt32(a ^ b)

//Bits64
const _truncUBigInt64 = x => BigInt.asUintN(64, x)

const _add64u = (a,b) => BigInt.asUintN(64, a + b)
const _mul64u = (a,b) => BigInt.asUintN(64, a * b)
const _div64u = (a,b) => a / b
const _shl64u = (a,b) => BigInt.asUintN(64, a << b)
const _shr64u = (a,b) => BigInt.asUintN(64, a >> b)
const _sub64u = (a,b) => BigInt.asUintN(64, a - b)

//String
const _strReverse = x => x.split('').reverse().join('')

const _substr = (o,l,x) => x.slice(o, o + l)

// Crash boundaries (System.Crash): `act` is a `PrimIO a`.  An Idris crash
// (an IdrisError) or any error that JavaScript raises ends it; its result is
// returned, or null if it crashed, and then __prim_crash_last is the record
// of what happened (until it is read).
let __prim_crashes = 0
let __prim_crash_last = null

function __prim_crash_catch(act) {
  try {
    return act(_idrisworld)
  } catch (e) {
    __prim_crashes++
    // (the clause added to a function that does not cover every input
    // crashes with this message)
    if (e instanceof IdrisError)
      __prim_crash_last = { kind: e.message.startsWith('Unhandled input for ') ? 1 : 0,
                            message: e.message, backtrace: null }
    else
      __prim_crash_last =
        { kind: 2, message: String(e && e.message !== undefined ? e.message : e),
          backtrace: e && typeof e.stack === 'string' ? e.stack + '\n' : null }
    return null
  }
}

function __prim_crashes_caught() { return __prim_crashes }
