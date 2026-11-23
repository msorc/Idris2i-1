-- The instances of Language.JSON.Typed, and derived ones.
import Data.List1
import Data.SnocList
import Data.SortedMap
import Data.HashMap
import Data.Vect
import Language.JSON.Derive

%language ElabReflection
%default total

roundTrip : (Eq a, ToJSON a, FromJSON a) => String -> a -> IO ()
roundTrip name x = do
  let txt = toJSONText x
  putStrLn (name ++ ": " ++ txt ++ " " ++ show (fromJSONText txt == Right x))

decodeAs : (0 a : Type) -> (Show a, FromJSON a) => String -> IO ()
decodeAs a txt = putStrLn (txt ++ " => " ++ either show show (fromJSONText {a} txt))

-- A record, a nested record, an enumeration, a sum with fields, a tree.
record Address where
  constructor MkAddress
  street : String
  zip : Maybe Int

record Person where
  constructor MkPerson
  name : String
  age : Int
  address : Address
  nicknames : List String

data Colour = Red | Green | Blue

data Shape : Type where
  Circle : Double -> Shape
  Rect : Double -> Double -> Shape
  Dot : Shape
  Labelled : (label : String) -> (size : Bits8) -> Shape

data Tree a = Leaf | Node (Tree a) a (Tree a)

data Rose a = MkRose a (List (Rose a))

%hint addressTo : ToJSON Address
addressTo = %runElab deriveToJSON defaultOptions
%hint addressFrom : FromJSON Address
addressFrom = %runElab deriveFromJSON defaultOptions
%hint personTo : ToJSON Person
personTo = %runElab deriveToJSON defaultOptions
%hint personFrom : FromJSON Person
personFrom = %runElab deriveFromJSON defaultOptions
%hint colourTo : ToJSON Colour
colourTo = %runElab deriveToJSON defaultOptions
%hint colourFrom : FromJSON Colour
colourFrom = %runElab deriveFromJSON defaultOptions
%hint shapeTo : ToJSON Shape
shapeTo = %runElab deriveToJSON defaultOptions
%hint shapeFrom : FromJSON Shape
shapeFrom = %runElab deriveFromJSON defaultOptions
%hint treeTo : ToJSON a => ToJSON (Tree a)
treeTo = %runElab deriveToJSON defaultOptions
%hint treeFrom : FromJSON a => FromJSON (Tree a)
treeFrom = %runElab deriveFromJSON defaultOptions
%hint roseTo : ToJSON a => ToJSON (Rose a)
roseTo = %runElab deriveToJSON defaultOptions
%hint roseFrom : FromJSON a => FromJSON (Rose a)
roseFrom = %runElab deriveFromJSON defaultOptions

-- Options: keys and tags renamed.
record Config where
  constructor MkConfig
  maxConnections : Int
  hostName : String

snake : String -> String
snake = pack . concatMap (\c => if isUpper c then ['_', toLower c] else [c]) . unpack

%hint configTo : ToJSON Config
configTo = %runElab deriveToJSON ({ fieldName := snake } defaultOptions)
%hint configFrom : FromJSON Config
configFrom = %runElab deriveFromJSON ({ fieldName := snake } defaultOptions)

shapeTo2 : ToJSON Shape
shapeTo2 = %runElab deriveToJSON ({ tagField := "kind", contentsField := "value", constructorTag := toLower } defaultOptions)

-- A hand-written implementation with the helpers.
record Point where
  constructor MkPoint
  x, y : Double

ToJSON Point where
  toJSON p = JObject [("x", toJSON p.x), ("y", toJSON p.y)]

FromJSON Point where
  fromJSON = withObject "Point" $ \o => [| MkPoint (field o "x") (field o "y") |]

-- Unsupported types
data Vec : Nat -> Type -> Type where
  VNil : Vec Z a
  VCons : a -> Vec n a -> Vec (S n) a

data Some : Type where
  MkSome : {0 t : Type} -> t -> Some

data Stream' : Type where
  MkStream : Int -> Inf Stream' -> Stream'

failing "it is an indexed family"
  vecTo : ToJSON a => ToJSON (Vec n a)
  vecTo = %runElab deriveToJSON defaultOptions

failing "existential or dependent field"
  someTo : ToJSON Some
  someTo = %runElab deriveToJSON defaultOptions

failing "lazy or infinite field"
  streamTo : ToJSON Stream'
  streamTo = %runElab deriveToJSON defaultOptions

Eq Address where
  a == b = a.street == b.street && a.zip == b.zip
Eq Person where
  a == b = a.name == b.name && a.age == b.age && a.address == b.address && a.nicknames == b.nicknames
Eq Colour where
  Red == Red = True
  Green == Green = True
  Blue == Blue = True
  _ == _ = False
Eq Shape where
  Circle a == Circle b = a == b
  Rect a b == Rect c d = a == c && b == d
  Dot == Dot = True
  Labelled a b == Labelled c d = a == c && b == d
  _ == _ = False
Eq a => Eq (Tree a) where
  Leaf == Leaf = True
  Node l x r == Node l' x' r' = l == l' && x == x' && r == r'
  _ == _ = False
Eq a => Eq (Rose a) where
  MkRose x xs == MkRose y ys = x == y && assert_total (xs == ys)
Eq Config where
  a == b = a.maxConnections == b.maxConnections && a.hostName == b.hostName
Eq Point where
  a == b = a.x == b.x && a.y == b.y

