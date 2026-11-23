||| A chat hub, driven here by a deterministic load generator.
|||
||| Rooms open, members join and talk, rooms close. At most `window` rooms are open
||| at a time. The program prints totals at the end.
module Main

import Data.IORef
import Data.List
import Data.String
import System

data Member : Type

record Room where
  constructor MkRoom
  ident   : Int
  members : IORef (List Member)
  traffic : IORef Int
  onClose : IORef (List (IO ()))

data Member : Type where
  MkMember : (ident : Int) -> (room : Room) -> (sent : IORef Int) -> Member

record Stats where
  constructor MkStats
  rooms    : Int
  joins    : Int
  messages : Int
  checksum : Int

record Hub where
  constructor MkHub
  active : IORef (List Room)
  stats  : IORef Stats
  log    : IORef (List String)

window : Nat
window = 8

mix : Int -> Int -> Int
mix h x = (h * 31 + x) `mod` 1000000007

newRoom : Hub -> Int -> IO Room
newRoom hub ident = do
  room <- [| MkRoom (pure ident) (newIORef []) (newIORef 0) (newIORef []) |]
  -- when the room closes, add what happened in it to the hub's statistics
  modifyIORef room.onClose (report room ::)
  modifyIORef hub.active (room ::)
  pure room
  where
    report : Room -> IO ()
    report room = do
      ms <- readIORef room.members
      t <- readIORef room.traffic
      modifyIORef hub.stats $ \s =>
        { rooms $= (+ 1), joins $= (+ cast (length ms)), messages $= (+ t),
          checksum $= (\c => mix c (room.ident + t)) } s

join : Room -> Int -> IO Member
join room ident = do
  sent <- newIORef 0
  let m = MkMember ident room sent
  modifyIORef room.members (m ::)
  pure m

say : Member -> Int -> IO ()
say (MkMember ident room sent) words = do
  modifyIORef sent (+ words)
  modifyIORef room.traffic (\t => mix t (ident * 7 + words))

close : Hub -> Room -> IO ()
close hub room = do
  hooks <- readIORef room.onClose
  sequence_ hooks
  modifyIORef hub.active (filter (\r => r.ident /= room.ident))

||| Keep the last few lines of the log.
note : Hub -> String -> IO ()
note hub line = modifyIORef hub.log (take 20 . (line ::))

||| One step of the load: open a room, fill it, let it talk, and close the oldest
||| room when too many are open.
step : Hub -> Int -> IO ()
step hub i = do
  room <- newRoom hub i
  let size = 3 + i `mod` 4
  ms <- traverse (\k => join room (i * 10 + k)) [1 .. size]
  -- the loudest member is thanked when the room closes
  for_ ms $ \m => say m (1 + (i + 3) `mod` 5)
  case ms of
    (first :: _) => modifyIORef room.onClose (thank first ::)
    [] => pure ()
  when (i `mod` 50000 == 0) $ note hub "room \{show i} open"
  rooms <- readIORef hub.active
  when (length rooms > window) $
    case last' rooms of
      Just oldest => close hub oldest
      Nothing => pure ()
  where
    thank : Member -> IO ()
    thank (MkMember ident _ sent) = do
      n <- readIORef sent
      modifyIORef hub.stats { checksum $= (\c => mix c (ident + n)) }

run : Int -> IO ()
run n = do
  hub <- [| MkHub (newIORef []) (newIORef (MkStats 0 0 0 0)) (newIORef []) |]
  loop hub 1
  rest <- readIORef hub.active
  for_ (reverse rest) (close hub)
  s <- readIORef hub.stats
  lines <- readIORef hub.log
  putStrLn "rooms \{show s.rooms} joins \{show s.joins} messages \{show s.messages} checksum \{show s.checksum}"
  putStrLn "log lines \{show (length lines)}"
  where
    loop : Hub -> Int -> IO ()
    loop hub i = if i > n then pure () else do
      step hub i
      loop hub (i + 1)

main : IO ()
main = do
  [_, arg] <- getArgs
    | _ => die "usage: hub ROUNDS"
  case parsePositive arg of
    Just n => run n
    Nothing => die "usage: hub ROUNDS"
