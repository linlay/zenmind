#!/usr/bin/env bash
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENMIND_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
MONOREPO_ROOT="$(cd "${ZENMIND_REPO_ROOT}/.." && pwd)"
ZENMIND_DIR="${MONOREPO_ROOT}/.zenmind"
VERSION_FILE="${ZENMIND_REPO_ROOT}/VERSION"
DIST_DIR="${ZENMIND_DIR}/dist"
ARCHIVE_ROOT_NAME="zenmind-agents"
SCRIPT_NAME="${ZENMIND_PACKAGE_SCRIPT_NAME:-$(basename "${BASH_SOURCE[0]}")}"

INCLUDE_DEMO=0
INCLUDE_API_KEYS=0
AGENTS_CSV=""

SELECTED_AGENTS=()
COLLECTED_MODELS=()
COLLECTED_PROVIDERS=()
COLLECTED_MCP_SERVERS=()
COLLECTED_VIEWPORT_SERVERS=()
COLLECTED_TOOLS=()
PACKAGED_TEAM_IDS=()
PACKAGED_SCHEDULE_IDS=()

usage() {
  cat <<USAGE
Usage: ./${SCRIPT_NAME} [options]

Package publishable agents from the current .zenmind workspace into a versioned dist tar.gz archive.

Version source:
  1. VERSION environment variable
  2. ${VERSION_FILE}

Options:
  --include-demo        include agents whose directory name starts with demo
  --include-api-keys    deprecated; packaged example configs are copied as-is
  --agents LIST         comma-separated agent keys to package
  -h, --help            show this help

Examples:
  ./${SCRIPT_NAME}
  ./${SCRIPT_NAME} --include-demo
  ./${SCRIPT_NAME} --include-api-keys
  ./${SCRIPT_NAME} --agents dailyOfficeAssistant,superWorkspaceAdmin
  ./${SCRIPT_NAME} --agents dailyOfficeAssistant --include-api-keys
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

append_unique() {
  local array_name="$1"
  local value="$2"
  local existing=""
  local existing_values=()
  [[ -n "$value" ]] || return 0
  eval "existing_values=(\"\${${array_name}[@]-}\")"
  for existing in "${existing_values[@]}"; do
    if [[ "$existing" == "$value" ]]; then
      return 0
    fi
  done
  eval "${array_name}+=(\"\$value\")"
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
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --include-demo)
        INCLUDE_DEMO=1
        shift
        ;;
      --include-api-keys)
        INCLUDE_API_KEYS=1
        shift
        ;;
      --agents)
        [[ $# -ge 2 ]] || {
          err "--agents requires a comma-separated value"
          usage
          exit 2
        }
        if [[ -n "$AGENTS_CSV" ]]; then
          AGENTS_CSV="${AGENTS_CSV},$2"
        else
          AGENTS_CSV="$2"
        fi
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        err "unknown argument: $1"
        usage
        exit 2
        ;;
    esac
  done
}

ensure_layout() {
  [[ -d "$ZENMIND_DIR" ]] || {
    err "workspace runtime directory not found: $ZENMIND_DIR"
    exit 1
  }
  [[ -d "$ZENMIND_DIR/agents" ]] || {
    err "agents directory not found: $ZENMIND_DIR/agents"
    exit 1
  }
  [[ -d "$ZENMIND_DIR/configs/models" ]] || {
    err "models directory not found: $ZENMIND_DIR/configs/models"
    exit 1
  }
  [[ -d "$ZENMIND_DIR/configs/providers" ]] || {
    err "providers directory not found: $ZENMIND_DIR/configs/providers"
    exit 1
  }
  [[ -d "$ZENMIND_DIR/configs/mcp-servers" ]] || {
    err "mcp-servers directory not found: $ZENMIND_DIR/configs/mcp-servers"
    exit 1
  }
  [[ -d "$ZENMIND_DIR/configs/viewport-servers" ]] || {
    err "viewport-servers directory not found: $ZENMIND_DIR/configs/viewport-servers"
    exit 1
  }
}

