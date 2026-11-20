#!/usr/bin/env bash
# Tests the notarize function of scripts/release.sh against a stand-in for
# `xcrun notarytool`: the function is cut out of the script between its
# markers, so what runs here is the code the release runs.
#   scripts/test-release-notarize.sh
# Nothing is submitted anywhere, and nothing sleeps.
set -euo pipefail
source "$(dirname "$0")/env.sh"
cd "$ROOT"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
sed -n '/^# >>> notarize$/,/^# <<< notarize$/p' scripts/release.sh >"$work/notarize.sh"
grep -q '^notarize() {$' "$work/notarize.sh" || { echo "test-release-notarize: FAIL: the notarize function was not found in scripts/release.sh" >&2; exit 1; }

# The cut-out function reads these and sets notary_attempts.
# shellcheck disable=SC2034
log="$work/log"
# shellcheck disable=SC2034
notary_profile=test-profile
# shellcheck source=/dev/null
source "$work/notarize.sh"

# The stand-ins. `answers` holds one word per expected call. The function
# runs xcrun inside $(…), a subshell, so the call count lives in a file.
sleeps=0
answers=()
xcrun() {
  local calls
  calls="$(cat "$work/calls")"
  local answer="${answers[$calls]:-abort}"
  echo $((calls + 1)) >"$work/calls"
  case "$answer" in
  accepted) printf 'Current status: In Progress...Current status: Accepted....Processing complete\n  id: 0\n  status: Accepted\n' ;;
  invalid) printf 'Current status: In Progress...Current status: Invalid....Processing complete\n  id: 0\n  status: Invalid\n' ;;
  # What a dropped upload prints: an error, a non-zero exit, no verdict.
  abort) printf 'Submission ID received\n  id: 0\nError: abortedUpload(resumeRequest: …connectTimeout)\n'; return 1 ;;
  # The wait ran out: exit 0 without a verdict.
  silent) printf 'Current status: In Progress...\n' ;;
  esac
}
sleep() { sleeps=$((sleeps + 1)); }

fail() { echo "test-release-notarize: FAIL: $*" >&2; exit 1; }
# expect <name> <status> <calls> <sleeps> <answers…>
expect() {
  local name="$1" want_status="$2" want_calls="$3" want_sleeps="$4" status=0
  shift 4
  answers=("$@")
  echo 0 >"$work/calls"
  sleeps=0
  notarize "$work/file.dmg" 2>"$work/err" || status=$?
  local calls
  calls="$(cat "$work/calls")"
  [ "$status" = "$want_status" ] || fail "$name: exit $status, want $want_status ($(cat "$work/err"))"
  [ "$calls" = "$want_calls" ] || fail "$name: $calls submission(s), want $want_calls"
  [ "$sleeps" = "$want_sleeps" ] || fail "$name: $sleeps pause(s), want $want_sleeps"
}

# shellcheck disable=SC2154
[ "$notary_attempts" = 3 ] || fail "the tests below assume 3 attempts, the script has $notary_attempts"
expect "accepted at once" 0 1 0 accepted
expect "one dropped upload, then accepted" 0 2 1 abort accepted
expect "two dropped uploads, then accepted" 0 3 2 abort abort accepted
expect "three dropped uploads: gives up at the limit" 1 3 2 abort abort abort accepted
grep -q "no submission completed in 3 attempts" "$work/err" || fail "giving up does not say so: $(cat "$work/err")"
expect "a verdict is not retried" 1 1 0 invalid accepted
grep -q 'answered "Invalid"' "$work/err" || fail "a refusal does not name the verdict: $(cat "$work/err")"
expect "a wait that ran out is tried again" 0 2 1 silent accepted
expect "a refusal after a dropped upload ends it" 1 2 1 abort invalid accepted
# Every submission's output is kept for whoever has to look.
[ "$(grep -c 'abortedUpload' "$log")" -ge 6 ] || fail "the submissions' output is not in the log"

echo "test-release-notarize: 7 scenarios ok"