Show Point where
  show p = "MkPoint " ++ show p.x ++ " " ++ show p.y
Show Address where
  show a = "MkAddress " ++ show a.street ++ " " ++ show a.zip
Show Person where
  show p = "MkPerson " ++ show p.name ++ " " ++ show p.age ++ " (" ++ show p.address ++ ") " ++ show p.nicknames

main : IO ()
main = do
  -- primitives and containers
  roundTrip "unit" ()
  roundTrip "bool" True
  roundTrip "string" "caf\233 \"\n\128512"
  roundTrip "char" 'z'
  roundTrip "double" (-2.5e-3)
  roundTrip "int" (the Int (-9007199254740991))
  roundTrip "integer" (the Integer 123456789012345)
  roundTrip "nat" (the Nat 42)
  roundTrip "bits8" (the Bits8 255)
  roundTrip "bits16" (the Bits16 65535)
  roundTrip "bits32" (the Bits32 4294967295)
  roundTrip "bits64" (the Bits64 9007199254740992)
  roundTrip "int8" (the Int8 (-128))
  roundTrip "int16" (the Int16 (-32768))
  roundTrip "int32" (the Int32 (-2147483648))
  roundTrip "int64" (the Int64 (-9007199254740992))
  roundTrip "maybe" (the (List (Maybe Int)) [Just 1, Nothing, Just 3])
  roundTrip "list" (the (List (List Int)) [[1, 2], [], [3]])
  roundTrip "snoclist" (the (SnocList String) [< "a", "b"])
  roundTrip "list1" (the (List1 Int) (1 ::: [2, 3]))
  roundTrip "vect" (the (Vect 3 Bool) [True, False, True])
  roundTrip "pair" (the (Int, String, Bool) (1, "two", True))
  roundTrip "either" (the (List (Either String Int)) [Left "e", Right 5])
  roundTrip "json" (JObject [("a", JArray [JNull, JNumber 1])])
  putStrLn (toJSONText (SortedMap.fromList [("b", the Int 2), ("a", 1)]))
  printLn (map SortedMap.toList (fromJSONText {a = SortedMap String Int} "{\"x\":1,\"y\":2,\"x\":3}"))
  printLn (map (sort . HashMap.toList) (fromJSONText {a = HashMap String Bool} "{\"p\":true,\"q\":false}"))
  -- range and shape errors
  decodeAs Int "1.5"
  decodeAs Int "1e19"
  decodeAs Nat "-1"
  decodeAs Bits8 "256"
  decodeAs Int8 "-129"
  decodeAs Bits64 "18446744073709551616"
  decodeAs Char "\"ab\""
  decodeAs (List Int) "[1, 2, \"3\"]"
  decodeAs (Vect 2 Int) "[1, 2, 3]"
  decodeAs (List1 Int) "[]"
  decodeAs (Int, Int) "[1]"
  decodeAs (Either Int Int) "{\"Middle\": 1}"
  decodeAs (List (Maybe Bool)) "[true, null, 0]"
  decodeAs Int "[1,"
  -- derived
  let ann = MkPerson "Ann" 41 (MkAddress "Main St" Nothing) (the (List String) ["A", "Annie"])
  putStrLn (toJSONText ann)
  roundTrip "person" ann
  roundTrip "colours" (the (List Colour) [Red, Green, Blue])
  roundTrip "shapes" (the (List Shape) [Circle 1.5, Rect 1 2, Dot, Labelled "x" 3])
  roundTrip "tree" (Node (Node Leaf 1 Leaf) (the Int 2) (Node Leaf 3 Leaf))
  roundTrip "rose" (MkRose "r" [MkRose "a" [], MkRose "b" [MkRose "c" []]])
  roundTrip "config" (MkConfig 10 "localhost")
  roundTrip "point" (MkPoint 1.5 (-2))
  putStrLn (toJSONText (MkConfig 10 "localhost"))
  traverse_ (putStrLn . toJSONText @{shapeTo2}) (the (List Shape) [Circle 1.5, Dot, Labelled "x" 3])
  decodeAs Person "{\"name\":\"Bob\",\"age\":7,\"address\":{\"street\":\"High St\"},\"nicknames\":[],\"extra\":1}"
  decodeAs Person "{\"name\":\"Bob\",\"age\":7,\"address\":{\"street\":\"High St\",\"zip\":\"x\"},\"nicknames\":[]}"
  decodeAs Person "{\"name\":\"Bob\",\"address\":{\"street\":\"High St\"},\"nicknames\":[]}"
  decodeAs Person "{\"name\":\"Bob\",\"age\":7,\"address\":{\"street\":\"High St\"},\"nicknames\":[\"a\", 2]}"
  decodeAs Point "{\"x\": 1, \"y\": true}"
  printLn (map (const ()) (fromJSONText {a = Colour} "\"Purple\""))
  printLn (map (const ()) (fromJSONText {a = List Shape} "[{\"tag\":\"Rect\",\"contents\":[1]}]"))
  printLn (map (const ()) (fromJSONText {a = Shape} "{\"contents\":1}"))
  printLn (map (const ()) (fromJSONText {a = Tree Int} "{\"tag\":\"Node\",\"contents\":[{\"tag\":\"Leaf\"},1,{\"tag\":\"Node\",\"contents\":[{\"tag\":\"Leaf\"},\"2\",{\"tag\":\"Leaf\"}]}]}"))
