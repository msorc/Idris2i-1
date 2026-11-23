||| The static and dynamic tables of HPACK (RFC 7541 section 2.3 and
||| appendix A).
|||
||| The dynamic table is a pure value: a queue of entries, the newest at
||| the front, as two lists (the newest entries newest first, and the older
||| ones oldest first), so that adding an entry and evicting the oldest take
||| amortised constant time, and an index is found by walking at most the
||| number of entries (a table of the default 4096 bytes holds at most 128
||| of them, and usually a few dozen).
module Network.HTTP2.HPACK.Table

import Data.ByteString
import Data.ByteString.Internal
import Data.List

%default total

--------------------------------------------------------------------------
-- Entries
--------------------------------------------------------------------------

||| A name and a value, as they are stored in a table.
public export
record Entry where
  constructor MkEntry
  name : ByteString
  value : ByteString

||| The size of an entry as RFC 7541 section 4.1 counts it: the lengths of
||| the name and value plus 32.
export %inline
entrySize : ByteString -> ByteString -> Int
entrySize n v = lengthInt n + lengthInt v + 32

--------------------------------------------------------------------------
-- Static table
--------------------------------------------------------------------------

||| The number of entries of the static table (61).
export
staticTableSize : Int
staticTableSize = 61

-- The entries of the static table, each a constant (built once), and a
-- `case` on the index that selects one (a jump table in C).
static1 : Entry
static1 = MkEntry ":authority" ""
static2 : Entry
static2 = MkEntry ":method" "GET"
static3 : Entry
static3 = MkEntry ":method" "POST"
static4 : Entry
static4 = MkEntry ":path" "/"
static5 : Entry
static5 = MkEntry ":path" "/index.html"
static6 : Entry
static6 = MkEntry ":scheme" "http"
static7 : Entry
static7 = MkEntry ":scheme" "https"
static8 : Entry
static8 = MkEntry ":status" "200"
static9 : Entry
static9 = MkEntry ":status" "204"
static10 : Entry
static10 = MkEntry ":status" "206"
static11 : Entry
static11 = MkEntry ":status" "304"
static12 : Entry
static12 = MkEntry ":status" "400"
static13 : Entry
static13 = MkEntry ":status" "404"
static14 : Entry
static14 = MkEntry ":status" "500"
static15 : Entry
static15 = MkEntry "accept-charset" ""
static16 : Entry
static16 = MkEntry "accept-encoding" "gzip, deflate"
static17 : Entry
static17 = MkEntry "accept-language" ""
static18 : Entry
static18 = MkEntry "accept-ranges" ""
static19 : Entry
static19 = MkEntry "accept" ""
static20 : Entry
static20 = MkEntry "access-control-allow-origin" ""
static21 : Entry
static21 = MkEntry "age" ""
static22 : Entry
static22 = MkEntry "allow" ""
static23 : Entry
static23 = MkEntry "authorization" ""
static24 : Entry
static24 = MkEntry "cache-control" ""
static25 : Entry
static25 = MkEntry "content-disposition" ""
static26 : Entry
static26 = MkEntry "content-encoding" ""
static27 : Entry
static27 = MkEntry "content-language" ""
static28 : Entry
static28 = MkEntry "content-length" ""
static29 : Entry
static29 = MkEntry "content-location" ""
static30 : Entry
static30 = MkEntry "content-range" ""
static31 : Entry
static31 = MkEntry "content-type" ""
static32 : Entry
static32 = MkEntry "cookie" ""
static33 : Entry
static33 = MkEntry "date" ""
static34 : Entry
static34 = MkEntry "etag" ""
static35 : Entry
static35 = MkEntry "expect" ""
static36 : Entry
static36 = MkEntry "expires" ""
static37 : Entry
static37 = MkEntry "from" ""
static38 : Entry
static38 = MkEntry "host" ""
static39 : Entry
static39 = MkEntry "if-match" ""
static40 : Entry
static40 = MkEntry "if-modified-since" ""
static41 : Entry
static41 = MkEntry "if-none-match" ""
static42 : Entry
static42 = MkEntry "if-range" ""
static43 : Entry
static43 = MkEntry "if-unmodified-since" ""
static44 : Entry
static44 = MkEntry "last-modified" ""
static45 : Entry
static45 = MkEntry "link" ""
static46 : Entry
static46 = MkEntry "location" ""
static47 : Entry
static47 = MkEntry "max-forwards" ""
static48 : Entry
static48 = MkEntry "proxy-authenticate" ""
static49 : Entry
static49 = MkEntry "proxy-authorization" ""
static50 : Entry
static50 = MkEntry "range" ""
static51 : Entry
static51 = MkEntry "referer" ""
static52 : Entry
static52 = MkEntry "refresh" ""
static53 : Entry
static53 = MkEntry "retry-after" ""
static54 : Entry
static54 = MkEntry "server" ""
static55 : Entry
static55 = MkEntry "set-cookie" ""
static56 : Entry
static56 = MkEntry "strict-transport-security" ""
static57 : Entry
static57 = MkEntry "transfer-encoding" ""
static58 : Entry
static58 = MkEntry "user-agent" ""
static59 : Entry
static59 = MkEntry "vary" ""
static60 : Entry
static60 = MkEntry "via" ""
static61 : Entry
static61 = MkEntry "www-authenticate" ""

