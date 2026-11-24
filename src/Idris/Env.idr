module Idris.Env

--- All environment variables accessed by the compiler are enumerated in this module.

import public Data.List
import public Data.Maybe

import System

%default total

||| Environment variable used by Idris2i-1 compiler
public export
record EnvDesc where
  constructor MkEnvDesc
  name : String
  help : String

||| All environment variables used by Idris2i-1 compiler
public export
envs : List EnvDesc
envs = [
    MkEnvDesc "EDITOR"               "Editor used in REPL :e command.",
    MkEnvDesc "IDRIS2I_1_PREFIX"        "Idris2i-1 installation prefix.",
    MkEnvDesc "IDRIS2I_1_PATH"          "Directories where Idris2i-1 looks for import files.",
    MkEnvDesc "IDRIS2I_1_PACKAGE_PATH"  "Directories where Idris2i-1 looks for Idris2i-1 packages.",
    MkEnvDesc "IDRIS2I_1_DATA"          "Directories where Idris2i-1 looks for data files.",
    MkEnvDesc "IDRIS2I_1_LIBS"          "Directories where Idris2i-1 looks for libraries (for code generation).",
    MkEnvDesc "IDRIS2I_1_CG"            "Codegen backend.",
    MkEnvDesc "IDRIS2I_1_INC_CGS"       "Code generators to use (comma separated) when compiling modules incrementally.",
    MkEnvDesc "IDRIS2I_1_BUILD_JOBS"    "How many processes build the modules of a package in parallel (see --jobs).",
    MkEnvDesc "IDRIS2I_1_TTC_CACHE_MB"  "How many megabytes of TTC files a process keeps, once read, for the modules it checks next (default: 32; 0 keeps none).",
    MkEnvDesc "CHEZ"                 "Chez backend: chez executable.",
    MkEnvDesc "RACKET"               "Racket backend: racket executable.",
    MkEnvDesc "RACKET_RACO"          "Racket backend: raco executable.",
    MkEnvDesc "GAMBIT_GSI"           "Gambit backend: gsi executable.",
    MkEnvDesc "GAMBIT_GSC"           "Gambit backend: gsc executable.",
    MkEnvDesc "GAMBIT_GSC_BACKEND"   "Gambit backend: arguments passed to gsc.",
    MkEnvDesc "IDRIS2I_1_CC"            "RefC backend: C compiler executable.",
    MkEnvDesc "IDRIS2I_1_CFLAGS"        "RefC backend: C compiler flags.",
    MkEnvDesc "IDRIS2I_1_CC_JOBS"       "RefC backend: how many C compilers compile a big program in parallel (default: the number of processors, up to 16).",
    MkEnvDesc "IDRIS2I_1_REFC_SPLIT_SIZE" "RefC backend: the size in bytes of C from which a program is compiled in units (default: 4000000).",
    MkEnvDesc "IDRIS2I_1_CPPFLAGS"      "RefC backend: C preprocessor flags.",
    MkEnvDesc "IDRIS2I_1_LDFLAGS"       "RefC backend: C linker flags.",
    MkEnvDesc "IDRIS2I_1_LDLIBS"        "RefC backend: C linker library names or flags.",
    MkEnvDesc "CC"                   "RefC backend: C compiler executable (IDRIS2I_1_CC takes precedence).",
    MkEnvDesc "CFLAGS"               "RefC backend: C compiler flags (IDRIS2I_1_CFLAGS takes precedence).",
    MkEnvDesc "CPPFLAGS"             "RefC backend: C preprocessor flags (IDRIS2I_1_CPPFLAGS takes precedence).",
    MkEnvDesc "LDFLAGS"              "RefC backend: C linker flags (IDRIS2I_1_LDFLAGS takes precedence).",
    MkEnvDesc "LDLIBS"               "RefC backend: C linker library names or flags (IDRIS2I_1_LDLIBS takes precedence).",
    MkEnvDesc "NODE"                 "NodeJS backend: NodeJS executable.",
    MkEnvDesc "PATH"                 "PATH variable is used to search for executables in certain codegens.",
    MkEnvDesc "DESTDIR"              "Directory prepended to the installation directory by --install (for staged installs).",
    MkEnvDesc "IDRIS2I_1_LINE_EDITING"  "Set to 0 to turn off line editing (history, key bindings and highlighting) in the REPL.",
    MkEnvDesc "IDRIS2I_1_HISTORY_FILE"  "File where the REPL keeps its history (default: ~/.idris2i_1_history). If empty, the history is not saved.",
    MkEnvDesc "NO_COLOR"             "Instruct Idris2i-1 not to print color to stdout. Passing the --color/--colour option will supersede this env var."]

--- `public export` only for `auto` to work in `idrisGetEnv`
public export
envNames : List String
envNames = map (.name) envs

||| Query documented environment variable
public export
idrisGetEnv : HasIO io => (name : String) ->
  {auto 0 known : IsJust (find (name ==) Env.envNames)}
  -> io (Maybe String)
idrisGetEnv name = getEnv name
