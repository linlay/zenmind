#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENMIND_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONOREPO_ROOT="$(cd "${ZENMIND_REPO_ROOT}/.." && pwd)"
ZENMIND_DIR="${MONOREPO_ROOT}/.zenmind"
VERSION_FILE="${ZENMIND_REPO_ROOT}/VERSION"
DIST_DIR="${ZENMIND_DIR}/dist"
ARCHIVE_ROOT_NAME="zenmind-data"
SOURCE_OWNER_DIR="${ZENMIND_DIR}/owner.example"
SOURCE_REGISTRIES_DIR="${ZENMIND_DIR}/registries.example"
SCRIPT_NAME="${ZENMIND_PACKAGE_SCRIPT_NAME:-$(basename "${BASH_SOURCE[0]}")}"

usage() {
  cat <<USAGE
Usage: ./${SCRIPT_NAME}

Package publishable .zenmind data into a versioned dist tar.gz archive.

Version source:
  1. VERSION environment variable
  2. ${VERSION_FILE}

Rules:
  - agents: include normal directories and *.example, exclude *.demo
  - chats: include *.example.jsonl and *.example directories only
  - owner.example -> owner in bundle
  - registries.example -> registries in bundle
  - root: include top-level entries whose basename contains .example
  - schedules: include normal and *.example.yml|*.example.yaml, exclude *.demo.yml|*.demo.yaml
  - skills-market: include normal directories and *.example, exclude *.demo
  - teams: include normal and *.example.yml|*.example.yaml, exclude *.demo.yml|*.demo.yaml
  - tools: excluded
USAGE
}

err() {
  printf '[package] ERROR: %s\n' "$*" >&2
}

log() {
  printf '[package] %s\n' "$*"
}

trim() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s\n' "$value"
}

require_command() {
  local cmd="$1"
  command -v "$cmd" >/dev/null 2>&1 || {
    err "required command not found: $cmd"
    exit 1
  }
}

