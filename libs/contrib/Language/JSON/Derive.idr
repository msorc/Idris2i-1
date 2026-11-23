||| Deriving `ToJSON` and `FromJSON` implementations by elaborator reflection.
|||
||| ```idris
||| import Language.JSON.Derive
|||
||| %language ElabReflection
|||
||| record Person where
|||   constructor MkPerson
|||   name : String
|||   age : Int
|||   email : Maybe String
|||
||| %hint
||| personToJSON : ToJSON Person
||| personToJSON = %runElab deriveToJSON defaultOptions
|||
||| %hint
||| personFromJSON : FromJSON Person
||| personFromJSON = %runElab deriveFromJSON defaultOptions
|||
||| data Tree a = Leaf | Node (Tree a) a (Tree a)
|||
||| %hint
||| treeToJSON : ToJSON a => ToJSON (Tree a)
||| treeToJSON = %runElab deriveToJSON defaultOptions
||| ```
|||
||| The `%hint` makes the definition an implementation that other code finds;
||| it is needed for a type that contains itself inside another type (as in
||| `data Rose a = Rose a (List (Rose a))`), and is what one wants anyway.
||| A parameter of the type (the `a` of `Tree a`) needs its own `ToJSON` or
||| `FromJSON` constraint in the signature if a field mentions it.
|||
||| # The encoding
|||
||| With `defaultOptions` (the same as the default of Haskell's `aeson`):
|||
|||  * a type whose constructors have no fields (an enumeration) is encoded as
|||    the name of the constructor, as a string: `"Red"`;
|||  * a type with one constructor whose fields all have names (a record) is
|||    encoded as an object with a member per field:
|||    `{"name": "Ann", "age": 41, "email": null}`;
|||  * a type with one constructor with unnamed fields is encoded as the
|||    value of the field if there is one, and as an array of the values if
|||    there are several;
|||  * any other type (a sum) is encoded as an object with the name of the
|||    constructor in the member `"tag"`, and
|||      - the fields of the constructor as further members if they all have
|||        names: `{"tag": "Circle", "radius": 1.5}`,
|||      - nothing else for a constructor without fields: `{"tag": "Leaf"}`,
|||      - the value of the field in the member `"contents"` if it has one
|||        unnamed field, and an array of the values there if it has several:
|||        `{"tag": "Node", "contents": [{"tag": "Leaf"}, 1, {"tag": "Leaf"}]}`.
|||
||| A field of a type `Maybe a` that is missing from an object decodes as
||| `Nothing` (and `Nothing` is encoded as `null`).  Members of an object that
||| are not fields are ignored when decoding.  `Options` changes the names of
||| the members and of the tags.
|||
||| The types that are not supported, with an error at compile time, are
||| indexed families (`Vect n a`, whose constructors fix the index),
||| constructors with existential or dependent fields (whose type mentions
||| another field or an implicit argument that is not a parameter), with
||| erased or auto-implicit fields, and with lazy or infinite fields.
module Language.JSON.Derive

import Data.Bits
import Data.String

import public Language.JSON.Typed
import public Language.Reflection

%language ElabReflection
%default total

------------------------------------------------------------------------
-- Options
------------------------------------------------------------------------

||| How derived implementations name things.
public export
record Options where
  constructor MkOptions
  ||| The key of a field, from the name of the field.
  fieldName : String -> String
  ||| The tag of a constructor, from its name (without namespace).
  constructorTag : String -> String
  ||| The member of the object of a sum that holds the tag.
  tagField : String
  ||| The member of the object of a sum that holds unnamed fields.
  contentsField : String

||| Keys and tags are the names in the source; the members of sums are
||| `"tag"` and `"contents"`.
public export
defaultOptions : Options
defaultOptions = MkOptions id id "tag" "contents"

------------------------------------------------------------------------
-- Helpers that the derived code calls
------------------------------------------------------------------------

||| Used by derived code: like `field`, with the decoder given.
export
fieldWith : (JSON -> Either DecodeError a) -> List (String, JSON) -> String -> Either DecodeError a
fieldWith dec ms k = case lookup k ms of
  Just v => inKey k (dec v)
  Nothing => Left (Mismatch [Key k] "missing member")

||| Used by derived code: the elements of an array of length `n`.
export
arrayOfLength : (name : String) -> (n : Nat) -> JSON -> Either DecodeError (List JSON)
arrayOfLength name n (JArray xs) =
  if length xs == n then Right xs
  else failDecode ("expected an array of length " ++ show n ++ " (" ++ name ++ "), got one of length " ++ show (length xs))
arrayOfLength name n j = unexpected ("an array of length " ++ show n ++ " (" ++ name ++ ")") j

||| Used by derived code: decode the element at an index of a list that is
||| known to be long enough.
export
elemWith : (JSON -> Either DecodeError a) -> List JSON -> Nat -> Either DecodeError a
elemWith dec xs i = case drop i xs of
  (x :: _) => inIndex i (dec x)
  [] => Left (Mismatch [Index i] "missing element")

||| Used by derived code: the value of an enumeration from its tag.
export
decodeEnum : (name : String) -> List (String, a) -> JSON -> Either DecodeError a
decodeEnum name tags (JString s) = case lookup s tags of
  Just x => Right x
  Nothing => failDecode ("unknown constructor of " ++ name ++ ": " ++ encodeText (JString s)
                         ++ " (expected one of " ++ joinBy ", " (map fst tags) ++ ")")
decodeEnum name _ j = unexpected (name ++ " (a string)") j

||| Used by derived code: decode an object of a sum, by the tag in the
||| member `tagField`, with the decoder of the members for that tag.
export
decodeTagged : (tagField : String) -> (name : String) ->
               List (String, List (String, JSON) -> Either DecodeError a) ->
               JSON -> Either DecodeError a
decodeTagged tf name decs (JObject ms) = case lookup tf ms of
  Just (JString t) => case lookup t decs of
    Just dec => dec ms
    Nothing => Left (Mismatch [Key tf] ("unknown constructor of " ++ name ++ ": " ++ encodeText (JString t)
                                        ++ " (expected one of " ++ joinBy ", " (map fst decs) ++ ")"))
  Just j => Left (Mismatch [Key tf] ("expected a constructor name (a string), got " ++ describe j))
  Nothing => Left (Mismatch [Key tf] ("missing member (the constructor of " ++ name ++ ")"))
decodeTagged tf name _ j = unexpected (name ++ " (an object)") j

||| Used by derived code: decode the member `contentsField` of an object.
export
contentsWith : (contentsField : String) -> (JSON -> Either DecodeError a) ->
               List (String, JSON) -> Either DecodeError a
contentsWith cf dec ms = fieldWith dec ms cf

||| Used by derived code: an implementation from its function.
export
mkToJSON : (a -> JSON) -> ToJSON a
mkToJSON f = MkToJSON f (\x => encodeBuilder (f x)) (\x => writeValue (f x))

||| Used by derived code: an implementation from its function and its
||| writer.
export
mkToJSONWith : (a -> JSON) -> (a -> JSONWriter) -> ToJSON a
mkToJSONWith f wr = MkToJSON f (\x => byteString (runWriter (wr x))) wr

-- (the default of `fromJSONAt`)
viaValue : (JSON -> Either DecodeError a) -> Input -> (pos : Int) -> Step a
viaValue f b p = case valueAt b p of
  StepOk j q => case f j of
                  Right x => StepOk x q
                  Left _ => StepFail
  StepFail => StepFail

||| Used by derived code: an implementation from its function.
export
mkFromJSON : (JSON -> Either DecodeError a) -> FromJSON a
mkFromJSON f = MkFromJSON f Nothing (viaValue f)

||| Used by derived code: an implementation from its function and its
||| decoder in place (see `fromJSONAt`).
export
mkFromJSONWith : (JSON -> Either DecodeError a) ->
                 (Input -> (pos : Int) -> Step a) -> FromJSON a
mkFromJSONWith f at = MkFromJSON f Nothing at

||| Used by derived code: give a value to a function.  It is not inlined,
||| so that a value made for a decoder or a writer (a key, the
||| implementation of a field of a type such as `List String`) is made
||| once, when the decoder is (were the function applied where it is
||| written, the value would be made at every call of the decoder).
export %noinline
shareValue : a -> (a -> r) -> r
shareValue x f = f x

||| Used by derived code: write `a`, then `b`.
export %inline
writeThen : JSONWriter -> JSONWriter -> JSONWriter
writeThen a b o p w = case a o p w of
  MkIORes q w => b o q w

||| Used by derived code: the member `k` of an object at `pos` (after
||| whitespace), and the continuation with the position of its value.
export %inline
stepKey : Input -> (pos : Int) -> Key -> (Int -> Step r) -> Step r
stepKey b p k cont = let q = keyAt b p k in if q < 0 then StepFail else cont q

||| Used by derived code: a comma after a member (and whitespace).
export %inline
stepComma : Input -> (pos : Int) -> (Int -> Step r) -> Step r
stepComma b p cont =
  let q = skipWsAt b p in
  if byteAtOr0 b q == 44 then cont (skipWsAt b (q + 1)) else StepFail

||| Used by derived code: the `}` that ends an object (after whitespace).
export %inline
stepClose : Input -> (pos : Int) -> (Int -> Step r) -> Step r
stepClose b p cont =
  let q = skipWsAt b p in
  if byteAtOr0 b q == 125 then cont (q + 1) else StepFail

||| Used by derived code: the `{` that starts an object, and the
||| continuation with the input of its members (see `enter`) and the
||| position after the `{` (and whitespace).
export %inline
stepOpen : Input -> (pos : Int) -> (Input -> Int -> Step r) -> Step r
stepOpen b p cont =
  if byteAtOr0 b p /= 123 then StepFail else
  case enter b of
    Nothing => StepFail
    Just inner => cont inner (skipWsAt b (p + 1))

||| Used by derived code: go on with a value decoded in place.
export %inline
stepWith : Step a -> (a -> Int -> Step r) -> Step r
stepWith (StepOk x q) cont = cont x q
stepWith StepFail _ = StepFail

||| Used by derived code: a value decoded in place with a function of the
||| `JSON` value.
export
stepVia : (JSON -> Either DecodeError a) -> Input -> (pos : Int) -> Step a
stepVia = viaValue

------------------------------------------------------------------------
-- Looking at the type
------------------------------------------------------------------------

-- A field of a constructor: its name if it has one, its type, and whether
-- it is of the type being derived itself.
record Field where
  constructor MkField
  fName : Maybe String
  fType : TTImp
  fRec : Bool

record Con where
  constructor MkCon
  conName : Name
  conFields : List Field

-- A name without its namespace, as a string.
nameStr : Name -> String
nameStr (UN (Basic s)) = s
nameStr (NS _ n) = nameStr n
nameStr n = show n

-- The name given in the source, if any (not one made up by the compiler).
userName : Maybe Name -> Maybe String
userName (Just n) = case dropNS n of
  UN (Basic s) => Just s
  _ => Nothing
userName Nothing = Nothing

binderName : Maybe Name -> List Name
binderName (Just n) = [n]
binderName Nothing = []

-- The explicit arguments.
explicits : List (Argument TTImp) -> List TTImp
explicits [] = []
explicits (Arg _ t :: rest) = t :: explicits rest
explicits (_ :: rest) = explicits rest

headName : TTImp -> Maybe Name
headName t = map (\v => snd v.head) (appView t)

-- Does the variable occur in the type?  (For the types of fields: the
-- forms that can occur there are looked into, and any other counts as not
-- mentioning it.)
mentions : Name -> TTImp -> Bool
mentions x (IVar _ n) = n == x
mentions x (IApp _ f a) = mentions x f || mentions x a
mentions x (INamedApp _ f _ a) = mentions x f || mentions x a
mentions x (IAutoApp _ f a) = mentions x f || mentions x a
mentions x (IPi _ _ _ _ a b) = mentions x a || mentions x b
mentions x (ILam _ _ _ _ a b) = mentions x a || mentions x b
mentions x (IDelayed _ _ a) = mentions x a
mentions x _ = False

-- `[0, 1 .. n - 1]`
indices : Nat -> List Nat
indices n = go n []
  where
    go : Nat -> List Nat -> List Nat
    go Z acc = acc
    go (S k) acc = go k (k :: acc)

isLazy : TTImp -> Bool
isLazy (IDelayed _ _ _) = True
isLazy _ = False

parameters (intf : String) (tyName : Name)

  unsupported : String -> Elab a
  unsupported why = fail ("Language.JSON.Derive: cannot derive " ++ intf ++ " for "
                          ++ show (dropNS tyName) ++ ": " ++ why)

  -- The names of the variables that the return type of a constructor is
  -- applied to, which must all be distinct variables (parameters).
  returnParams : Name -> TTImp -> Elab (List Name)
  returnParams cn ret = do
    let Just v = appView ret
      | Nothing => unsupported ("unexpected return type of " ++ show (dropNS cn))
    let args = explicits (v.args <>> [])
    for args $ \a => case a of
      IVar _ n => pure n
      _ => unsupported ("it is an indexed family (the constructor " ++ show (dropNS cn)
                        ++ " returns " ++ show ret ++ "); only parameters are supported")

  analyse : (Name, TTImp) -> Elab Con
  analyse (cn, ty) = go [] [<] ty
    where
      go : List Name -> SnocList Field -> TTImp -> Elab Con
      go bs acc (IPi _ rig ExplicitArg mn argTy rest) = do
        when (rig == M0) $
          unsupported ("the constructor " ++ show (dropNS cn) ++ " has an erased field")
        when (isLazy argTy) $
          unsupported ("the constructor " ++ show (dropNS cn) ++ " has a lazy or infinite field")
        go (binderName mn ++ bs) (acc :< MkField (userName mn) argTy (headName argTy == Just tyName)) rest
      go bs acc (IPi _ _ AutoImplicit _ _ _) =
        unsupported ("the constructor " ++ show (dropNS cn) ++ " has an auto-implicit argument (a constraint)")
      go bs acc (IPi _ _ _ mn _ rest) = go (binderName mn ++ bs) acc rest
      go bs acc ret = do
        ps <- returnParams cn ret
        let fields = acc <>> []
        let others = filter (\b => not (b `elem` ps)) bs
        for_ fields $ \f =>
          for_ others $ \b =>
            when (mentions b f.fType) $
              unsupported ("a field of the constructor " ++ show (dropNS cn) ++ " has the type "
                           ++ show f.fType ++ ", which depends on " ++ show b
                           ++ " (an existential or dependent field)")
        pure (MkCon cn fields)

-- The type constructor and its analysed data constructors, from the goal.
inspect : (intf : String) -> Elab (TTImp, Name, List Con)
inspect intf = do
  Just (IApp _ _ t) <- goal
    | _ => fail ("Language.JSON.Derive: expected a goal of the form `" ++ intf ++ " t`")
  let Just v = appView t
    | Nothing => fail ("Language.JSON.Derive: expected a goal of the form `" ++ intf
                       ++ " t` for a type constructor t, got " ++ show t)
  [(f, _)] <- getType (snd v.head)
    | [] => fail ("Language.JSON.Derive: " ++ show (snd v.head) ++ " is not in scope")
    | _ => fail ("Language.JSON.Derive: " ++ show (snd v.head) ++ " is ambiguous")
  [(_, MkNameInfo (TyCon _ _))] <- getInfo f
    | _ => fail ("Language.JSON.Derive: " ++ show (snd v.head) ++ " is not a data type")
  cnames <- getCons f
  cs <- for cnames $ \c => do
          [(cn, cty)] <- getType c
            | _ => fail ("Language.JSON.Derive: " ++ show c ++ " is ambiguous")
          pure (cn, cty)
  when (null cs) $ fail ("Language.JSON.Derive: cannot derive " ++ intf ++ " for "
                         ++ show (dropNS f) ++ ": it has no constructors")
  cons <- traverse (analyse intf f) cs
  pure (t, f, cons)

------------------------------------------------------------------------
-- Building terms
------------------------------------------------------------------------

str : String -> TTImp
str s = IPrimVal emptyFC (Str s)

-- A literal of type `Nat`.
natLit : Nat -> TTImp
natLit n = IApp emptyFC `(fromInteger) (IPrimVal emptyFC (BI (cast n)))

var : String -> TTImp
var s = IVar emptyFC (UN (Basic s))

listOf : List TTImp -> TTImp
listOf = foldr (\x, acc => `(~(x) :: ~(acc))) `(Nil)

pairOf : TTImp -> TTImp -> TTImp
pairOf a b = `(MkPair ~(a) ~(b))

