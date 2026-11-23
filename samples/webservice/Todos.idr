||| The routes of the sample web service (see Main.idr) and what they keep:
||| a list of things to do, in memory.  Main.idr serves them over HTTP,
||| Https.idr over HTTPS.
module Todos

import Data.IORef
import Data.Maybe
import Data.SortedMap
import Language.JSON.Derive
import Language.JSON.Typed
import Network.HTTP.Router
import System
import System.File
import System.Signal

%default covering
%language ElabReflection

-- The data

||| An item as the service keeps it and sends it.
public export
record Todo where
  constructor MkTodo
  id : Int
  title : String
  done : Bool

||| An item as a client sends it (the service picks the id).
public export
record NewTodo where
  constructor MkNewTodo
  title : String
  done : Maybe Bool

%hint
todoToJSON : ToJSON Todo
todoToJSON = %runElab deriveToJSON defaultOptions

%hint
newTodoFromJSON : FromJSON NewTodo
newTodoFromJSON = %runElab deriveFromJSON defaultOptions

-- The store: the items by id, and the next id.  Handlers run in many
-- threads at once, so it changes only with atomicModifyIORef.
public export
record Store where
  constructor MkStore
  items : SortedMap Int Todo
  nextId : Int

-- The routes

||| The id captured in the path, if it is a number.
idParam : Params -> Maybe Int
idParam ps = do
  s <- param "id" ps
  let n = cast {to = Int} s
  if show n == s then Just n else Nothing

notFound : Response
notFound = jsonError statusNotFound "no such item"

||| The routes, over a store.
export
routes : IORef Store -> List Route
routes store =
  [ route GET "/health" $ \_, _ => pure (textResponse statusOK "ok\n")

  , route GET "/todos" $ \req, _ => do
      s <- readIORef store
      let all = values s.items
      pure $ jsonResponse statusOK $ case queryParam "done" req of
        Just "true" => filter (.done) all
        Just "false" => filter (not . (.done)) all
        _ => all

  , route POST "/todos" $ \req, _ => do
      Right new <- jsonBody {a = NewTodo} req
        | Left bad => pure bad
      todo <- atomicModifyIORef store $ \s =>
                let t = MkTodo s.nextId new.title (fromMaybe False new.done) in
                ({ items $= insert t.id t, nextId $= (+ 1) } s, t)
      pure (withHeader "Location" (fromString ("/todos/" ++ show todo.id))
              (jsonResponse statusCreated todo))

  , route GET "/todos/:id" $ \_, ps => do
      s <- readIORef store
      pure $ case idParam ps >>= \i => lookup i s.items of
        Just t => jsonResponse statusOK t
        Nothing => notFound

  , route PUT "/todos/:id" $ \req, ps => do
      Right new <- jsonBody {a = NewTodo} req
        | Left bad => pure bad
      let Just i = idParam ps
        | Nothing => pure notFound
      found <- atomicModifyIORef store $ \s =>
                 case lookup i s.items of
                   Nothing => (s, Nothing)
                   Just _ => let t = MkTodo i new.title (fromMaybe False new.done) in
                             ({ items $= insert i t } s, Just t)
      pure (maybe notFound (jsonResponse statusOK) found)

  , route DELETE "/todos/:id" $ \_, ps => do
      let Just i = idParam ps
        | Nothing => pure notFound
      found <- atomicModifyIORef store $ \s =>
                 case lookup i s.items of
                   Nothing => (s, False)
                   Just _ => ({ items $= delete i } s, True)
      pure (if found then emptyResponse statusNoContent else notFound)
  ]

-- (The output is flushed at once, so that a log that goes to a file or a
-- pipe is up to date.)
export
say : String -> IO ()
say s = do putStrLn s; fflush stdout

-- Wait for SIGINT, then stop the server, letting requests in progress
-- finish for up to five seconds.
export
stopOnInterrupt : Server -> IO ()
stopOnInterrupt srv = do
  Just SigINT <- handleNextCollectedSignal
    | _ => do usleep 100000; stopOnInterrupt srv
  say "interrupted: stopping"
  stopServer srv 5000

||| The access log: a line per response.
export
logRequest : AccessLogEntry -> IO ()
logRequest e =
  say "\{show e.method} \{toStringLossy e.target} \{show e.status} \{show e.bodyBytes}B \{show (e.durationNs `div` 1000)}us"

||| An empty store.
export
newStore : IO (IORef Store)
newStore = newIORef (MkStore empty 1)

||| Run a started server until SIGINT, then stop it gracefully.
export
runUntilInterrupted : Server -> IO ()
runUntilInterrupted srv = do
  say "listening on \{show (serverAddress srv)}"
  Right () <- collectSignal SigINT
    | Left _ => putStrLn "cannot catch SIGINT: stop the service another way"
  _ <- fork (stopOnInterrupt srv)
  waitServer srv
  say "stopped"
