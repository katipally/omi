#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEASE_COMMAND="$SCRIPT_DIR/../scripts/qualification-lease-command.sh"
TMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/omi-qualification-lease-command-test.XXXXXX")"

cleanup() {
  rm -rf "$TMP_ROOT"
}
trap cleanup EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

FIXTURE_WORKTREE="$TMP_ROOT/worktree"
FIXTURE_PYTHON="$FIXTURE_WORKTREE/backend/.venv/bin/python"
mkdir -p "$(dirname "$FIXTURE_PYTHON")"
cat > "$FIXTURE_PYTHON" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ "${1:-}" == '-m' && "${2:-}" == 'dev_harness.cli' && "${3:-}" == 'qualification-lease' && "${5:-}" == '--lease-id' ]] || {
  echo "unexpected qualification lease command shape" >&2
  exit 65
}
case "${QUALIFICATION_LEASE_FIXTURE_MODE:-}" in
  acquire-failure)
    printf '%s\n' 'Safety check failed: Qualification lease owner PID is not running: 424242'
    exit 2
    ;;
  release-failure)
    printf '%s\n' 'Safety check failed: Qualification lease token does not match the active lease'
    exit 2
    ;;
  acquire-success)
    printf '%s\n' '{"log_dir":"/tmp/qualification-log","token":"test-token"}'
    ;;
  *)
    echo "unexpected fixture mode: ${QUALIFICATION_LEASE_FIXTURE_MODE:-unset}" >&2
    exit 64
    ;;
esac
SH
chmod +x "$FIXTURE_PYTHON"

if QUALIFICATION_LEASE_FIXTURE_MODE=acquire-failure "$LEASE_COMMAND" acquire "$FIXTURE_WORKTREE" qualification-test 424242 1000 3 >"$TMP_ROOT/acquire.out" 2>"$TMP_ROOT/acquire.err"; then
  fail "lease acquire unexpectedly succeeded"
fi
grep -Fq 'qualification failed: lease acquire exited 2: Safety check failed: Qualification lease owner PID is not running: 424242' "$TMP_ROOT/acquire.err" \
  || fail "lease acquire failure was not relayed to stderr"
[[ ! -s "$TMP_ROOT/acquire.out" ]] || fail "failed lease acquire wrote a JSON capability to stdout"

if QUALIFICATION_LEASE_FIXTURE_MODE=release-failure "$LEASE_COMMAND" release "$FIXTURE_WORKTREE" qualification-test test-release-token 3 1209600 >"$TMP_ROOT/release.out" 2>"$TMP_ROOT/release.err"; then
  fail "lease release unexpectedly succeeded"
fi
grep -Fq 'qualification failed: lease release exited 2: Safety check failed: Qualification lease token does not match the active lease' "$TMP_ROOT/release.err" \
  || fail "lease release failure was not relayed to stderr"
if grep -Fq 'test-release-token' "$TMP_ROOT/release.err"; then
  fail "lease release diagnostic leaked its capability token"
fi

QUALIFICATION_LEASE_FIXTURE_MODE=acquire-success "$LEASE_COMMAND" acquire "$FIXTURE_WORKTREE" qualification-test $$ 1000 3 >"$TMP_ROOT/success.out"
grep -Fxq '{"log_dir":"/tmp/qualification-log","token":"test-token"}' "$TMP_ROOT/success.out" \
  || fail "successful lease acquire did not preserve its JSON capability"

echo "qualification lease command behavioral regression tests passed"