conTag : Options -> Con -> String
conTag opts c = opts.constructorTag (nameStr (dropNS c.conName))

hasName : Field -> Bool
hasName f = case f.fName of
  Just _ => True
  Nothing => False

isNamed : Con -> Bool
isNamed c = not (null c.conFields) && all (\f => hasName f) c.conFields

key : Options -> Field -> String
key opts f = case f.fName of
  Just n => opts.fieldName n
  Nothing => ""

-- The variables of the fields of a constructor.
fieldVars : Con -> List String
fieldVars c = map (\i => "x" ++ show i) (indices (length c.conFields))

------------------------------------------------------------------------
-- ToJSON
------------------------------------------------------------------------

-- `assert_total x`
assertTotal : TTImp -> TTImp
assertTotal = IApp emptyFC `(assert_total)

encodeField : Name -> Field -> String -> TTImp
encodeField fun f v =
  if f.fRec then assertTotal (IApp emptyFC (IVar emptyFC fun) (var v))
  else assertTotal (IApp emptyFC `(Language.JSON.Typed.toJSON) (var v))

-- The JSON of a constructor, given the variables of its fields.
encodeCon : Options -> Name -> (single, enum : Bool) -> Con -> TTImp
encodeCon opts fun single enum c =
  let vs = fieldVars c
      encs = zipWith (encodeField fun) c.conFields vs
      members = zipWith (\f, e => pairOf (str (key opts f)) e) c.conFields encs
      tag = `(JString ~(str (conTag opts c)))
      tagMember = pairOf (str opts.tagField) tag
  in if enum then tag
     else if single then
       (if isNamed c then `(JObject ~(listOf members))
        else case encs of
               [e] => e
               _ => `(JArray ~(listOf encs)))
     else if isNamed c then `(JObject ~(listOf (tagMember :: members)))
     else case encs of
            [] => `(JObject ~(listOf [tagMember]))
            [e] => `(JObject ~(listOf [tagMember, pairOf (str opts.contentsField) e]))
            _ => `(JObject ~(listOf [tagMember, pairOf (str opts.contentsField) `(JArray ~(listOf encs))]))

