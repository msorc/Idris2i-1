-- The strings of C functions (see "Strings" in docs/source/ffi/ffi.rst):
-- a `String` result is copied and never freed, so it is for the strings that
-- the C code keeps; a string that the caller must free is a `Ptr String`,
-- which is converted and then freed.  Valgrind sees the leak or the bad free
-- of a wrong binding.

lib : String -> String
lib fn = "C:" ++ fn ++ ",libffistrings,ffistrings.h"

-- The library keeps the string (and returns a `const char *`).
%foreign (lib "dayName")
dayName : Int -> String

-- The caller frees the string.
%foreign (lib "greeting")
prim__greeting : String -> PrimIO (Ptr String)

%foreign (lib "freeGreeting")
prim__freeGreeting : Ptr String -> PrimIO ()

-- Copies the C string.  An IO action, not the pure `prim__getString`, so that
-- the copy is made before the string is freed.
%foreign "C:idris2_getString, libidris2_support, idris_support.h"
prim__copyString : Ptr String -> PrimIO String

greeting : HasIO io => String -> io (Maybe String)
greeting name
    = do ptr <- primIO (prim__greeting name)
         if prim__nullPtr ptr /= 0
            then pure Nothing
            else do str <- primIO (prim__copyString ptr)
                    primIO (prim__freeGreeting ptr)
                    pure (Just str)

-- The library copies its argument, which is only valid during the call.
%foreign (lib "setTitle")
prim__setTitle : String -> PrimIO ()

%foreign (lib "getTitle")
prim__getTitle : PrimIO String

%foreign (lib "clearTitle")
prim__clearTitle : PrimIO ()

greetAll : Nat -> Nat -> IO Nat
greetAll Z acc = pure acc
greetAll (S k) acc
    = do Just str <- greeting ("number " ++ show k)
           | Nothing => pure acc
         greetAll k (acc + length str)

main : IO ()
main = do putStrLn (dayName 0 ++ ", " ++ dayName 6 ++ ", " ++ dayName 7)
          Just str <- greeting "Idris"
            | Nothing => putStrLn "no greeting"
          putStrLn str
          printLn !(greetAll 1000 0)
          name <- getLine
          primIO (prim__setTitle ("A title for " ++ name))
          -- the argument of setTitle is freed by now
          printLn !(greetAll 1000 0)
          putStrLn !(primIO prim__getTitle)
          primIO prim__clearTitle
          putStrLn ("[" ++ !(primIO prim__getTitle) ++ "]")
