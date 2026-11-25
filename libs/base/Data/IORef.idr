module Data.IORef

import System.Concurrency
import System.Info

%default total

-- Implemented externally
-- e.g., in Scheme, passed around as a box
data Mut : Type -> Type where [external]

%extern prim__newIORef : forall a . a -> (1 x : %World) -> IORes (Mut a)
%extern prim__readIORef : forall a . Mut a -> (1 x : %World) -> IORes a
%extern prim__writeIORef : forall a . Mut a -> a -> (1 x : %World) -> IORes ()

export
data IORef : Type -> Type where
     MkRef : Mut a -> IORef a

||| Create a new IORef.
%spec hio
export
newIORef : {auto hio : HasIO io} -> a -> io (IORef a)
newIORef val
    = do m <- primIO (prim__newIORef val)
         pure (MkRef m)

||| Read the value of an IORef.
%spec hio
%inline
export
readIORef : {auto hio : HasIO io} -> IORef a -> io a
readIORef (MkRef m) = primIO (prim__readIORef m)

||| Write a new value into an IORef.
||| This function does not create a memory barrier and can be reordered with other independent reads and writes within a thread,
||| which may cause issues for multithreaded execution.
%spec hio
%inline
export
writeIORef : {auto hio : HasIO io} -> IORef a -> (val : a) -> io ()
writeIORef (MkRef m) val = primIO (prim__writeIORef m val)

||| Mutate the contents of an IORef, combining readIORef and writeIORef.
||| This is not an atomic update, consider using atomically when operating in a multithreaded environment.
%spec hio
export
modifyIORef : {auto hio : HasIO io} -> IORef a -> (a -> a) -> io ()
modifyIORef ref f
    = do val <- readIORef ref
         writeIORef ref (f val)

||| This function atomically runs its argument according to the provided mutex.
||| It can for instance be used to modify the contents of an IORef `ref` with a function `f`
||| in a safe way in a multithreaded program by using `atomically lock (modifyIORef ref f)`
||| provided that other threads also rely on the same `lock` to modify `ref`.
%spec hio
export
atomically : {auto hio : HasIO io} -> Mutex -> io () -> io ()
atomically lock act
    = do mutexAcquire lock
         act
         mutexRelease lock

-- Atomic operations

||| What an `IORef` held when `readForCAS` read it, for `casIORef`: the
||| value itself, which `peekTicket` gives.
|||
||| A ticket stands for that very value (the object in memory), not for
||| what it is equal to: see `casIORef`.
export
data Ticket : Type -> Type where [external]

%foreign "RefC:refc_readForCAS"
         "scheme,chez:(lambda (ty r) (unbox r))"
         "javascript:lambda:(ty, r) => r.value"
prim__readForCAS : Mut a -> PrimIO (Ticket a)

%foreign "RefC:refc_peekTicket"
         "scheme,chez:(lambda (ty t) t)"
         "javascript:lambda:(ty, t) => t"
prim__peekTicket : Ticket a -> a

%foreign "RefC:refc_casIORef"
         "scheme,chez:blodwen-box-cas"
         "javascript:lambda:(ty, r, t, v) => Object.is(r.value, t) ? ((r.value = v), 1) : 0"
prim__casIORef : Mut a -> Ticket a -> a -> PrimIO Int

||| Read the value of an IORef as a `Ticket`, for `casIORef`.
%spec hio
%inline
export
readForCAS : {auto hio : HasIO io} -> IORef a -> io (Ticket a)
readForCAS (MkRef m) = primIO (prim__readForCAS m)

||| The value that a ticket stands for.
%inline
export
peekTicket : Ticket a -> a
peekTicket t = prim__peekTicket t

||| Compare-and-swap: write `new` into the IORef if it still holds the value
||| of the ticket, as one atomic step, and tell whether it did.
|||
||| "Still holds the value of the ticket" means the same object, not an
||| equal one: the swap is done when the IORef has not been written since
||| the ticket was read, or was written back with that very value (from
||| `peekTicket`, say).  An equal value that was built again, such as the
||| result of `x + 0` or a list built anew, counts as another value, so the
||| swap fails: read a new ticket and try again.  Values that a back end
||| does not allocate (small integers, characters, constructors without
||| arguments, on most back ends) are the same whenever they are equal; as
||| which values these are depends on the back end, a program should not
||| rely on it, only on a swap failing after a write of a value that
||| differs.  A ticket keeps its value alive, so a value that was written
||| and replaced cannot be mistaken for a new one at the same address.
|||
||| Supported by the RefC, Chez and JavaScript back ends.
%spec hio
%inline
export
casIORef : {auto hio : HasIO io} -> IORef a -> Ticket a -> (new : a) -> io Bool
casIORef (MkRef m) t new = pure $ !(primIO (prim__casIORef m t new)) /= 0

||| Atomically apply a function to the value of an IORef: write the first
||| part of its result back, and return the second part.  Other threads see
||| either the old value or the new one, and no update is lost when threads
||| update the IORef at the same time.
|||
||| This is a loop of `readForCAS`, `f` and `casIORef`: no lock is held while
||| `f` runs, and when another thread wrote the IORef in the meantime, `f`
||| runs again on the new value.  So `f` may run more than once (on the RefC
||| and Chez back ends, whose threads run in parallel, it does when threads
||| contend for the IORef), and should be cheap and pure.  If `f` crashes,
||| the program stops; if it loops, the IORef stays as it was and other
||| threads can still read and update it.  Under heavy contention, a slow
||| `f` may have to be retried many times; protect such an update with a
||| `Mutex` instead (see `atomically`).
|||
||| The writes of `writeIORef` count as updates: an `atomicModifyIORef`
||| that runs at the same time is retried, not lost.
%spec hio
export
atomicModifyIORef : {auto hio : HasIO io} -> IORef a -> (a -> (a, b)) -> io b
atomicModifyIORef ref f
    = do t <- readForCAS ref
         let (new, res) = f (peekTicket t)
         True <- casIORef ref t new
           | False => assert_total (atomicModifyIORef ref f)
         pure res

||| Atomically apply a function to the value of an IORef, as
||| `atomicModifyIORef` does (`f` may run more than once).
%spec hio
export
atomicModifyIORef_ : {auto hio : HasIO io} -> IORef a -> (a -> a) -> io ()
atomicModifyIORef_ ref f = atomicModifyIORef ref (\x => (f x, ()))