-- A key as a JSON string literal, escaped as `encode` escapes it (written
-- without `encode`, which cannot run at elaboration time).
quoteKey : String -> String
quoteKey k = "\"" ++ concatMap esc (unpack k) ++ "\""
  where
    hex : Int -> Char
    hex n = if n < 10 then chr (48 + n) else chr (87 + n)
    esc : Char -> String
    esc '"' = "\\\""
    esc '\\' = "\\\\"
    esc c = let n = ord c in
            if n >= 32 then singleton c
            else if n == 8 then "\\b" else if n == 9 then "\\t" else if n == 10 then "\\n"
            else if n == 12 then "\\f" else if n == 13 then "\\r"
            else pack ['\\', 'u', '0', '0', hex (shiftR n 4), hex (n .&. 15)]

-- Is the implementation for a field made when it is used (that of an
-- applied type, `List String` say), so that it is worth making once?  Only
-- for a type without parameters, whose fields' types are closed.
shared : TTImp -> Field -> Bool
shared (IVar _ _) f = not f.fRec && (case f.fType of IApp _ _ _ => True; _ => False)
shared _ _ = False

-- The writer of a record (a single constructor whose fields all have
-- names), given the variables of its fields: the members, with the keys
-- and punctuation written in advance.
writeRecord : Options -> TTImp -> Name -> Con -> TTImp
writeRecord opts t fun c =
  let vs = fieldVars c
      parts = zipWith3 (\f, v, i =>
                 let pre = (if i == the Nat 0 then "{" else ",") ++ quoteKey (key opts f) ++ ":"
                     wv = if f.fRec then `(writeValue (assert_total (~(IVar emptyFC fun) ~(var v))))
                          else if shared t f then `(~(var ("w" ++ v)) ~(var v))
                          else `(assert_total (Language.JSON.Typed.toWriter ~(var v)))
                 in `(writeThen (writeRaw ~(str pre)) ~(wv)))
               c.conFields vs (indices (length c.conFields))
  in foldr (\x, acc => `(writeThen ~(x) ~(acc))) `(writeByte 125) parts

||| Derive `ToJSON` for a record or sum type (see the module header for the
||| encoding):
|||
||| ```idris
||| %hint
||| personToJSON : ToJSON Person
||| personToJSON = %runElab deriveToJSON defaultOptions
||| ```
export
deriveToJSON : Options -> Elab (ToJSON a)
deriveToJSON opts = do
  (t, f, cons) <- inspect "ToJSON"
  let fun = UN (Basic ("toJSON" ++ nameStr (dropNS f)))
  let single = length cons == 1
  let enum = all (null . conFields) cons
  let clauses = map (\c => PatClause emptyFC
                        (IApp emptyFC (IVar emptyFC fun)
                              (foldl (\acc, v => IApp emptyFC acc (var v)) (IVar emptyFC c.conName) (fieldVars c)))
                        (encodeCon opts fun single enum c)) cons
  let ty = MkTy emptyFC (NoFC fun) `(~(t) -> JSON)
  case cons of
    [c] => if isNamed c && not enum
      then do
        -- (a record: a writer too, which writes the members directly)
        let wfun = UN (Basic ("toWriter" ++ nameStr (dropNS f)))
        -- (the writers of the shared fields are arguments, made once)
        let sh = filter (\(fl, _) => shared t fl) (zip c.conFields (fieldVars c))
        let wty = MkTy emptyFC (NoFC wfun)
                    (foldr (\(fl, _), acc => IPi emptyFC MW ExplicitArg Nothing `(~(fl.fType) -> JSONWriter) acc)
                           `(~(t) -> JSONWriter) sh)
        let wclause = PatClause emptyFC
                        (IApp emptyFC (foldl (\acc, (_, v) => IApp emptyFC acc (var ("w" ++ v))) (IVar emptyFC wfun) sh)
                              (foldl (\acc, v => IApp emptyFC acc (var v)) (IVar emptyFC c.conName) (fieldVars c)))
                        (writeRecord opts t fun c)
        let inst = foldr (\(fl, v), acc =>
                            `(shareValue (the (~(fl.fType) -> JSONWriter) Language.JSON.Typed.toWriter)
                                ~(ILam emptyFC MW ExplicitArg (Just (UN (Basic ("w" ++ v)))) `(_) acc)))
                         `(mkToJSONWith ~(IVar emptyFC fun)
                              ~(foldl (\acc, (_, v) => IApp emptyFC acc (var ("w" ++ v))) (IVar emptyFC wfun) sh))
                         sh
        check $ ILocal emptyFC
          [ IClaim (MkFCVal emptyFC (MkIClaimData MW Private [Totality Total] ty))
          , IDef emptyFC fun clauses
          , IClaim (MkFCVal emptyFC (MkIClaimData MW Private [Totality Total] wty))
          , IDef emptyFC wfun [wclause]
          ] inst
      else plain ty clauses fun
    _ => plain ty clauses fun
  where
    plain : ITy -> List Clause -> Name -> Elab (ToJSON a)
    plain ty clauses fun =
      check $ ILocal emptyFC
        [ IClaim (MkFCVal emptyFC (MkIClaimData MW Private [Totality Total] ty))
        , IDef emptyFC fun clauses
        ] `(mkToJSON ~(IVar emptyFC fun))

------------------------------------------------------------------------
-- FromJSON
------------------------------------------------------------------------

decoderOf : Name -> Field -> TTImp
decoderOf fun f = if f.fRec then IVar emptyFC fun else `(Language.JSON.Typed.fromJSON)

-- `pure C <*> a1 <*> ... <*> an`
applyAll : Name -> List TTImp -> TTImp
applyAll cn = foldl (\acc, a => `(~(acc) <*> ~(a))) `(pure ~(IVar emptyFC cn))

-- Decode the members of an object (the variable `o`) into a constructor
-- with named fields.
decodeNamed : Options -> Name -> Con -> TTImp
decodeNamed opts fun c =
  applyAll c.conName (map (\f =>
    if f.fRec then `(assert_total (fieldWith ~(IVar emptyFC fun) o ~(str (key opts f))))
    else `(assert_total (field o ~(str (key opts f))))) c.conFields)

-- Decode the value `v` as the unnamed fields of a constructor.
decodePositional : Name -> String -> Con -> TTImp -> TTImp
decodePositional fun name c v = case c.conFields of
  [f] => `(map ~(IVar emptyFC c.conName) (assert_total (~(decoderOf fun f) ~(v))))
  fs => `(arrayOfLength ~(str name) ~(natLit (length fs)) ~(v) >>= \xs =>
            ~(applyAll c.conName (zipWith (\f, i => `(assert_total (elemWith ~(decoderOf fun f) xs ~(natLit i))))
                                          fs (indices (length fs)))))

-- The decoder of the members `o` of the object of a sum for a constructor.
decodeInSum : Options -> Name -> String -> Con -> TTImp
decodeInSum opts fun name c =
  if isNamed c then decodeNamed opts fun c
  else case c.conFields of
         [] => `(pure ~(IVar emptyFC c.conName))
         _ => `(contentsWith ~(str opts.contentsField) (\cv => ~(decodePositional fun name c `(cv))) o)

-- The decoder in place of a record (see `fromJSONAt`), given the decoder
-- of the JSON value `fun` for its fields of its own type: the members must
-- come in the order of the fields, once each and with no other member;
-- otherwise it fails, and `fromJSON` decodes the value.
decodeRecordAt : Options -> TTImp -> Name -> Con -> TTImp
decodeRecordAt opts t fun c =
  let vs = fieldVars c
      n = length c.conFields
      done = `(stepClose b p (\p => StepOk ~(foldl (\acc, v => IApp emptyFC acc (var v)) (IVar emptyFC c.conName) vs) p))
      step : (Field, String, Nat) -> TTImp -> TTImp
      step (f, v, i) rest =
        let dec = if f.fRec then `(stepVia ~(IVar emptyFC fun) b p)
                  else if shared t f then `(~(var ("d" ++ v)) b p)
                  else `(assert_total (Language.JSON.Typed.fromJSONAt b p))
            body = `(stepKey b p ~(var ("k" ++ v)) (\p => stepWith ~(dec) ~(ILam emptyFC MW ExplicitArg (Just (UN (Basic v))) `(_) `(\p => ~(rest)))))
        in if i == 0 then body else `(stepComma b p (\p => ~(body)))
      chain = foldr step done (zip c.conFields (zip vs (indices n)))
      -- (the keys are made once, when the implementation is: see `withKey`)
      keyed = foldr (\(f, v), acc => `(shareValue (jsonKey ~(str (key opts f)))
                                          ~(ILam emptyFC MW ExplicitArg (Just (UN (Basic ("k" ++ v)))) `(Key) acc)))
                    `(\b0, p => stepOpen b0 p (\b, p => ~(chain)))
                    (zip c.conFields vs)
      -- (the decoders of the shared fields, made once too)
      decs = foldr (\(f, v), acc =>
                      if shared t f
                         then `(shareValue (the (Input -> Int -> Step ~(f.fType)) Language.JSON.Typed.fromJSONAt)
                                  ~(ILam emptyFC MW ExplicitArg (Just (UN (Basic ("d" ++ v)))) `(_) acc))
                         else acc)
                   keyed (zip c.conFields vs)
  in decs

||| Derive `FromJSON` for a record or sum type (see the module header for the
||| encoding):
|||
||| ```idris
||| %hint
||| personFromJSON : FromJSON Person
||| personFromJSON = %runElab deriveFromJSON defaultOptions
||| ```
export
deriveFromJSON : Options -> Elab (FromJSON a)
deriveFromJSON opts = do
  (t, f, cons) <- inspect "FromJSON"
  let fun = UN (Basic ("fromJSON" ++ nameStr (dropNS f)))
  let name = nameStr (dropNS f)
  let enum = all (null . conFields) cons
  let body : TTImp
      body = if enum
        then `(decodeEnum ~(str name) ~(listOf (map (\c => pairOf (str (conTag opts c)) (IVar emptyFC c.conName)) cons)) j)
        else case cons of
          [c] => if isNamed c
                   then `(withObject ~(str name) (\o => ~(decodeNamed opts fun c)) j)
                   else decodePositional fun name c `(j)
          _ => `(decodeTagged ~(str opts.tagField) ~(str name)
                   ~(listOf (map (\c => pairOf (str (conTag opts c)) `(\o => ~(decodeInSum opts fun name c))) cons)) j)
  let ty = MkTy emptyFC (NoFC fun) `(JSON -> Either DecodeError ~(t))
  let decls = [ IClaim (MkFCVal emptyFC (MkIClaimData MW Private [Totality Total] ty))
              , IDef emptyFC fun [PatClause emptyFC (IApp emptyFC (IVar emptyFC fun) (var "j")) body] ]
  case cons of
    [c] => if isNamed c && not enum
             then check $ ILocal emptyFC decls
                    `(mkFromJSONWith ~(IVar emptyFC fun) ~(decodeRecordAt opts t fun c))
             else check $ ILocal emptyFC decls `(mkFromJSON ~(IVar emptyFC fun))
    _ => check $ ILocal emptyFC decls `(mkFromJSON ~(IVar emptyFC fun))
