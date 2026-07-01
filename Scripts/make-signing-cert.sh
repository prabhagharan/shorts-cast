#!/usr/bin/env bash
# Create a stable, self-signed CODE-SIGNING identity in the login keychain.
#
# Why: macOS ties permission (TCC) grants — Screen Recording, Accessibility,
# Input Monitoring — to an app's code-signing identity. make-app.sh otherwise
# signs ad-hoc, whose identity (the binary's cdhash) changes every build, so
# macOS forgets the grants and re-prompts. Signing every build with ONE stable
# identity keeps the grants across rebuilds.
#
# One-time setup. Safe to re-run — it no-ops if the identity already exists.
set -euo pipefail

NAME="${1:-ShortsCast Dev}"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "Code-signing identity '$NAME' already exists — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Use the system LibreSSL, not a Homebrew/MacPorts OpenSSL 3 that may be first on
# PATH: OpenSSL 3's `pkcs12 -export` writes a MAC that macOS `security import`
# can't verify ("MAC verification failed"). LibreSSL emits a compatible p12.
OSSL=/usr/bin/openssl

# openssl config (works with macOS's LibreSSL, which lacks `req -addext`).
cat > "$TMP/cs.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
basicConstraints = critical,CA:FALSE
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
EOF

"$OSSL" req -x509 -newkey rsa:2048 -nodes -days 3650 \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cs.cnf"
# Use a (throwaway) non-empty password: `security import` fails MAC verification
# on an empty-password p12. The p12 is deleted immediately, so the value is moot.
P12PW="shortscast-temp"
"$OSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/id.p12" -passout "pass:$P12PW"

# Import the key+cert and pre-authorize codesign to use the private key.
security import "$TMP/id.p12" -k "$KEYCHAIN" -P "$P12PW" -T /usr/bin/codesign

if security find-identity -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo
  echo "✅ Created code-signing identity '$NAME'."
  echo "Next: ./Scripts/make-app.sh  (it will now sign with '$NAME')."
  echo "The first build may prompt to use the key — click 'Always Allow'."
  echo "Grant the app its permissions once; later rebuilds won't re-prompt."
else
  echo "warning: identity '$NAME' was not found after import." >&2
  echo "Create it via Keychain Access → Certificate Assistant → Create a Certificate" >&2
  echo "(Self-Signed Root, Certificate Type: Code Signing), name it '$NAME'." >&2
  exit 1
fi
