#!/usr/bin/env bash
# Test the secret-scan pre-commit scanner: it must block a staged secret and
# allow clean content. Runs in a throwaway git repo so it never touches the real
# dotfiles repo.
#
# The fake secret is ASSEMBLED AT RUNTIME so this test file itself contains no
# literal that would match the scanner (otherwise the scanner would flag this
# very file when it is committed).

set -u

SCANNER="$HOME/.config/git/hooks/secret-scan"
fail() { echo "FAIL: $*" >&2; exit 1; }

[ -x "$SCANNER" ] || { echo "SKIP: scanner not found at $SCANNER"; exit 0; }
command -v git >/dev/null 2>&1 || { echo "SKIP: git not installed"; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
cd "$T" || fail "cannot cd to temp repo"

git init -q .
git config user.email test@example.invalid
git config user.name test

# Clean content must pass.
printf 'echo hello world\n' > ok.sh
git add ok.sh
"$SCANNER" >/dev/null 2>&1 || fail "scanner wrongly blocked clean content"

# A staged fake API key must be blocked. Build "sk-" + 24 chars at runtime so
# this test file contains no literal that the scanner would match.
body="$(printf 'A%.0s' $(seq 1 24))"
printf 'export TOKEN=%s%s\n' "sk-" "$body" > leak.sh
git add leak.sh
err="$("$SCANNER" 2>&1 >/dev/null)"
"$SCANNER" >/dev/null 2>&1 && fail "scanner did NOT block a staged fake API key"
printf '%s' "$err" | grep -qiE 'unrecognized option|Usage: grep' && \
    fail "scanner emitted a grep option-parsing error: $err"
git rm -q --cached leak.sh; rm -f leak.sh

# A staged fake private-key block must also be blocked (regex starts with '-----',
# which previously broke grep option parsing). Assemble at runtime.
pk="$(printf -- '-----BEGIN %s PRIVATE KEY-----' OPENSSH)"
printf '%s\n' "$pk" > key.pem
git add key.pem
err="$("$SCANNER" 2>&1 >/dev/null)"
"$SCANNER" >/dev/null 2>&1 && fail "scanner did NOT block a fake private-key block"
printf '%s' "$err" | grep -qiE 'unrecognized option|Usage: grep' && \
    fail "scanner emitted a grep option-parsing error on the private-key pattern: $err"

echo "PASS: secret-scan blocks API keys and private keys, allows clean content, no grep errors"
