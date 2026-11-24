#!/usr/bin/env bash
# Runs lockward with the action's arguments, writes a job summary and, for
# verify, a SARIF file for code scanning. The exit code is reported as an
# output so SARIF is uploaded before the job fails.
set -uo pipefail

read -r -a args <<< "${LOCKWARD_ARGS:-verify --frozen}"

set +e
out="$(lockward "${args[@]}" 2>&1)"
code=$?
set -e

# The output can contain text from the repository being checked. Stop the
# runner from interpreting it as workflow commands ("::error::", "::add-mask::")
# while it is printed, using an unguessable token to resume.
token="lockward-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
echo "::stop-commands::${token}"
printf '%s\n' "$out"
echo "::${token}::"

# Fence the job summary with more backticks than any run in the output, so the
# content cannot close the code block and inject Markdown.
longest="$(printf '%s' "$out" | { grep -o '`\+' || true; } | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
fence='```'
while (( ${#fence} <= longest )); do fence="${fence}\`"; done
{
  echo "### Lockward"
  echo
  echo "$fence"
  printf '%s\n' "$out"
  echo "$fence"
} >> "${GITHUB_STEP_SUMMARY:-/dev/null}"

sarif=""
if [[ "${LOCKWARD_SARIF:-true}" == "true" && "${args[0]:-}" == "verify" ]]; then
  sarif="${RUNNER_TEMP:-/tmp}/lockward.sarif"
  extra=()
  skip=0
  for a in "${args[@]:1}"; do
    if (( skip )); then skip=0; continue; fi
    case "$a" in
      --format|-format) skip=1 ;;
      --format=*|-format=*) ;;
      *) extra+=("$a") ;;
    esac
  done
  lockward verify "${extra[@]}" --format sarif > "$sarif" 2>/dev/null || true
  [[ -s "$sarif" ]] || sarif=""
fi

{
  echo "exit-code=$code"
  echo "sarif-file=$sarif"
} >> "${GITHUB_OUTPUT:-/dev/null}"
