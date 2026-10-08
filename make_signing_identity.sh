#!/bin/zsh
# SPDX-License-Identifier: MIT
# Creates a self-signed code-signing identity in your login keychain, so every local build is
# signed by the same identity and keeps its Accessibility permission across rebuilds.
# Run once per Mac. The certificate is only trusted for signing on this Mac.
set -e
NAME="${1:-ScreenSharingTouchBar Local Signing}"
if security find-certificate -c "$NAME" >/dev/null 2>&1; then
  echo "Code-signing identity \"$NAME\" already exists."
  exit 0
fi
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
/usr/bin/openssl req -x509 -newkey rsa:2048 -sha256 -days 3650 -nodes -config "$TMP/cert.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
PASS=$(/usr/bin/openssl rand -hex 16)
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
  -out "$TMP/identity.p12" -passout "pass:$PASS"
security import "$TMP/identity.p12" -k "$HOME/Library/Keychains/login.keychain-db" -P "$PASS" -T /usr/bin/codesign >/dev/null
echo "Created code-signing identity \"$NAME\" in your login keychain (valid 10 years)."