array_contains() {
  local sought="$1"
  shift
  local item=""
  for item in "$@"; do
    if [[ "$item" == "$sought" ]]; then
      return 0
    fi
  done
  return 1
}

resolve_yaml_file() {
  local dir="$1"
  local key="$2"
  if [[ -f "$dir/$key.yml" ]]; then
    printf '%s\n' "$dir/$key.yml"
    return 0
  fi
  if [[ -f "$dir/$key.yaml" ]]; then
    printf '%s\n' "$dir/$key.yaml"
    return 0
  fi
  return 1
}

resolve_example_yaml_file() {
  local dir="$1"
  local key="$2"
  if [[ -f "$dir/$key.example.yml" ]]; then
    printf '%s\n' "$dir/$key.example.yml"
    return 0
  fi
  if [[ -f "$dir/$key.example.yaml" ]]; then
    printf '%s\n' "$dir/$key.example.yaml"
    return 0
  fi
  return 1
}

list_example_yaml_files() {
  local dir="$1"
  find "$dir" -maxdepth 1 -type f \( -name '*.example.yml' -o -name '*.example.yaml' \) | sort
}

count_example_yaml_files() {
  local dir="$1"
  list_example_yaml_files "$dir" | wc -l | tr -d '[:space:]'
}

extract_model_keys() {
  local file="$1"
  awk '
    /^[[:space:]]*modelKey:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*modelKey:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") {
        print line
      }
    }
  ' "$file"
}

extract_tool_names() {
  local file="$1"
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*(backends|frontends|actions):[[:space:]]*$/ {
      collecting = 1
      next
    }
    collecting && /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if (line != "") {
        print line
      }
      next
    }
    collecting && /^[[:space:]]*[A-Za-z0-9_][A-Za-z0-9_-]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
    collecting && /^[^[:space:]][^:]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
  ' "$file"
}

extract_backend_names() {
  local file="$1"
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*backends:[[:space:]]*$/ {
      collecting = 1
      next
    }
    collecting && /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if (line != "") {
        print line
      }
      next
    }
    collecting && /^[[:space:]]*[A-Za-z0-9_][A-Za-z0-9_-]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
    collecting && /^[^[:space:]][^:]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
  ' "$file"
}

extract_skill_names() {
  local file="$1"
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*skills:[[:space:]]*$/ {
      collecting = 1
      next
    }
    collecting && /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if (line != "") {
        print line
      }
      next
    }
    collecting && /^[[:space:]]*[A-Za-z0-9_][A-Za-z0-9_-]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
    collecting && /^[^[:space:]][^:]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
  ' "$file"
}

extract_provider_key() {
  local file="$1"
  awk '
    /^[[:space:]]*provider:[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*provider:[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") {
        print line
        exit
      }
    }
  ' "$file"
}

extract_top_level_value() {
  local file="$1"
  local field_name="$2"
  awk -v field="$field_name" '
    $0 ~ ("^[[:space:]]*" field ":[[:space:]]*") {
      line = $0
      sub("^[[:space:]]*" field ":[[:space:]]*", "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      sub(/[[:space:]]+$/, "", line)
      if (line != "") {
        print line
      }
      exit
    }
  ' "$file"
}

extract_team_agent_keys() {
  local file="$1"
  awk '
    function trim(s) {
      sub(/^[[:space:]]+/, "", s)
      sub(/[[:space:]]+$/, "", s)
      return s
    }
    /^[[:space:]]*agentKeys:[[:space:]]*$/ {
      collecting = 1
      next
    }
    collecting && /^[[:space:]]*-[[:space:]]*/ {
      line = $0
      sub(/^[[:space:]]*-[[:space:]]*/, "", line)
      sub(/[[:space:]]+#.*$/, "", line)
      line = trim(line)
      if (line != "") {
        print line
      }
      next
    }
    collecting && /^[[:space:]]*[A-Za-z0-9_][A-Za-z0-9_-]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
    collecting && /^[^[:space:]][^:]*:[[:space:]]*.*$/ {
      collecting = 0
      next
    }
  ' "$file"
}

is_builtin_tool() {
  case "$1" in
    datetime|container_hub_bash|_bash_|confirm_dialog)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

mcp_server_for_backend() {
  case "$1" in
    mock.*)
      printf '%s\n' "mock"
      ;;
    db_*)
      printf '%s\n' "database"
      ;;
    email.*)
      printf '%s\n' "email"
      ;;
    image.*)
      printf '%s\n' "imagine"
      ;;
    bash.*)
      printf '%s\n' "bash"
      ;;
    *)
      return 1
      ;;
  esac
}

