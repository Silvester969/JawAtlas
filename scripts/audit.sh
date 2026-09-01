#!/usr/bin/env bash
set -uo pipefail
cd "$(dirname "$0")/.."
status=0

echo "== comment gate =="
if grep -rn "//\|/\*" --include="*.swift" App JawAtlasCore Tests | grep -v "swift-tools-version"; then
  echo "FAIL: comments found in shipped Swift sources"
  status=1
else
  echo "OK: no comments"
fi

echo "== offline gate =="
if grep -rn "URLSession\|NWConnection\|NWListener\|CFSocket\|getaddrinfo\|Network\." --include="*.swift" App JawAtlasCore Tests; then
  echo "FAIL: networking symbols found"
  status=1
else
  echo "OK: no networking symbols"
fi

echo "== force unwrap gate =="
if grep -rnE '[a-zA-Z0-9_\)\]]![.,\) ]' --include="*.swift" App JawAtlasCore; then
  echo "WARN: review force unwraps above"
fi

exit $status
