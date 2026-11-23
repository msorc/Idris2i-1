# Make throwaway certificates for the tests of the tls pool, in the
# directory `certs` of the current one, with the openssl command-line tool.
# Nothing here is committed: the keys are made anew by every run.
#
#   ca.pem, ca.key            a certification authority
#   ca2.pem                   another one, which signs nothing the tests trust
#   server.pem, server.key    localhost (DNS:localhost, IP:127.0.0.1), by ca, ECDSA P-256
#   chain.pem                 server.pem then ca.pem
#   rsa.pem, rsa.key          the same with RSA-2048
#   expired.pem, expired.key  localhost, by ca, expired in 2020
#   other.pem, other.key      other.example (and *.other.example), by ca
#   client.pem, client.key    a client certificate (CN=test client), by ca
#   rogue.pem, rogue.key      localhost, by ca2
#
# Usage: . ../gencerts.sh   (sets $certs)

certs="$PWD/certs"
rm -rf "$certs"
mkdir -p "$certs"

_ossl() { openssl "$@" 2>/dev/null; }

_key() { # name type
  case "$2" in
    rsa) _ossl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out "$certs/$1.key" ;;
    *)   _ossl genpkey -algorithm EC -pkeyopt ec_paramgen_curve:P-256 -out "$certs/$1.key" ;;
  esac
}

_ca() { # name subject
  _key "$1" ec
  _ossl req -x509 -new -key "$certs/$1.key" -subj "$2" -days 30 \
    -addext "basicConstraints=critical,CA:TRUE" \
    -addext "keyUsage=critical,keyCertSign,cRLSign" \
    -out "$certs/$1.pem"
}

_cert() { # name keytype subject san ca usage [x509 validity options...]
  name=$1; kt=$2; subj=$3; san=$4; ca=$5; usage=$6
  shift 6
  _key "$name" "$kt"
  _ossl req -new -key "$certs/$name.key" -subj "$subj" -out "$certs/$name.csr"
  printf 'basicConstraints=CA:FALSE\nsubjectAltName=%s\nextendedKeyUsage=%s\n' "$san" "$usage" \
    > "$certs/$name.ext"
  _ossl x509 -req -in "$certs/$name.csr" -CA "$certs/$ca.pem" -CAkey "$certs/$ca.key" \
    -CAcreateserial -extfile "$certs/$name.ext" -out "$certs/$name.pem" "$@"
  rm -f "$certs/$name.csr" "$certs/$name.ext"
}

_ca ca "/CN=Idris TLS test CA"
_ca ca2 "/CN=Another test CA"
_cert server ec "/CN=localhost/O=Idris tests" "DNS:localhost,IP:127.0.0.1" ca serverAuth -days 30
_cert rsa rsa "/CN=localhost/O=Idris tests RSA" "DNS:localhost,IP:127.0.0.1" ca serverAuth -days 30
_cert expired ec "/CN=localhost/O=Expired" "DNS:localhost,IP:127.0.0.1" ca serverAuth \
  -not_before 20200101000000Z -not_after 20200201000000Z
_cert other ec "/CN=other.example" "DNS:other.example,DNS:*.other.example" ca serverAuth -days 30
_cert client ec "/CN=test client" "email:client@example.com" ca clientAuth -days 30
_cert rogue ec "/CN=localhost/O=Rogue" "DNS:localhost,IP:127.0.0.1" ca2 serverAuth -days 30
cat "$certs/server.pem" "$certs/ca.pem" > "$certs/chain.pem"

for f in ca server rsa expired other client rogue; do
  if [ ! -s "$certs/$f.pem" ] || [ ! -s "$certs/$f.key" ]; then
    echo "gencerts: could not make $f.pem"
  fi
done
