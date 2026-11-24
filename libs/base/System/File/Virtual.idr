||| Magic/Virtual files
module System.File.Virtual

import System.File.Support
import public System.File.Types

%default total

%foreign supportC "idris2i_1_stdin"
         supportNode "stdin"
prim__stdin : FilePtr

%foreign supportC "idris2i_1_stdout"
         supportNode "stdout"
prim__stdout : FilePtr

%foreign supportC "idris2i_1_stderr"
         supportNode "stderr"
prim__stderr : FilePtr

||| The standard input.
export
stdin : File
stdin = FHandle prim__stdin

||| The standard output.
export
stdout : File
stdout = FHandle prim__stdout

||| The standard error.
export
stderr : File
stderr = FHandle prim__stderr