||| The entry of the static table at an index.  Precondition:
||| `1 <= i <= 61` (anything else gives entry 1).
export
staticEntry : Int -> Entry
staticEntry i = case i of
  1 => static1
  2 => static2
  3 => static3
  4 => static4
  5 => static5
  6 => static6
  7 => static7
  8 => static8
  9 => static9
  10 => static10
  11 => static11
  12 => static12
  13 => static13
  14 => static14
  15 => static15
  16 => static16
  17 => static17
  18 => static18
  19 => static19
  20 => static20
  21 => static21
  22 => static22
  23 => static23
  24 => static24
  25 => static25
  26 => static26
  27 => static27
  28 => static28
  29 => static29
  30 => static30
  31 => static31
  32 => static32
  33 => static33
  34 => static34
  35 => static35
  36 => static36
  37 => static37
  38 => static38
  39 => static39
  40 => static40
  41 => static41
  42 => static42
  43 => static43
  44 => static44
  45 => static45
  46 => static46
  47 => static47
  48 => static48
  49 => static49
  50 => static50
  51 => static51
  52 => static52
  53 => static53
  54 => static54
  55 => static55
  56 => static56
  57 => static57
  58 => static58
  59 => static59
  60 => static60
  61 => static61
  _ => static1

-- The indices of the static entries whose names have this length, in
-- increasing order, so that a lookup compares a name with the few entries
-- whose names have its length.  (A `case` of constant lists, which are made
-- once.)
staticWithLength : Int -> List Int
staticWithLength len = case len of
  3 => [21, 60]
  4 => [33, 34, 37, 38, 45, 59]
  5 => [4, 5, 22, 50]
  6 => [19, 32, 35, 54]
  7 => [2, 3, 6, 7, 8, 9, 10, 11, 12, 13, 14, 36, 51, 52]
  8 => [39, 42, 46]
  10 => [1, 55, 58]
  11 => [53]
  12 => [31, 47]
  13 => [18, 23, 24, 30, 41, 44]
  14 => [15, 28]
  15 => [16, 17]
  16 => [26, 27, 29, 61]
  17 => [40, 57]
  18 => [48]
  19 => [25, 43, 49]
  25 => [56]
  27 => [20]
  _ => []

||| The index of the first entry of the static table with this name and
||| value, and the index of the first one with this name, or 0 for none.
||| The name must be in lower case.
export
staticLookup : ByteString -> ByteString -> (Int, Int)
staticLookup n v = go (staticWithLength (lengthInt n)) 0
  where
    go : List Int -> Int -> (Int, Int)
    go [] nameIdx = (0, nameIdx)
    go (i :: is) nameIdx =
      let e = staticEntry i in
      if sameBytes e.name n
         then if sameBytes e.value v then (i, if nameIdx == 0 then i else nameIdx)
              else go is (if nameIdx == 0 then i else nameIdx)
         else go is nameIdx

--------------------------------------------------------------------------
-- Dynamic table
--------------------------------------------------------------------------

||| A dynamic table: its entries, its size (RFC 7541 section 4.1) and its
||| maximum size.
export
record DynamicTable where
  constructor MkDynamicTable
  -- The newest entries, newest first.
  front : List Entry
  frontLen : Int
  -- The older entries, oldest first.
  back : List Entry
  backLen : Int
  size : Int
  maxSize : Int

