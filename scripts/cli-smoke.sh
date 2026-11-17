#!/usr/bin/env bash
# CLI smoke tests for the built `xmlfmt` binary.
#
# `moon test` only covers the library: argument handling, stdout/stderr split
# and exit codes live in cmd/xmlfmt/main.mbt and regressed before (--help wrote
# to stderr, so `xmlfmt --help` looked like it printed nothing when stdout was
# captured). Run this after `moon build --target native --release`.
#
#   ./scripts/cli-smoke.sh [path/to/xmlfmt]
set -uo pipefail

BIN=${1:-_build/native/release/build/cmd/xmlfmt/xmlfmt.exe}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

failures=0
pass() { printf 'ok   %s\n' "$1"; }
fail() {
  printf 'FAIL %s\n' "$1" >&2
  failures=$((failures + 1))
}

# run <name> <expected-exit> -- <args...>; captures stdout/stderr per case
run() {
  local name=$1 expected=$2
  shift 3
  "$BIN" "$@" >"$TMP/out" 2>"$TMP/err"
  local actual=$?
  if [ "$actual" -eq "$expected" ]; then
    pass "$name (exit $actual)"
  else
    fail "$name: expected exit $expected, got $actual"$'\n'"$(cat "$TMP/err")"
  fi
}

assert_stdout_has() {
  if grep -qF -- "$1" "$TMP/out"; then
    pass "$2"
  else
    fail "$2: stdout does not contain '$1'"
  fi
}

assert_stdout_empty() {
  if [ -s "$TMP/out" ]; then
    fail "$1: expected empty stdout, got: $(head -c 200 "$TMP/out")"
  else
    pass "$1"
  fi
}

assert_stdout_equals() {
  if [ "$(cat "$TMP/out")" = "$1" ]; then
    pass "$2"
  else
    fail "$2: unexpected stdout: $(cat "$TMP/out")"
  fi
}

if [ ! -x "$BIN" ]; then
  echo "cli-smoke: $BIN is missing; run: moon build --target native --release" >&2
  exit 1
fi

expected_version=$(sed -n 's/^version = "\(.*\)"$/\1/p' "$ROOT/moon.mod")

# The npm package must publish the same version the binary reports, or users
# upgrade the wrapper and still run a binary from another release.
npm_version=$(sed -n 's/^  "version": "\(.*\)",$/\1/p' "$ROOT/npmjs/package.json")
if [ "$npm_version" = "$expected_version" ]; then
  pass "npmjs/package.json matches moon.mod ($expected_version)"
else
  fail "npmjs/package.json is $npm_version but moon.mod is $expected_version"
fi

# --help must go to stdout and succeed: it is normal program output.
run "--help" 0 -- --help
assert_stdout_has "Usage: xmlfmt" "--help mentions usage"
assert_stdout_has "--version" "--help documents --version"
# The help footer names the build, so a stale or shadowed binary is obvious.
run "--help names the version" 0 -- --help
assert_stdout_has "xmlfmt $expected_version" "--help names the running version"
run "-h" 0 -- -h
assert_stdout_has "Usage: xmlfmt" "-h mentions usage"

# Version output, including the short flag.
for flag in -v -V --version; do
  run "$flag" 0 -- "$flag"
  assert_stdout_equals "xmlfmt $expected_version" "$flag prints moon.mod version"
done

# Bad command lines exit 2 with an empty stdout, so they cannot be mistaken
# for formatted documents. They must not fall through and read stdin.
run "unknown option" 2 -- --nope
assert_stdout_empty "unknown option writes nothing to stdout"
run "missing option value" 2 -- --indent
assert_stdout_empty "missing value writes nothing to stdout"

# Unreadable input exits 1 instead of succeeding with an empty document.
run "missing input file" 1 -- "$TMP/does-not-exist.xml"
assert_stdout_empty "missing input file writes nothing to stdout"

# Formatting still works, from stdin and from a file.
printf '<root><a x="1">t</a><b/></root>' | "$BIN" - >"$TMP/out" 2>"$TMP/err"
if [ "$(cat "$TMP/out")" = $'<root>\n  <a x="1">t</a>\n  <b></b>\n</root>' ]; then
  pass "pretty-print from stdin"
else
  fail "pretty-print from stdin: $(cat "$TMP/out")"
fi

printf '<root><a/></root>' >"$TMP/in.xml"
run "format file" 0 -- "$TMP/in.xml"
assert_stdout_equals $'<root>\n  <a></a>\n</root>' "format file output"

run "compress" 0 -- -c "$TMP/in.xml"
assert_stdout_equals "<root><a/></root>" "compress output (minified, empty elements self-close)"

run "selfclose-space" 0 -- -s -S "$TMP/in.xml"
assert_stdout_equals $'<root>\n  <a />\n</root>' "selfclose-space output"

# Start tags spread over several lines keep their attributes: only ' '
# separated attributes before, so newlines leaked into attribute names.
printf '<root\n  a="1"\n  b="2"\n>\n  <c/>\n</root>' >"$TMP/multiline.xml"
run "multi-line start tag" 0 -- "$TMP/multiline.xml"
assert_stdout_equals $'<root a="1" b="2">\n  <c></c>\n</root>' "multi-line start tag attributes"

# UTF-16 documents (Windows tools, some editors) must not come out as mojibake.
python3 - "$TMP/utf16.xml" <<'PYEOF' 2>/dev/null || printf '' >"$TMP/utf16.xml"
import sys
open(sys.argv[1], "wb").write("<r><a>x</a></r>".encode("utf-16"))
PYEOF
if [ -s "$TMP/utf16.xml" ]; then
  run "UTF-16 input" 0 -- "$TMP/utf16.xml"
  assert_stdout_equals $'<r>\n  <a>x</a>\n</r>' "UTF-16 input decoded"
fi

run "overwrite" 0 -- -w "$TMP/in.xml"
if [ "$(cat "$TMP/in.xml")" = $'<root>\n  <a></a>\n</root>' ]; then
  pass "overwrite rewrites the input file"
else
  fail "overwrite rewrote file as: $(cat "$TMP/in.xml")"
fi

if [ "$failures" -ne 0 ]; then
  echo "cli-smoke: $failures check(s) failed" >&2
  exit 1
fi
echo "cli-smoke: all checks passed"
