#!/usr/bin/env bash
# check-magic-strings.sh — reflutter-internal l10n tripwire (runs AGAINST a consuming app).
#
# Fails if any UI-widget string literal in an l10n-enforced dir is not allowlisted.
# This is the canonical, shared implementation: the LOGIC (tripwire patterns,
# rg/grep fallback, interpolation exemption, `// l10n-ok` escape) lives here in the
# plugin; the per-app CONFIG (which dirs are enforced, the ARB path for the fix
# hint) is read from the consuming app's `reflutter.json`. So apps stop forking
# the 80-line script — they declare their enforcement state in one small config.
#
# TRIPWIRE, not a complete gate. It catches the common offenders:
#   - `Text('...')` / `SelectableText('...')`
#   - `Tooltip(message: '...')`
#   - single-quoted literals in common user-facing named params (tooltip:,
#     hintText:, labelText:, helperText:, errorText:, confirmLabel:, cancelLabel:,
#     submitLabel:, placeholder:)
# Deliberately blind to: double-quoted literals, string interpolation, `title:`
# (too noisy), indirectly-built SnackBar/dialog content, `throw 'msg'` — those stay
# review-covered against the documented l10n convention.
#
# CONFIG — the consuming app's `reflutter.json` (repo root), optional:
#   {
#     "magicStrings": {
#       "enforcedDirs": ["lib"],                       # default: ["lib"]
#       "arbPath": "lib/shared/l10n/arb/app_en.arb"    # default: this
#     }
#   }
# No config / no jq → defaults (enforce "lib"). Opt-in rollout: list only the
# migrated dirs until the whole tree is localized, then collapse to ["lib"].
#
# Escape hatch: append `// l10n-ok` to a line intentionally not localized.
#
# USAGE  (run from the consuming app's repo root)
#   bash <plugin>/scripts/check-magic-strings.sh
set -uo pipefail

# Anchor to the consuming app's repo (this script lives in the plugin).
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO_ROOT"

CONFIG="reflutter.json"

# --- resolve config: env vars > reflutter.json > defaults ---------------------
# Precedence lets the composite GitHub Action (and any caller) pass inputs via
# env without a reflutter.json, while local runs read the repo's reflutter.json.
#   MAGIC_STRINGS_DIRS  — space-separated enforced dirs (e.g. "lib lib/foo")
#   MAGIC_STRINGS_ARB   — ARB path for the fix hint
DEFAULT_ARB="lib/shared/l10n/arb/app_en.arb"
ENFORCED_DIRS=()
ARB_PATH="$DEFAULT_ARB"

if [ -n "${MAGIC_STRINGS_DIRS:-}" ]; then
  # shellcheck disable=SC2206
  ENFORCED_DIRS=(${MAGIC_STRINGS_DIRS})
elif [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1; then
  while IFS= read -r d; do [ -n "$d" ] && ENFORCED_DIRS+=("$d"); done < <(jq -r '.magicStrings.enforcedDirs[]? // empty' "$CONFIG" 2>/dev/null)
fi

if [ -n "${MAGIC_STRINGS_ARB:-}" ]; then
  ARB_PATH="$MAGIC_STRINGS_ARB"
elif [ -f "$CONFIG" ] && command -v jq >/dev/null 2>&1; then
  ARB_PATH="$(jq -r '.magicStrings.arbPath // empty' "$CONFIG" 2>/dev/null)"
  { [ -z "$ARB_PATH" ] || [ "$ARB_PATH" = "null" ]; } && ARB_PATH="$DEFAULT_ARB"
fi

# Default when nothing set.
[ "${#ENFORCED_DIRS[@]}" -gt 0 ] || ENFORCED_DIRS=("lib")

# --- tripwire patterns (identical to the canonical poolmate logic) ------------
NAMED_PARAMS="tooltip|hintText|labelText|helperText|errorText|confirmLabel|cancelLabel|submitLabel|placeholder"
PATTERN="(Text|SelectableText)\\('|Tooltip\\([^)]*message:[[:space:]]*'|(${NAMED_PARAMS}):[[:space:]]*'"

# Drop allowlisted lines + pure interpolations carrying no literal copy.
filter() {
  grep -v 'l10n-ok' \
    | grep -vE "(Text|SelectableText)\\('\\\$" \
    | grep -vE "(${NAMED_PARAMS}):[[:space:]]*'\\\$"
}

# Search one dir, excluding generated + test files; rg if present else grep.
search_dir() {
  local dir="$1"
  if command -v rg >/dev/null 2>&1; then
    rg -n --no-heading "$PATTERN" "$dir" \
      -g '!**/gen/**' -g '!**/*.g.dart' -g '!**/*_test.dart' 2>/dev/null || true
  else
    grep -rnE "$PATTERN" "$dir" \
      --include='*.dart' --exclude='*_test.dart' --exclude='*.g.dart' 2>/dev/null \
      | grep -v '/gen/' || true
  fi
}

fail=0
for dir in "${ENFORCED_DIRS[@]}"; do
  [ -d "$dir" ] || continue
  hits=$(search_dir "$dir" | filter || true)
  if [ -n "$hits" ]; then
    echo "❌ Hardcoded UI string(s) in l10n-enforced dir '$dir':"
    echo "$hits"
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  echo ""
  echo "Fix: move the string to $ARB_PATH (+ your locale ARBs) and use"
  echo "context.l10n.<key>. If intentionally non-localized, append '// l10n-ok'."
  exit 1
fi

echo "✅ No un-allowlisted hardcoded UI strings in enforced dirs (${ENFORCED_DIRS[*]})."