||| An empty table with a maximum size.
export
emptyTable : (maxSize : Int) -> DynamicTable
emptyTable m = MkDynamicTable [] 0 [] 0 0 m

||| The number of entries.
export
tableCount : DynamicTable -> Int
tableCount t = t.frontLen + t.backLen

||| The size of the entries (RFC 7541 section 4.1).
export
tableSize : DynamicTable -> Int
tableSize t = t.size

||| The maximum size.
export
tableMaxSize : DynamicTable -> Int
tableMaxSize t = t.maxSize

||| The entries, newest (index 1) first.
export
tableEntries : DynamicTable -> List Entry
tableEntries t = t.front ++ reverse t.back

-- Remove the oldest entry.  Precondition: the table is not empty.
evictOne : DynamicTable -> DynamicTable
evictOne t = case t.back of
  (e :: rest) => { back := rest, backLen $= (\n => n - 1),
                   size $= (\s => s - entrySize e.name e.value) } t
  [] => case reverse t.front of
          [] => t
          (e :: rest) => { front := [], frontLen := 0, back := rest,
                           backLen := t.frontLen - 1,
                           size $= (\s => s - entrySize e.name e.value) } t

-- Evict until the size is at most `limit`.
evictTo : Int -> DynamicTable -> DynamicTable
evictTo limit t =
  if t.size <= limit || tableCount t == 0 then t
  else evictTo limit (assert_smaller t (evictOne t))

||| Change the maximum size, evicting the oldest entries that no longer
||| fit (RFC 7541 section 4.3).
export
setMaxSize : Int -> DynamicTable -> DynamicTable
setMaxSize m t = { maxSize := m } (evictTo m t)

||| Add an entry (RFC 7541 section 4.4): the oldest entries are evicted
||| until it fits; an entry bigger than the maximum size empties the table
||| and is not added.
export
insert : Entry -> DynamicTable -> DynamicTable
insert e t =
  let sz = entrySize e.name e.value in
  if sz > t.maxSize then { front := [], frontLen := 0, back := [], backLen := 0, size := 0 } t
  else let t' = evictTo (t.maxSize - sz) t in
       { front $= (e ::), frontLen $= (+ 1), size $= (+ sz) } t'

-- The element at a 0-based index of a list.
nth : Int -> List Entry -> Maybe Entry
nth _ [] = Nothing
nth i (x :: xs) = if i <= 0 then Just x else nth (i - 1) xs

||| The entry at an index of the dynamic table, 1 for the newest.
export
dynamicEntry : Int -> DynamicTable -> Maybe Entry
dynamicEntry i t =
  if i < 1 then Nothing
  else if i <= t.frontLen then nth (i - 1) t.front
  else let j = i - t.frontLen in
       if j > t.backLen then Nothing else nth (t.backLen - j) t.back

||| The index of the newest entry with this name and value, and that of the
||| newest one with this name, or 0 for none (indices of the dynamic table,
||| 1 for the newest).
export
dynamicLookup : ByteString -> ByteString -> DynamicTable -> (Int, Int)
dynamicLookup n v t =
  case goList 1 0 t.front of
    (0, nameIdx) => goBack nameIdx
    found => found
  where
    goList : Int -> Int -> List Entry -> (Int, Int)
    goList _ nameIdx [] = (0, nameIdx)
    goList i nameIdx (e :: rest) =
      if lengthInt e.name == lengthInt n && e.name == n
         then if e.value == v then (i, if nameIdx == 0 then i else nameIdx)
              else goList (i + 1) (if nameIdx == 0 then i else nameIdx) rest
         else goList (i + 1) nameIdx rest
    -- The back list is oldest first: the newest match is the last one.
    goBackList : Int -> (Int, Int) -> List Entry -> (Int, Int)
    goBackList _ acc [] = acc
    goBackList i (full, nm) (e :: rest) =
      if lengthInt e.name == lengthInt n && e.name == n
         then goBackList (i - 1) (if e.value == v then i else full, i) rest
         else goBackList (i - 1) (full, nm) rest
    goBack : Int -> (Int, Int)
    goBack nameIdx =
      let (full, nm) = goBackList (t.frontLen + t.backLen) (0, 0) t.back in
      (full, if nameIdx == 0 then nm else nameIdx)