validate_agent_directory() {
  local agent_key="$1"
  local agent_dir="$ZENMIND_DIR/agents/$agent_key"
  local agent_file="$agent_dir/agent.yml"
  local skill_name=""

  [[ -d "$agent_dir" ]] || {
    err "agent directory not found: $agent_dir"
    exit 1
  }
  [[ -f "$agent_file" ]] || {
    err "agent.yml not found: $agent_file"
    exit 1
  }

  while IFS= read -r skill_name || [[ -n "$skill_name" ]]; do
    [[ -n "$skill_name" ]] || continue
    if [[ -d "$agent_dir/skills/$skill_name" ]]; then
      continue
    fi
    if [[ -d "$ZENMIND_DIR/skills-market/$skill_name" ]]; then
      continue
    fi
    if [[ "$skill_name" == "container_hub_validation" ]]; then
      continue
    fi
    err "agent '$agent_key' references missing skill: $skill_name"
    err "expected either $agent_dir/skills/$skill_name or $ZENMIND_DIR/skills-market/$skill_name"
      exit 1
  done < <(extract_skill_names "$agent_file")
}

collect_selected_agents() {
  local agent_key=""
  local entry=""

  if [[ -n "$AGENTS_CSV" ]]; then
    OLD_IFS="$IFS"
    IFS=','
    for entry in $AGENTS_CSV; do
      agent_key="$(trim "$entry")"
      [[ -n "$agent_key" ]] || continue
      append_unique SELECTED_AGENTS "$agent_key"
    done
    IFS="$OLD_IFS"
  else
    while IFS= read -r agent_key || [[ -n "$agent_key" ]]; do
      [[ -n "$agent_key" ]] || continue
      if [[ $INCLUDE_DEMO -eq 0 && "$agent_key" == demo* ]]; then
        continue
      fi
      append_unique SELECTED_AGENTS "$agent_key"
    done < <(find "$ZENMIND_DIR/agents" -mindepth 1 -maxdepth 1 -type d -exec basename {} \; | sort)
  fi

  if [[ ${#SELECTED_AGENTS[@]} -eq 0 ]]; then
    err "no agents selected for packaging"
    exit 1
  fi

  for agent_key in "${SELECTED_AGENTS[@]}"; do
    validate_agent_directory "$agent_key"
  done
}

collect_dependencies_for_agent() {
  local agent_key="$1"
  local agent_file="$ZENMIND_DIR/agents/$agent_key/agent.yml"
  local model_key=""
  local provider_key=""
  local tool_name=""
  local backend_name=""
  local mcp_server=""

  while IFS= read -r model_key || [[ -n "$model_key" ]]; do
    local model_file=""
    [[ -n "$model_key" ]] || continue
    append_unique COLLECTED_MODELS "$model_key"
    model_file="$(resolve_example_yaml_file "$ZENMIND_DIR/configs/models" "$model_key" || true)"
    [[ -n "$model_file" ]] || {
      err "model example config not found for agent '$agent_key': $model_key"
      exit 1
    }
    provider_key="$(extract_provider_key "$model_file")"
    [[ -n "$provider_key" ]] || {
      err "provider missing in model config: $model_file"
      exit 1
    }
    append_unique COLLECTED_PROVIDERS "$provider_key"
  done < <(extract_model_keys "$agent_file")

  while IFS= read -r tool_name || [[ -n "$tool_name" ]]; do
    [[ -n "$tool_name" ]] || continue
    if is_builtin_tool "$tool_name"; then
      continue
    fi
    if resolve_yaml_file "$ZENMIND_DIR/tools" "$tool_name" >/dev/null 2>&1; then
      append_unique COLLECTED_TOOLS "$tool_name"
    fi
  done < <(extract_tool_names "$agent_file")

  while IFS= read -r backend_name || [[ -n "$backend_name" ]]; do
    [[ -n "$backend_name" ]] || continue
    if is_builtin_tool "$backend_name"; then
      continue
    fi
    if resolve_yaml_file "$ZENMIND_DIR/tools" "$backend_name" >/dev/null 2>&1; then
      append_unique COLLECTED_TOOLS "$backend_name"
      continue
    fi
    mcp_server="$(mcp_server_for_backend "$backend_name" || true)"
    if [[ -n "$mcp_server" ]]; then
      append_unique COLLECTED_MCP_SERVERS "$mcp_server"
      continue
    fi
    err "agent '$agent_key' references unresolved backend tool: $backend_name"
    exit 1
  done < <(extract_backend_names "$agent_file")
}

collect_all_dependencies() {
  local agent_key=""
  local viewport_file=""
  for agent_key in "${SELECTED_AGENTS[@]}"; do
    collect_dependencies_for_agent "$agent_key"
  done

  for agent_key in "${COLLECTED_PROVIDERS[@]}"; do
    resolve_example_yaml_file "$ZENMIND_DIR/configs/providers" "$agent_key" >/dev/null 2>&1 || {
      err "provider example config not found: $agent_key"
      exit 1
    }
  done

  for agent_key in "${COLLECTED_MCP_SERVERS[@]}"; do
    resolve_example_yaml_file "$ZENMIND_DIR/configs/mcp-servers" "$agent_key" >/dev/null 2>&1 || {
      err "MCP server example config not found: $agent_key"
      exit 1
    }
    viewport_file="$(resolve_example_yaml_file "$ZENMIND_DIR/configs/viewport-servers" "$agent_key" || true)"
    if [[ -n "$viewport_file" ]]; then
      append_unique COLLECTED_VIEWPORT_SERVERS "$agent_key"
    fi
  done

  for agent_key in "${COLLECTED_TOOLS[@]}"; do
    resolve_yaml_file "$ZENMIND_DIR/tools" "$agent_key" >/dev/null 2>&1 || {
      err "local tool config not found: $agent_key"
      exit 1
    }
  done
}

copy_provider_file() {
  local src="$1"
  local dest="$2"
  cp "$src" "$dest"
}

copy_example_config_dir() {
  local src_dir="$1"
  local dest_dir="$2"
  local src=""
  mkdir -p "$dest_dir"
  while IFS= read -r src || [[ -n "$src" ]]; do
    [[ -n "$src" ]] || continue
    cp "$src" "$dest_dir/"
  done < <(list_example_yaml_files "$src_dir")
}

copy_directory() {
  local src="$1"
  local dest_parent="$2"
  mkdir -p "$dest_parent"
  cp -R "$src" "$dest_parent/"
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

render_filtered_team_file() {
  local src="$1"
  local dest="$2"
  local team_name=""
  local default_agent_key=""
  local filtered_agent_keys=()
  local team_agent_key=""

  team_name="$(extract_top_level_value "$src" "name")"
  default_agent_key="$(extract_top_level_value "$src" "defaultAgentKey")"

  while IFS= read -r team_agent_key || [[ -n "$team_agent_key" ]]; do
    [[ -n "$team_agent_key" ]] || continue
    if array_contains "$team_agent_key" "${SELECTED_AGENTS[@]}"; then
      append_unique filtered_agent_keys "$team_agent_key"
    fi
  done < <(extract_team_agent_keys "$src")

  if [[ ${#filtered_agent_keys[@]} -eq 0 ]]; then
    return 1
  fi

  if [[ -z "$default_agent_key" ]] || ! array_contains "$default_agent_key" "${filtered_agent_keys[@]}"; then
    default_agent_key="${filtered_agent_keys[0]}"
  fi

  mkdir -p "$(dirname "$dest")"
  {
    printf 'name: %s\n' "$team_name"
    printf 'defaultAgentKey: %s\n' "$default_agent_key"
    printf 'agentKeys:\n'
    for team_agent_key in "${filtered_agent_keys[@]}"; do
      printf -- '- %s\n' "$team_agent_key"
    done
  } > "$dest"
}

team_supports_agent() {
  local team_file="$1"
  local agent_key="$2"
  local team_agent_key=""
  local filtered_agent_keys=()

  [[ -f "$team_file" ]] || return 1

  while IFS= read -r team_agent_key || [[ -n "$team_agent_key" ]]; do
    [[ -n "$team_agent_key" ]] || continue
    if array_contains "$team_agent_key" "${SELECTED_AGENTS[@]}"; then
      append_unique filtered_agent_keys "$team_agent_key"
    fi
  done < <(extract_team_agent_keys "$team_file")

  if [[ ${#filtered_agent_keys[@]} -eq 0 ]]; then
    return 1
  fi

  array_contains "$agent_key" "${filtered_agent_keys[@]}"
}

copy_packaged_teams() {
  local teams_src_dir="$ZENMIND_DIR/teams"
  local teams_dest_dir="$1"
  local team_src=""
  local team_base=""
  local team_dest=""

  mkdir -p "$teams_dest_dir"
  if [[ ! -d "$teams_src_dir" ]]; then
    return 0
  fi

  while IFS= read -r team_src || [[ -n "$team_src" ]]; do
    [[ -n "$team_src" ]] || continue
    team_base="$(basename "$team_src")"
    team_dest="$teams_dest_dir/$team_base"
    if render_filtered_team_file "$team_src" "$team_dest"; then
      append_unique PACKAGED_TEAM_IDS "${team_base%.*}"
    else
      rm -f "$team_dest"
    fi
  done < <(find "$teams_src_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
}

copy_packaged_schedules() {
  local schedules_src_dir="$ZENMIND_DIR/schedules"
  local schedules_dest_dir="$1"
  local schedule_src=""
  local schedule_base=""
  local schedule_agent_key=""
  local schedule_team_id=""
  local team_file=""

  mkdir -p "$schedules_dest_dir"
  if [[ ! -d "$schedules_src_dir" ]]; then
    return 0
  fi

  while IFS= read -r schedule_src || [[ -n "$schedule_src" ]]; do
    [[ -n "$schedule_src" ]] || continue
    schedule_base="$(basename "$schedule_src")"
    schedule_agent_key="$(extract_top_level_value "$schedule_src" "agentKey")"
    if [[ -z "$schedule_agent_key" ]] || ! array_contains "$schedule_agent_key" "${SELECTED_AGENTS[@]}"; then
      continue
    fi

    schedule_team_id="$(extract_top_level_value "$schedule_src" "teamId")"
    if [[ -n "$schedule_team_id" ]]; then
      team_file="$(resolve_yaml_file "$ZENMIND_DIR/teams" "$schedule_team_id" || true)"
      if [[ -z "$team_file" ]] || ! team_supports_agent "$team_file" "$schedule_agent_key"; then
        continue
      fi
    fi

    cp "$schedule_src" "$schedules_dest_dir/$schedule_base"
    append_unique PACKAGED_SCHEDULE_IDS "${schedule_base%.*}"
  done < <(find "$schedules_src_dir" -maxdepth 1 -type f \( -name '*.yml' -o -name '*.yaml' \) | sort)
}

build_archive() {
  local archive_name archive_dir archive_path staging_dir package_root
  local models_example_count providers_example_count mcp_servers_example_count viewport_servers_example_count
  archive_name="${ARCHIVE_ROOT_NAME}-${VERSION}.tar.gz"
  archive_dir="${DIST_DIR}/${VERSION}"
  archive_path="${archive_dir}/${archive_name}"
  mkdir -p "$archive_dir"

  staging_dir="$(mktemp -d "${TMPDIR:-/tmp}/zenmind-package-agents.XXXXXX")"
  package_root="${staging_dir}/${ARCHIVE_ROOT_NAME}"

  cleanup() {
    rm -rf "$staging_dir"
  }
  trap cleanup EXIT

  mkdir -p "$package_root"

  local agent_key=""
  local src=""

  for agent_key in "${SELECTED_AGENTS[@]}"; do
    copy_directory "$ZENMIND_DIR/agents/$agent_key" "$package_root/agents"
  done

  mkdir -p "$package_root/teams"
  mkdir -p "$package_root/skills-market"
  mkdir -p "$package_root/schedules"
  mkdir -p "$package_root/configs"

  copy_example_config_dir "$ZENMIND_DIR/configs/models" "$package_root/configs/models"
  copy_example_config_dir "$ZENMIND_DIR/configs/providers" "$package_root/configs/providers"
  copy_example_config_dir "$ZENMIND_DIR/configs/mcp-servers" "$package_root/configs/mcp-servers"
  copy_example_config_dir "$ZENMIND_DIR/configs/viewport-servers" "$package_root/configs/viewport-servers"

  models_example_count="$(count_example_yaml_files "$ZENMIND_DIR/configs/models")"
  providers_example_count="$(count_example_yaml_files "$ZENMIND_DIR/configs/providers")"
  mcp_servers_example_count="$(count_example_yaml_files "$ZENMIND_DIR/configs/mcp-servers")"
  viewport_servers_example_count="$(count_example_yaml_files "$ZENMIND_DIR/configs/viewport-servers")"

  for agent_key in "${COLLECTED_TOOLS[@]}"; do
    src="$(resolve_yaml_file "$ZENMIND_DIR/tools" "$agent_key")"
    mkdir -p "$package_root/tools"
    cp "$src" "$package_root/tools/"
  done

  copy_packaged_teams "$package_root/teams"
  copy_packaged_schedules "$package_root/schedules"
  copy_directory_contents "$ZENMIND_DIR/skills-market" "$package_root/skills-market"

  tar --exclude='.DS_Store' -C "$staging_dir" -czf "$archive_path" "$ARCHIVE_ROOT_NAME"

  log "archive created: $archive_path"
  log "version: $VERSION"
  log "agents: ${SELECTED_AGENTS[*]}"
  log "config examples packaged: models=${models_example_count} providers=${providers_example_count} mcp-servers=${mcp_servers_example_count} viewport-servers=${viewport_servers_example_count}"
  if [[ ${#COLLECTED_TOOLS[@]} -gt 0 ]]; then
    log "tools: ${COLLECTED_TOOLS[*]}"
  fi
  log "teams packaged: ${#PACKAGED_TEAM_IDS[@]}"
  log "schedules packaged: ${#PACKAGED_SCHEDULE_IDS[@]}"
}

main() {
  require_command awk
  require_command cp
  require_command find
  require_command grep
  require_command mkdir
  require_command tar

  resolve_version
  parse_args "$@"
  ensure_layout
  collect_selected_agents
  collect_all_dependencies
  build_archive
}

main "$@"