resolve_version() {
  if [[ "${VERSION+x}" == x ]]; then
    VERSION="$(trim "$VERSION")"
  else
    [[ -f "$VERSION_FILE" ]] || {
      err "missing VERSION file: $VERSION_FILE"
      exit 1
    }
    VERSION="$(tr -d '[:space:]' < "$VERSION_FILE")"
  fi

  [[ -n "$VERSION" ]] || {
    err "VERSION must not be empty"
    exit 1
  }
  [[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || {
    err "VERSION must match vX.Y.Z (got: $VERSION)"
    exit 1
  }
}

parse_args() {
  if [[ $# -eq 0 ]]; then
    return 0
  fi

  if [[ $# -eq 1 && ( "$1" == "-h" || "$1" == "--help" ) ]]; then
    usage
    exit 0
  fi

  err "this script does not accept custom packaging flags"
  usage
  exit 2
}

ensure_layout() {
  [[ -d "$ZENMIND_DIR/agents" ]] || {
    err "agents directory not found: $ZENMIND_DIR/agents"
    exit 1
  }
  [[ -d "$SOURCE_OWNER_DIR" ]] || {
    err "owner example directory not found: $SOURCE_OWNER_DIR"
    exit 1
  }
  for registry_dir in models providers mcp-servers viewport-servers; do
    [[ -d "$SOURCE_REGISTRIES_DIR/$registry_dir" ]] || {
      err "registries example directory not found: $SOURCE_REGISTRIES_DIR/$registry_dir"
      exit 1
    }
  done
}

is_example_dir_name() {
  [[ "$1" == *.example ]]
}

is_demo_dir_name() {
  [[ "$1" == *.demo ]]
}

is_normal_dir_name() {
  ! is_example_dir_name "$1" && ! is_demo_dir_name "$1"
}

is_example_jsonl_name() {
  [[ "$1" == *.example.jsonl ]]
}

is_example_yaml_name() {
  [[ "$1" == *.example.yml || "$1" == *.example.yaml ]]
}

is_demo_yaml_name() {
  [[ "$1" == *.demo.yml || "$1" == *.demo.yaml ]]
}

is_yaml_name() {
  [[ "$1" == *.yml || "$1" == *.yaml ]]
}

is_normal_yaml_name() {
  is_yaml_name "$1" && ! is_example_yaml_name "$1" && ! is_demo_yaml_name "$1"
}

is_root_example_name() {
  [[ "$1" == *".example"* ]]
}

copy_directory() {
  local src="$1"
  local dest_parent="$2"
  mkdir -p "$dest_parent"
  cp -R "$src" "$dest_parent/"
}

copy_file() {
  local src="$1"
  local dest_dir="$2"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/"
}

copy_directory_contents() {
  local src="$1"
  local dest="$2"
  mkdir -p "$dest"
  if [[ ! -d "$src" ]]; then
    return 0
  fi
  cp -R "$src"/. "$dest"/
}

copy_selected_agent_dirs() {
  local src_dir="$ZENMIND_DIR/agents"
  local dest_dir="$1"
  local entry=""
  local name=""
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    if is_normal_dir_name "$name" || is_example_dir_name "$name"; then
      copy_directory "$entry" "$dest_dir"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

copy_selected_chats() {
  local src_dir="$ZENMIND_DIR/chats"
  local dest_dir="$1"
  local entry=""
  local name=""
  [[ -d "$src_dir" ]] || return 0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    if [[ -d "$entry" ]]; then
      if is_example_dir_name "$name"; then
        copy_directory "$entry" "$dest_dir"
      fi
      continue
    fi
    if [[ -f "$entry" ]] && is_example_jsonl_name "$name"; then
      copy_file "$entry" "$dest_dir"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 | sort)
}

copy_selected_root_entries() {
  local src_dir="$ZENMIND_DIR/root"
  local dest_dir="$1"
  local entry=""
  local name=""
  [[ -d "$src_dir" ]] || return 0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    is_root_example_name "$name" || continue
    if [[ -d "$entry" ]]; then
      copy_directory "$entry" "$dest_dir"
    else
      copy_file "$entry" "$dest_dir"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 | sort)
}

copy_selected_yaml_files() {
  local src_dir="$1"
  local dest_dir="$2"
  local entry=""
  local name=""
  [[ -d "$src_dir" ]] || return 0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    if is_normal_yaml_name "$name" || is_example_yaml_name "$name"; then
      copy_file "$entry" "$dest_dir"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
}

copy_selected_skills_market_dirs() {
  local src_dir="$ZENMIND_DIR/skills-market"
  local dest_dir="$1"
  local entry=""
  local name=""
  [[ -d "$src_dir" ]] || return 0
  while IFS= read -r entry || [[ -n "$entry" ]]; do
    [[ -n "$entry" ]] || continue
    name="$(basename "$entry")"
    if is_normal_dir_name "$name" || is_example_dir_name "$name"; then
      copy_directory "$entry" "$dest_dir"
    fi
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d | sort)
}

build_archive() {
  local archive_name archive_dir archive_path staging_dir package_root
  archive_name="${ARCHIVE_ROOT_NAME}-${VERSION}.tar.gz"
  archive_dir="${DIST_DIR}/${VERSION}"
  archive_path="${archive_dir}/${archive_name}"
  mkdir -p "$archive_dir"

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/zenmind-package-data.XXXXXX")"
  package_root="${staging_dir}/${ARCHIVE_ROOT_NAME}"
  trap "rm -rf '${staging_dir}'" EXIT

  mkdir -p \
    "$package_root/agents" \
    "$package_root/chats" \
    "$package_root/owner" \
    "$package_root/registries" \
    "$package_root/root" \
    "$package_root/schedules" \
    "$package_root/skills-market" \
    "$package_root/teams"

  copy_selected_agent_dirs "$package_root/agents"
  copy_selected_chats "$package_root/chats"
  copy_directory_contents "$SOURCE_OWNER_DIR" "$package_root/owner"
  copy_directory_contents "$SOURCE_REGISTRIES_DIR" "$package_root/registries"
  copy_selected_root_entries "$package_root/root"
  copy_selected_yaml_files "$ZENMIND_DIR/schedules" "$package_root/schedules"
  copy_selected_skills_market_dirs "$package_root/skills-market"
  copy_selected_yaml_files "$ZENMIND_DIR/teams" "$package_root/teams"

  tar --exclude='.DS_Store' -C "$staging_dir" -czf "$archive_path" "$ARCHIVE_ROOT_NAME"

  log "archive created: $archive_path"
  log "version: $VERSION"
}

main() {
  require_command cp
  require_command find
  require_command mkdir
  require_command tar

  resolve_version
  parse_args "$@"
  ensure_layout
  build_archive
}

main "$@"
