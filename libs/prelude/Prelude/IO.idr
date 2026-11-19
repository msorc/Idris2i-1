module Prelude.IO

import Builtin
import PrimIO
import Prelude.Basics
import Prelude.Interfaces
import Prelude.Show
import Prelude.Types

%default total

--------
-- IO --
--------

public export
Functor IO where
  map f io = io_bind io $ io_pure . f

%inline
public export
Applicative IO where
  pure x = io_pure x
  f <*> a
      = io_bind f (\f' =>
          io_bind a (\a' =>
            io_pure (f' a')))

%inline
public export
Monad IO where
  b >>= k = io_bind b k

||| `traverse_` on a list in `IO`, as a loop.  `traverse_` builds a chain of
||| `*>` as long as the list and then runs it, which needs a stack as deep as
||| the list on the JavaScript backends; this passes the world on from one
||| action to the next instead.  Uses of `traverse_`, `for_` and `sequence_` on
||| lists in `IO` are transformed to this.
public export
ioTraverseList_ : (a -> IO b) -> List a -> IO ()
ioTraverseList_ f xs = fromPrim (go xs)
  where
    go : List a -> (1 w : %World) -> IORes ()
    go [] w = MkIORes () w
    go (x :: xs) w = case toPrim (f x) w of
                          MkIORes _ w' => go xs w'

%transform "ioTraverseList_" traverse_ {t = List} {f = IO} = ioTraverseList_
%transform "ioForList_" for_ {t = List} {f = IO} xs f = ioTraverseList_ f xs
%transform "ioSequenceList_" sequence_ {t = List} {f = IO} {a} xs = ioTraverseList_ {a = IO a} {b = a} id xs

public export
interface Monad io => HasIO io where
  constructor MkHasIO
  liftIO : IO a -> io a

public export
interface Monad io => HasLinearIO io where
  constructor MkHasLinearIO
  liftIO1 : (1 _ : IO a) -> io a

public export %inline
HasLinearIO IO where
  liftIO1 x = x

public export %inline
HasLinearIO io => HasIO io where
  liftIO x = liftIO1 x

export %inline
primIO : HasIO io => (fn : (1 x : %World) -> IORes a) -> io a
primIO op = liftIO (fromPrim op)

export %inline
primIO1 : HasLinearIO io => (1 fn : (1 x : %World) -> IORes a) -> io a
primIO1 op = liftIO1 (fromPrim op)

%extern
prim__onCollectAny : AnyPtr -> (AnyPtr -> PrimIO ()) -> PrimIO GCAnyPtr
%extern
prim__onCollect : Ptr t -> (Ptr t -> PrimIO ()) -> PrimIO (GCPtr t)

export
onCollectAny : HasIO io => AnyPtr -> (AnyPtr -> IO ()) -> io GCAnyPtr
onCollectAny ptr c = primIO (prim__onCollectAny ptr (\x => toPrim (c x)))

export
onCollect : HasIO io => Ptr t -> (Ptr t -> IO ()) -> io (GCPtr t)
onCollect ptr c = primIO (prim__onCollect ptr (\x => toPrim (c x)))

%foreign "C:idris2_getString, libidris2_support, idris_support.h"
         "javascript:lambda:x=>x"
export
prim__getString : Ptr String -> String

%foreign "RefC:idris2_refc_putChar"
         "C:putchar,libc 6"
         "node:lambda:x=>process.stdout.write(x)"
         "browser:lambda:x=>console.log(x)"
prim__putChar : Char -> (1 x : %World) -> IORes ()

%foreign "C:getchar,libc 6"
         "node:support:getChar,support_system_file"
%extern prim__getChar : (1 x : %World) -> IORes Char

-- (RefC: its own reader builds the string directly, without the copy out of
-- the per-thread buffer of idris2_getStr that the other backends make.)
%foreign "RefC:idris2_refc_getStr"
         "C:idris2_getStr, libidris2_support, idris_support.h"
         "node:support:getStr,support_system_file"
prim__getStr : PrimIO String

%foreign "RefC:idris2_refc_putStr"
         "C:idris2_putStr, libidris2_support, idris_support.h"
         "node:lambda:x=>process.stdout.write(x)"
         "browser:lambda:x=>console.log(x)"
prim__putStr : String -> PrimIO ()

||| Output a string to stdout without a trailing newline.
%inline export
putStr : HasIO io => String -> io ()
putStr str = primIO (prim__putStr str)

