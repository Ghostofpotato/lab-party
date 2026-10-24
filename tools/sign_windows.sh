#!/usr/bin/env bash
# Authenticode-sign the Windows build in place, then verify it.
# Certificate in a file:   SIGN_PFX=/path/cert.pfx SIGN_PASS=... tools/sign_windows.sh [exe]
# Certificate in a token/cloud (Certum SimplySign, YubiKey, ...):
#   SIGN_PKCS11_MODULE=/path/lib.so SIGN_CERT=/path/cert.pem SIGN_KEY='pkcs11:...' SIGN_PASS=<pin> tools/sign_windows.sh [exe]
set -euo pipefail
EXE="${1:-$HOME/lab-party-build/windows/LabParty.exe}"
TS="${SIGN_TS:-http://time.certum.pl}"
OUT="$EXE.signed"
common=(-n "Lab Party" -i "https://github.com/Ghostofpotato/lab-party" -h sha256 -ts "$TS" -in "$EXE" -out "$OUT")
if [ -n "${SIGN_PFX:-}" ]; then
  osslsigncode sign -pkcs12 "$SIGN_PFX" -pass "${SIGN_PASS:-}" "${common[@]}"
elif [ -n "${SIGN_PKCS11_MODULE:-}" ]; then
  osslsigncode sign -pkcs11module "$SIGN_PKCS11_MODULE" -certs "$SIGN_CERT" -key "$SIGN_KEY" -pass "${SIGN_PASS:-}" "${common[@]}"
else
  echo "set SIGN_PFX or SIGN_PKCS11_MODULE"; exit 1
fi
mv "$OUT" "$EXE"
osslsigncode verify -in "$EXE" | grep -E "Signature verification|Subject:|Timestamp" || true
