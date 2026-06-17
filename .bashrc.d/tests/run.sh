#!/usr/bin/env bash
# Test runner for the dotfiles snippets.
#
# Runs every *.test.sh in this directory and reports a summary. Exits non-zero
# if any test fails (SKIPs do not fail the run).
#
#   bash ~/.bashrc.d/tests/run.sh

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

rc=0
ran=0
for t in "$HERE"/*.test.sh; do
    [ -e "$t" ] || continue
    ran=$((ran + 1))
    echo "== $(basename "$t") =="
    if bash "$t"; then :; else rc=1; fi
done

if [ "$ran" -eq 0 ]; then
    echo "no tests found in $HERE"
fi
exit "$rc"