||| Output a string to stdout with a trailing newline.
export
%inline putStrLn : HasIO io => String -> io ()
putStrLn str = putStr (prim__strAppend str "\n")

||| Read one line of input from stdin, without the trailing newline.
%inline export
getLine : HasIO io => io String
getLine = primIO prim__getStr

||| Write one single-byte character to stdout.
%inline export
putChar : HasIO io => Char -> io ()
putChar c = primIO (prim__putChar c)

||| Write one multi-byte character to stdout, with a trailing newline.
%inline export
putCharLn : HasIO io => Char -> io ()
putCharLn c = putStrLn (prim__cast_CharString c)

||| Read one single-byte character from stdin.
%inline export
getChar : HasIO io => io Char
getChar = primIO prim__getChar

%foreign "scheme:blodwen-thread"
         "RefC:refc_fork"
         "javascript:support:fork,support_concurrency"
export
prim__fork : (1 prog : PrimIO ()) -> PrimIO ThreadID

export
fork : (1 prog : IO ()) -> IO ThreadID
fork act = fromPrim (prim__fork (toPrim act))

%foreign "scheme:blodwen-thread-wait"
         "RefC:refc_threadWait"
         "javascript:support:threadWait,support_concurrency"
export
prim__threadWait : (1 threadID : ThreadID) -> PrimIO ()

export
threadWait : (1 threadID : ThreadID) -> IO ()
threadWait threadID = fromPrim (prim__threadWait threadID)

||| Output something showable to stdout, without a trailing newline.
%inline export
print : HasIO io => Show a => a -> io ()
print = putStr . show

||| Output something showable to stdout, with a trailing newline.
%inline export
printLn : HasIO io => Show a => a -> io ()
printLn = putStrLn . show

-- (These are at the end of the file, so that the positions in it that the
-- expected output of refc/callingConvention shows stay.)

||| `traverse` on a list in `IO`, as a loop.  `traverse` builds a chain of
||| `<*>` as long as the list, and running it needs a stack as deep as the
||| list on the JavaScript backends; this passes the world on from one action
||| to the next and collects the results in a `SnocList`.  Uses of
||| `traverse`, `for` and `sequence` on lists in `IO` are transformed to this.
public export
ioTraverseList : (a -> IO b) -> List a -> IO (List b)
ioTraverseList f xs = fromPrim (go [<] xs)
  where
    go : SnocList b -> List a -> (1 w : %World) -> IORes (List b)
    go sy [] w = MkIORes (sy <>> []) w
    go sy (x :: xs) w = case toPrim (f x) w of
                             MkIORes y w' => go (sy :< y) xs w'

%transform "ioTraverseList" traverse {t = List} {f = IO} = ioTraverseList
%transform "ioForList" for {t = List} {f = IO} xs f = ioTraverseList f xs
%transform "ioSequenceList" sequence {t = List} {f = IO} {a} xs = ioTraverseList {a = IO a} {b = a} id xs

||| `foldlM` on a list in `IO`, as a loop.  `foldlM` builds a chain of `>>=`
||| as long as the list, nested to the left, and running it needs a stack as
||| deep as the list on the JavaScript backends; this passes the world and
||| the accumulator on from one action to the next instead.  Uses of `foldlM`
||| on lists in `IO` are transformed to this.
public export
ioFoldlMList : (acc -> a -> IO acc) -> acc -> List a -> IO acc
ioFoldlMList f a0 xs = fromPrim (go a0 xs)
  where
    go : acc -> List a -> (1 w : %World) -> IORes acc
    go a [] w = MkIORes a w
    go a (x :: xs) w = case toPrim (f a x) w of
                            MkIORes a' w' => go a' xs w'

%transform "ioFoldlMList" foldlM {t = List} {m = IO} = ioFoldlMList

||| `*>` in `IO`, where the second action is a tail call.  `a *> b` is
||| `map (const id) a <*> b`, which runs `b` and then gives its value on: a
||| chain of `*>` as long as a list (`foldr (*>) (pure ()) actions`) then
||| needs a stack as deep as the list on the JavaScript backends.  Uses of
||| `*>` in `IO` are transformed to this.
public export
ioSeqRight : IO a -> IO b -> IO b
ioSeqRight a b = io_bind a (\_ => b)

%transform "ioSeqRight" (*>) {f = IO} = ioSeqRight
