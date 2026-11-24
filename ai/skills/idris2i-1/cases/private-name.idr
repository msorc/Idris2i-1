-- expect: E0202
namespace Lib
  secret : Nat
  secret = 1

leak : Nat
leak = Lib.secret
