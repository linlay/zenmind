#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENMIND_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONOREPO_ROOT="$(cd "${ZENMIND_REPO_ROOT}/.." && pwd)"

SOURCE_ROOT="${SOURCE_ROOT:-${MONOREPO_ROOT}}"
TARGET_ROOT="${TARGET_ROOT:-${ZENMIND_REPO_ROOT}/dist}"
PROJECTS=(
  "zenmind"
  "zenmind-gateway"
  "zenmind-app-server"
  "zenmind-voice-server"
  "pan-webclient"
  "term-webclient"
  "agent-container-hub"
  "agent-platform-runner"
  "mcp-server-imagine"
  "mcp-server-mock"
)

usage() {
  cat <<'EOF'
Usage: collect-dist.sh <version>

<version> must be one of:
  vX.Y
  vX.Y.Z
EOF
}

log_info() {
  printf '[INFO] %s\n' "$*"
}

log_warn() {
  printf '[WARN] %s\n' "$*" >&2
}

log_error() {
  printf '[ERROR] %s\n' "$*" >&2
}

is_semver() {
  [[ "$1" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

extract_version_from_text() {
  local text="${1:-}"
  if [[ "$text" =~ (v[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  if [[ "$text" =~ (^|[^0-9])([0-9]+\.[0-9]+\.[0-9]+)($|[^0-9]) ]]; then
    printf 'v%s\n' "${BASH_REMATCH[2]}"
    return 0
  fi
  return 1
}

version_key() {
  local version="${1#v}"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"
  printf '%09d%09d%09d\n' "$major" "$minor" "$patch"
}

resolve_project_repo_root() {
  local project="$1"
  case "$project" in
    zenmind)
      printf '%s\n' "$ZENMIND_REPO_ROOT"
      ;;
    *)
      printf '%s\n' "$SOURCE_ROOT/$project"
      ;;
  esac
}

resolve_project_dist_root() {
  local project="$1"
  case "$project" in
    zenmind)
      printf '%s\n' "${MONOREPO_ROOT}/.zenmind/dist"
      ;;
    *)
      printf '%s\n' "$(resolve_project_repo_root "$project")/dist"
      ;;
  esac
}

version_matches_input() {
  local requested="$1"
  local candidate="$2"

  if [[ "$requested" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    [[ "$candidate" == "$requested" ]]
    return
  fi

  [[ "$requested" =~ ^v([0-9]+)\.([0-9]+)$ ]] || return 1
  [[ "$candidate" =~ ^v([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || return 1
  local requested_mm="${requested#v}"
  local candidate_mm="${candidate#v}"
  candidate_mm="${candidate_mm%.*}"
  [[ "$candidate_mm" == "$requested_mm" ]]
}

print_summary() {
  local copied_total="$1"
  local item

  printf '\nSummary\n'
  printf 'Copied: %s\n' "$copied_total"

  if ((${#copied[@]} > 0)); then
    printf 'Copied items:\n'
    for item in "${copied[@]}"; do
      printf '  - %s\n' "$item"
    done
  fi

  if ((${#skipped[@]} > 0)); then
    printf 'Skipped items:\n'
    for item in "${skipped[@]}"; do
      printf '  - %s\n' "$item"
    done
  fi
}

if (($# != 1)); then
  usage
  exit 1
fi

REQUESTED_VERSION="$1"
if [[ ! "$REQUESTED_VERSION" =~ ^v[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
  log_error "invalid version: $REQUESTED_VERSION"
  usage
  exit 1
fi

TARGET_DIR="$TARGET_ROOT/$REQUESTED_VERSION"
mkdir -p "$TARGET_DIR"

copied=()
skipped=()
copied_count=0

for project in "${PROJECTS[@]}"; do
  repo_root="$(resolve_project_repo_root "$project")"
  dist_root="$(resolve_project_dist_root "$project")"

  if [[ ! -d "$repo_root" ]]; then
    skipped+=("$project: repo not found ($repo_root)")
    continue
  fi

  if [[ ! -d "$dist_root" ]]; then
    skipped+=("$project: dist directory not found")
    continue
  fi

  tarballs=()
  while IFS= read -r file; do
    tarballs+=("$file")
  done < <(find "$dist_root" -type f -name '*.tar.gz' | sort)

  if ((${#tarballs[@]} == 0)); then
    skipped+=("$project: no .tar.gz files under dist/")
    continue
  fi

  matching_files=()
  matching_versions=()

  for file in "${tarballs[@]}"; do
    candidate_version="$(extract_version_from_text "$(basename "$file")" 2>/dev/null || true)"
    if [[ -z "$candidate_version" ]]; then
      continue
    fi
    if version_matches_input "$REQUESTED_VERSION" "$candidate_version"; then
      matching_files+=("$file")
      matching_versions+=("$candidate_version")
    fi
  done

  if ((${#matching_files[@]} == 0)); then
    skipped+=("$project: no dist tarball matched $REQUESTED_VERSION")
    continue
  fi

  selected_files=()

  if [[ "$REQUESTED_VERSION" =~ ^v[0-9]+\.[0-9]+$ ]]; then
    best_version=""
    best_key=""
    idx=0
    for candidate_version in "${matching_versions[@]}"; do
      current_key="$(version_key "$candidate_version")"
      if [[ -z "$best_key" || "$current_key" > "$best_key" ]]; then
        best_key="$current_key"
        best_version="$candidate_version"
      fi
      idx=$((idx + 1))
    done

    idx=0
    for file in "${matching_files[@]}"; do
      if [[ "${matching_versions[$idx]}" == "$best_version" ]]; then
        selected_files+=("$file")
      fi
      idx=$((idx + 1))
    done
  else
    selected_files=("${matching_files[@]}")
  fi

  if ((${#selected_files[@]} == 0)); then
    skipped+=("$project: matched version but no selectable files remained")
    continue
  fi

  for file in "${selected_files[@]}"; do
    cp -f "$file" "$TARGET_DIR/"
    copied+=("$project -> $(basename "$file")")
    copied_count=$((copied_count + 1))
    log_info "copied $(basename "$file") from $project"
  done
done

if ((copied_count > 0)); then
  node "${SCRIPT_DIR}/generate-release-manifest.mjs" \
    --dist-dir "$TARGET_DIR" \
    --version "$REQUESTED_VERSION"
  log_info "generated release-manifest.json and SHA256SUMS"
fi

print_summary "$copied_count"

if ((copied_count > 0)); then
  exit 0
fi

exit 1
