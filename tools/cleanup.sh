#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: tools/cleanup.sh [--apply]

Without --apply, lists repository-owned generated directories that would be
removed. Pass --apply only after reviewing the list. The active release
candidate directory is intentionally retained.
EOF
}

apply=false
case "${1:-}" in
  "") ;;
  --apply) apply=true ;;
  -h|--help) usage; exit 0 ;;
  *) usage >&2; exit 2 ;;
esac

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
repository_root="$(cd "$script_dir/.." && pwd -P)"

if [[ -n "${PARENTAL_CONTROL_CLEANUP_TEST_ROOT:-}" ]]; then
  candidate_root="$(cd "$PARENTAL_CONTROL_CLEANUP_TEST_ROOT" && pwd -P)"
  if [[ ! -f "$candidate_root/.parental-control-cleanup-test-root" ]]; then
    echo "Refusing test override without the cleanup test marker." >&2
    exit 3
  fi
  repository_root="$candidate_root"
elif [[ ! -f "$repository_root/AGENTS.md" || ! -f "$repository_root/CODEX_MASTER_PROMPT.md" ]]; then
  echo "Refusing cleanup outside the Parental Control System repository." >&2
  exit 3
fi

if [[ "$repository_root" == "/" ]]; then
  echo "Refusing cleanup at filesystem root." >&2
  exit 3
fi

declare -a targets=()
direct_targets=(
  ".build"
  "build"
  "dist"
  "coverage"
  "TestResults"
  ".artifacts/derived-data"
  ".artifacts/test-results"
  ".artifacts/tmp"
  ".artifacts/package-staging"
  ".artifacts/diagnostics"
  "apps/controller-macos/.artifacts"
)

for relative_path in "${direct_targets[@]}"; do
  candidate="$repository_root/$relative_path"
  if [[ -e "$candidate" || -L "$candidate" ]]; then
    targets+=("$candidate")
  fi
done

while IFS= read -r -d '' candidate; do
  targets+=("$candidate")
done < <(
  find "$repository_root" \
    -path "$repository_root/.git" -prune -o \
    -path "$repository_root/.artifacts/release-candidate" -prune -o \
    -type d \( -name node_modules -o -name bin -o -name obj -o -name publish \) \
    -print0
)

if [[ ${#targets[@]} -eq 0 ]]; then
  echo "No repository-owned generated output found."
  exit 0
fi

printf '%s\n' "Repository-owned generated output:"
for target in "${targets[@]}"; do
  printf '  %s\n' "${target#"$repository_root/"}"
done

if [[ "$apply" != true ]]; then
  echo "Dry run only. Re-run with --apply to remove the listed paths."
  exit 0
fi

for target in "${targets[@]}"; do
  if [[ "$target" != "$repository_root/"* ]]; then
    echo "Refusing path outside repository: $target" >&2
    exit 3
  fi
  rm -rf -- "$target"
done

echo "Removed ${#targets[@]} repository-owned generated path(s)."
