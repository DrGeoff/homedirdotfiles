#!/usr/bin/env bash
# Integration test for ~/.bashrc.d/secret
#
# Verifies the keepassxc-cli backend end-to-end through the real secret() code
# path, using a DISPOSABLE database with a throwaway master password — no real
# vault and no real secrets are involved, so this is safe to keep in a public
# repo.
#
# Run directly:        bash ~/.bashrc.d/tests/secret.test.sh
# Or via the runner:   bash ~/.bashrc.d/tests/run.sh
#
# Exits 0 (SKIP) if keepassxc-cli is not installed.

set -u

HERE="$(CDPATH= cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SECRET_SNIPPET="$HERE/../secret"

fail() { echo "FAIL: $*" >&2; exit 1; }

command -v keepassxc-cli >/dev/null 2>&1 || { echo "SKIP: keepassxc-cli not installed"; exit 0; }
[ -r "$SECRET_SNIPPET" ] || fail "secret snippet not found at $SECRET_SNIPPET"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

DB="$T/throwaway.kdbx"
PW="testpass"          # throwaway database master password
VALUE="hunter2"        # throwaway entry value

printf '%s\n%s\n' "$PW" "$PW" | keepassxc-cli db-create -q "$DB" -p >/dev/null 2>&1 \
    || fail "could not create throwaway database"
printf '%s\n%s\n' "$PW" "$VALUE" | keepassxc-cli add -q -p "$DB" _dottest >/dev/null 2>&1 \
    || fail "could not add test entry"
# Second entry, to prove one unlock serves many: it sits in a sub-group and its
# value has CSV-hostile characters, since withsecret reads entries via CSV export.
VALUE2='sword,"fish'
printf '%s\n' "$PW" | keepassxc-cli mkdir -q "$DB" _grp >/dev/null 2>&1 \
    || fail "could not add test group"
printf '%s\n%s\n' "$PW" "$VALUE2" | keepassxc-cli add -q -p "$DB" _grp/_dottest2 >/dev/null 2>&1 \
    || fail "could not add second test entry"

# Drive the real secret() path. Feed the throwaway master password on stdin, and
# isolate from the plaintext fallback by pointing SECRETS_DIR at an empty dir so
# only the keepassxc-cli backend can satisfy the lookup.
got="$(printf '%s\n' "$PW" \
        | KPXC_DB="$DB" SECRETS_DIR="$T/nosuch" \
          bash -c "source '$SECRET_SNIPPET'; secret _dottest" 2>/dev/null)"

[ "$got" = "$VALUE" ] || fail "secret() returned [$got], expected [$VALUE]"
echo "PASS: secret() retrieves an entry from a throwaway KeePassXC database via keepassxc-cli"

# withsecret must export the values into the child only, unlock once for several
# entries, and reuse the cache: the master password is supplied exactly once, so
# the second entry and the second call can only succeed via one unlock + cache.
got="$(printf '%s\n' "$PW" \
        | KPXC_DB="$DB" SECRETS_DIR="$T/nosuch" \
          bash -c "source '$SECRET_SNIPPET'; source '$HERE/../withsecret'
                   withsecret X=_dottest Y=_grp/_dottest2 -- printenv X Y
                   withsecret X=_dottest -- printenv X; printenv X Y" 2>/dev/null)"
[ "$got" = "$VALUE"$'\n'"$VALUE2"$'\n'"$VALUE" ] \
    || fail "withsecret returned [$got], expected both values, then cached value, and no leak"
echo "PASS: withsecret exports into the child only and asks for the password once per shell"

# A wrong password is re-asked once: wrong then right must succeed.
got="$(printf '%s\n' wrong "$PW" \
        | KPXC_DB="$DB" SECRETS_DIR="$T/nosuch" \
          bash -c "source '$SECRET_SNIPPET'; source '$HERE/../withsecret'
                   withsecret X=_dottest Y=_grp/_dottest2 -- printenv X Y" 2>/dev/null)"
[ "$got" = "$VALUE"$'\n'"$VALUE2" ] || fail "wrong-then-right returned [$got], expected both values"

# Wrong twice must give up: no command run, non-zero exit, no third prompt
# (the correct password is offered third and must NOT be consumed).
got="$(printf '%s\n' wrong wrong "$PW" \
        | KPXC_DB="$DB" SECRETS_DIR="$T/nosuch" \
          bash -c "source '$SECRET_SNIPPET'; source '$HERE/../withsecret'
                   withsecret X=_dottest -- printenv X || echo gave-up" 2>/dev/null)"
[ "$got" = "gave-up" ] || fail "wrong-twice returned [$got], expected gave-up"
echo "PASS: withsecret re-asks a wrong password once, then gives up"
