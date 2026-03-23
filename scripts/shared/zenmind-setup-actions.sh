#!/usr/bin/env bash

readonly ZENMIND_SOURCE_REPOS=(
  "zenmind"
  "zenmind-app-server"
  "zenmind-voice-server"
  "zenmind-gateway"
  "agent-platform-runner"
  "agent-container-hub"
  "pan-webclient"
  "term-webclient"
  "mcp-server-mock"
  "mcp-server-imagine"
)

readonly ZENMIND_RELEASE_START_SERVICES=(
  "zenmind-app-server"
  "pan-webclient"
  "term-webclient"
  "mcp-server-mock"
  "mcp-server-imagine"
  "agent-container-hub"
  "agent-platform-runner"
  "zenmind-voice-server"
  "zenmind-gateway"
)

readonly ZENMIND_RELEASE_STOP_SERVICES=(
  "zenmind-gateway"
  "zenmind-voice-server"
  "agent-platform-runner"
  "agent-container-hub"
  "mcp-server-imagine"
  "mcp-server-mock"
  "term-webclient"
  "pan-webclient"
  "zenmind-app-server"
)

zenmind_setup_state_cli_path() {
  printf '%s/scripts/setup-state-cli.mjs\n' "$SCRIPT_DIR"
}

zenmind_install_state_path() {
  printf '%s/.zenmind/install-state.json\n' "$(zenmind_repo_root_path)"
}

zenmind_release_root_path() {
  printf '%s/release\n' "$(zenmind_repo_root_path)"
}

zenmind_release_version_dir() {
  printf '%s/%s\n' "$(zenmind_release_root_path)" "$1"
}

zenmind_release_artifacts_dir() {
  printf '%s/artifacts\n' "$1"
}

zenmind_release_deploy_dir() {
  printf '%s/deploy\n' "$1"
}

zenmind_release_service_dir() {
  printf '%s/%s\n' "$(zenmind_release_deploy_dir "$1")" "$2"
}

zenmind_release_runtime_dir() {
  printf '%s/.runtime\n' "$(zenmind_release_service_dir "$1" "$2")"
}

zenmind_release_shared_auth_dir() {
  printf '%s/shared/auth\n' "$(zenmind_release_deploy_dir "$1")"
}

zenmind_release_zenmind_dir() {
  printf '%s/.zenmind\n' "$(zenmind_release_deploy_dir "$1")"
}

zenmind_app_server_key_script() {
  printf '%s/zenmind-app-server/release-scripts/mac/setup-jwk-public-key.sh\n' "$(zenmind_repo_root_path)"
}

zenmind_host_os() {
  case "$(uname -s)" in
    Darwin) printf 'darwin\n' ;;
    Linux) printf 'linux\n' ;;
    *) setup_err "unsupported host OS: $(uname -s)"; return 1 ;;
  esac
}

zenmind_host_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf 'amd64\n' ;;
    arm64|aarch64) printf 'arm64\n' ;;
    *) setup_err "unsupported host arch: $(uname -m)"; return 1 ;;
  esac
}

zenmind_json_get() {
  local json_file="$1"
  local dotted_path="$2"
  node --input-type=module - "$json_file" "$dotted_path" <<'NODE'
import fs from "node:fs";

const [jsonFile, dottedPath] = process.argv.slice(2);
const data = JSON.parse(fs.readFileSync(jsonFile, "utf8"));
let value = data;
for (const segment of dottedPath.split(".")) {
  if (!segment) {
    continue;
  }
  value = value?.[segment];
}
if (value === undefined || value === null) {
  process.exit(1);
}
if (typeof value === "object") {
  process.stdout.write(JSON.stringify(value));
} else {
  process.stdout.write(String(value));
}
NODE
}

zenmind_state_read_to_file() {
  local output_file="$1"
  if node "$(zenmind_setup_state_cli_path)" state-read --workspace-root "$SCRIPT_DIR" >"$output_file"; then
    return 0
  fi
  return 1
}

zenmind_state_write_from_file() {
  local input_file="$1"
  node "$(zenmind_setup_state_cli_path)" state-write --workspace-root "$SCRIPT_DIR" <"$input_file" >/dev/null
}

zenmind_state_infer_source_to_file() {
  local output_file="$1"
  local -a cmd=("$(zenmind_setup_state_cli_path)" "state-infer-source" "--workspace-root" "$SCRIPT_DIR")
  if [[ -n "${MANIFEST_SOURCE_ARG:-}" ]]; then
    cmd+=("--manifest-source" "$MANIFEST_SOURCE_ARG")
  fi
  if [[ -n "${TARGET_VERSION:-}" ]]; then
    cmd+=("--target-tag" "$TARGET_VERSION" "--current-version" "$TARGET_VERSION")
  fi
  node "${cmd[@]}" >"$output_file"
}

zenmind_manifest_load_to_file() {
  local output_file="$1"
  local -a cmd=("$(zenmind_setup_state_cli_path)" "manifest-json" "--workspace-root" "$SCRIPT_DIR")
  if [[ -n "${MANIFEST_SOURCE_ARG:-}" ]]; then
    cmd+=("--manifest" "$MANIFEST_SOURCE_ARG")
  fi
  node "${cmd[@]}" >"$output_file"
}

zenmind_manifest_artifacts_to_file() {
  local output_file="$1"
  local host_os="$2"
  local host_arch="$3"
  local -a cmd=("$(zenmind_setup_state_cli_path)" "manifest-artifacts" "--workspace-root" "$SCRIPT_DIR" "--os" "$host_os" "--arch" "$host_arch")
  if [[ -n "${MANIFEST_SOURCE_ARG:-}" ]]; then
    cmd+=("--manifest" "$MANIFEST_SOURCE_ARG")
  fi
  node "${cmd[@]}" >"$output_file"
}

zenmind_manifest_artifacts_to_tsv() {
  local json_file="$1"
  node --input-type=module - "$json_file" <<'NODE'
import fs from "node:fs";

const artifacts = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const artifact of artifacts) {
  process.stdout.write([
    artifact.service || "",
    artifact.fileName || "",
    artifact.runtime || "",
    artifact.sha256 || "",
    artifact.source?.kind || "",
    artifact.source?.source || ""
  ].join("\t"));
  process.stdout.write("\n");
}
NODE
}

zenmind_source_refs_to_tsv() {
  local json_file="$1"
  node --input-type=module - "$json_file" <<'NODE'
import fs from "node:fs";

const refs = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
for (const [repo, ref] of Object.entries(refs)) {
  process.stdout.write(`${repo}\t${ref}\n`);
}
NODE
}

zenmind_resolve_install_mode_from_state() {
  local state_file
  state_file="$(mktemp)"
  if ! zenmind_state_read_to_file "$state_file"; then
    rm -f "$state_file"
    return 1
  fi
  zenmind_json_get "$state_file" "installMode"
  rm -f "$state_file"
}

zenmind_resolve_or_bootstrap_state_to_file() {
  local output_file="$1"
  if zenmind_state_read_to_file "$output_file"; then
    return 0
  fi
  if zenmind_state_infer_source_to_file "$output_file"; then
    zenmind_state_write_from_file "$output_file"
    zenmind_summary_add_warn "install state was missing; inferred source mode from sibling repo layout"
    return 0
  fi
  return 1
}

zenmind_prompt_install_mode() {
  local action_label="$1"
  if [[ -n "${INSTALL_MODE:-}" ]]; then
    return 0
  fi

  local state_mode=""
  state_mode="$(zenmind_resolve_install_mode_from_state 2>/dev/null || true)"
  if [[ -n "$state_mode" && ("${NON_INTERACTIVE:-0}" == "1" || ! -t 0) ]]; then
    INSTALL_MODE="$state_mode"
    zenmind_summary_add_warn "${action_label} mode not specified; defaulting to current install mode: ${INSTALL_MODE}"
    return 0
  fi

  if [[ "${NON_INTERACTIVE:-0}" == "1" || ! -t 0 ]]; then
    zenmind_summary_add_fail "${action_label} requires --source or --release in non-interactive mode"
    return 1
  fi

  local choice
  echo
  echo "Choose ${action_label} mode:"
  echo "  1) Source install"
  echo "  2) Release install"
  read -r -p "Select [1]: " choice
  case "${choice:-1}" in
    1) INSTALL_MODE="source" ;;
    2) INSTALL_MODE="release" ;;
    *)
      INSTALL_MODE="source"
      zenmind_summary_add_warn "unknown ${action_label} mode '${choice}', defaulting to source"
      ;;
  esac
}

zenmind_current_mode_for_runtime_action() {
  local state_file
  state_file="$(mktemp)"
  if ! zenmind_resolve_or_bootstrap_state_to_file "$state_file"; then
    rm -f "$state_file"
    zenmind_summary_add_fail "install state missing and no managed source layout was detected"
    return 1
  fi
  zenmind_json_get "$state_file" "installMode"
  rm -f "$state_file"
}

zenmind_source_repo_dir() {
  local repo_name="$1"
  case "$repo_name" in
    zenmind) printf '%s\n' "$SCRIPT_DIR" ;;
    *) printf '%s/%s\n' "$(zenmind_repo_root_path)" "$repo_name" ;;
  esac
}

zenmind_source_repo_url() {
  case "$1" in
    zenmind) printf '%s\n' "" ;;
    zenmind-app-server) printf '%s\n' "https://github.com/linlay/zenmind-app-server-go.git" ;;
    zenmind-voice-server) printf '%s\n' "https://github.com/linlay/zenmind-voice-server.git" ;;
    zenmind-gateway) printf '%s\n' "https://github.com/linlay/zenmind-gateway.git" ;;
    agent-platform-runner) printf '%s\n' "https://github.com/linlay/agent-platform-runner.git" ;;
    agent-container-hub) printf '%s\n' "https://github.com/linlay/agent-container-hub.git" ;;
    pan-webclient) printf '%s\n' "https://github.com/linlay/pan-webclient.git" ;;
    term-webclient) printf '%s\n' "https://github.com/linlay/term-webclient.git" ;;
    mcp-server-mock) printf '%s\n' "https://github.com/linlay/mcp-server-mock.git" ;;
    mcp-server-imagine) printf '%s\n' "https://github.com/linlay/mcp-server-imagine.git" ;;
    *) printf '%s\n' "" ;;
  esac
}

zenmind_source_require_clean_repo() {
  local repo_name="$1"
  local repo_dir="$2"
  local status_output
  if ! git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    zenmind_summary_add_fail "repo is not a git worktree: ${repo_name}"
    return 1
  fi
  status_output="$(git -C "$repo_dir" status --porcelain 2>/dev/null || true)"
  if [[ -n "$status_output" ]]; then
    zenmind_summary_add_fail "dirty repo blocks source operation: ${repo_name}"
    return 1
  fi
}

zenmind_source_fetch_checkout() {
  local repo_name="$1"
  local repo_dir="$2"
  local target_tag="$3"
  setup_log "fetching tags for ${repo_name}"
  git -C "$repo_dir" fetch --tags --force >/dev/null
  setup_log "checking out ${repo_name} -> ${target_tag}"
  git -C "$repo_dir" checkout --detach "$target_tag" >/dev/null
}

zenmind_source_capture_refs() {
  local output_file="$1"
  node "$(zenmind_setup_state_cli_path)" source-refs --workspace-root "$SCRIPT_DIR" >"$output_file"
}

zenmind_source_rollback_refs() {
  local refs_json="$1"
  local repo_name ref repo_dir
  while IFS=$'\t' read -r repo_name ref; do
    [[ -n "$repo_name" && -n "$ref" ]] || continue
    repo_dir="$(zenmind_source_repo_dir "$repo_name")"
    if [[ -d "$repo_dir" ]] && git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      git -C "$repo_dir" checkout --detach "$ref" >/dev/null 2>&1 || true
    fi
  done < <(zenmind_source_refs_to_tsv "$refs_json")
}

zenmind_source_target_from_manifest() {
  local manifest_file="$1"
  local target_tag stack_version manifest_source
  target_tag="${TARGET_VERSION:-$(zenmind_json_get "$manifest_file" "sourceTag")}"
  stack_version="${TARGET_VERSION:-$(zenmind_json_get "$manifest_file" "stackVersion")}"
  manifest_source="$(zenmind_json_get "$manifest_file" "__source" 2>/dev/null || true)"
  printf '%s\t%s\t%s\n' "$target_tag" "$stack_version" "$manifest_source"
}

zenmind_source_target_without_manifest() {
  local assert_target="${TARGET_VERSION:-}"
  if [[ -z "$assert_target" ]]; then
    zenmind_summary_add_fail "source install/upgrade requires --target-version or a manifest source"
    return 1
  fi
  printf '%s\t%s\t%s\n' "$assert_target" "$assert_target" ""
}

zenmind_write_source_state() {
  local current_version="$1"
  local target_tag="$2"
  local manifest_source="$3"
  local previous_version="$4"
  local install_stamp="$5"
  local upgrade_stamp="$6"
  local refs_json tmp_file
  refs_json="$(mktemp)"
  tmp_file="$(mktemp)"
  zenmind_source_capture_refs "$refs_json"
  node --input-type=module - "$refs_json" "$current_version" "$target_tag" "$manifest_source" "$previous_version" "$install_stamp" "$upgrade_stamp" "$(zenmind_repo_root_path)" <<'NODE' >"$tmp_file"
import fs from "node:fs";

const [refsFile, currentVersion, targetTag, manifestSource, previousVersion, installStamp, upgradeStamp, reposRoot] = process.argv.slice(2);
const repoRefs = JSON.parse(fs.readFileSync(refsFile, "utf8"));
const state = {
  schemaVersion: 1,
  installMode: "source",
  channel: "stable",
  currentVersion,
  previousVersion,
  manifestSource,
  lastCheckedAt: "",
  lastInstalledAt: installStamp,
  lastUpgradedAt: upgradeStamp,
  source: {
    reposRoot,
    targetTag,
    repoRefs
  }
};
process.stdout.write(JSON.stringify(state, null, 2));
NODE
  zenmind_state_write_from_file "$tmp_file"
  rm -f "$refs_json" "$tmp_file"
}

zenmind_run_install_source() {
  local manifest_file target_tag stack_version manifest_source
  local repo_name repo_dir repo_url

  if ! setup_require_cmd git; then
    zenmind_summary_add_fail "git is required for source install"
    return 1
  fi
  zenmind_summary_add_ok "git available"

  if [[ -n "${MANIFEST_SOURCE_ARG:-}" || -z "${TARGET_VERSION:-}" ]]; then
    manifest_file="$(mktemp)"
    if ! zenmind_manifest_load_to_file "$manifest_file"; then
      rm -f "$manifest_file"
      zenmind_summary_add_fail "failed to load release manifest"
      return 1
    fi
    IFS=$'\t' read -r target_tag stack_version manifest_source < <(zenmind_source_target_from_manifest "$manifest_file")
    rm -f "$manifest_file"
  else
    IFS=$'\t' read -r target_tag stack_version manifest_source < <(zenmind_source_target_without_manifest)
  fi

  for repo_name in "${ZENMIND_SOURCE_REPOS[@]}"; do
    [[ "$repo_name" == "zenmind" ]] && continue
    repo_dir="$(zenmind_source_repo_dir "$repo_name")"
    repo_url="$(zenmind_source_repo_url "$repo_name")"
    if [[ ! -d "$repo_dir" ]]; then
      setup_log "cloning ${repo_url} -> ${repo_dir}"
      git clone "$repo_url" "$repo_dir" >/dev/null || {
        zenmind_summary_add_fail "failed to clone repo: ${repo_name}"
        return 1
      }
    fi
    zenmind_source_require_clean_repo "$repo_name" "$repo_dir" || return 1
    zenmind_source_fetch_checkout "$repo_name" "$repo_dir" "$target_tag" || {
      zenmind_summary_add_fail "failed to checkout ${repo_name} -> ${target_tag}"
      return 1
    }
    zenmind_summary_add_ok "prepared source repo: ${repo_name} -> ${target_tag}"
  done

  repo_dir="$(zenmind_source_repo_dir "zenmind")"
  zenmind_source_require_clean_repo "zenmind" "$repo_dir" || return 1
  zenmind_source_fetch_checkout "zenmind" "$repo_dir" "$target_tag" || {
    zenmind_summary_add_fail "failed to checkout zenmind -> ${target_tag}"
    return 1
  }
  zenmind_summary_add_ok "prepared source repo: zenmind -> ${target_tag}"

  zenmind_apply_config || return 1
  zenmind_write_source_state "$stack_version" "$target_tag" "$manifest_source" "" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" ""
  zenmind_summary_add_ok "recorded source install state: $(zenmind_install_state_path)"
}

zenmind_run_upgrade_source() {
  local state_file refs_file manifest_file target_tag stack_version manifest_source
  local repo_name repo_dir

  state_file="$(mktemp)"
  refs_file="$(mktemp)"
  if ! zenmind_resolve_or_bootstrap_state_to_file "$state_file"; then
    rm -f "$state_file" "$refs_file"
    zenmind_summary_add_fail "source upgrade requires an existing source installation"
    return 1
  fi
  if [[ "$(zenmind_json_get "$state_file" "installMode")" != "source" ]]; then
    rm -f "$state_file" "$refs_file"
    zenmind_summary_add_fail "current install mode is not source"
    return 1
  fi
  zenmind_source_capture_refs "$refs_file"

  if [[ -n "${MANIFEST_SOURCE_ARG:-}" || -z "${TARGET_VERSION:-}" ]]; then
    manifest_file="$(mktemp)"
    if ! zenmind_manifest_load_to_file "$manifest_file"; then
      rm -f "$state_file" "$refs_file" "$manifest_file"
      zenmind_summary_add_fail "failed to load release manifest"
      return 1
    fi
    IFS=$'\t' read -r target_tag stack_version manifest_source < <(zenmind_source_target_from_manifest "$manifest_file")
    rm -f "$manifest_file"
  else
    IFS=$'\t' read -r target_tag stack_version manifest_source < <(zenmind_source_target_without_manifest)
  fi

  for repo_name in "${ZENMIND_SOURCE_REPOS[@]}"; do
    repo_dir="$(zenmind_source_repo_dir "$repo_name")"
    [[ -d "$repo_dir" ]] || {
      zenmind_summary_add_fail "missing repo for source upgrade: ${repo_name}"
      zenmind_source_rollback_refs "$refs_file"
      rm -f "$state_file" "$refs_file"
      return 1
    }
    zenmind_source_require_clean_repo "$repo_name" "$repo_dir" || {
      zenmind_source_rollback_refs "$refs_file"
      rm -f "$state_file" "$refs_file"
      return 1
    }
  done

  for repo_name in "${ZENMIND_SOURCE_REPOS[@]}"; do
    [[ "$repo_name" == "zenmind" ]] && continue
    repo_dir="$(zenmind_source_repo_dir "$repo_name")"
    zenmind_source_fetch_checkout "$repo_name" "$repo_dir" "$target_tag" || {
      zenmind_summary_add_fail "failed to checkout ${repo_name} -> ${target_tag}"
      zenmind_source_rollback_refs "$refs_file"
      rm -f "$state_file" "$refs_file"
      return 1
    }
    zenmind_summary_add_ok "upgraded source repo: ${repo_name} -> ${target_tag}"
  done

  repo_dir="$(zenmind_source_repo_dir "zenmind")"
  zenmind_source_fetch_checkout "zenmind" "$repo_dir" "$target_tag" || {
    zenmind_summary_add_fail "failed to checkout zenmind -> ${target_tag}"
    zenmind_source_rollback_refs "$refs_file"
    rm -f "$state_file" "$refs_file"
    return 1
  }
  zenmind_summary_add_ok "upgraded source repo: zenmind -> ${target_tag}"

  if ! zenmind_apply_config; then
    zenmind_source_rollback_refs "$refs_file"
    rm -f "$state_file" "$refs_file"
    return 1
  fi

  zenmind_write_source_state "$stack_version" "$target_tag" "$manifest_source" "$(zenmind_json_get "$state_file" "currentVersion" 2>/dev/null || true)" "$(zenmind_json_get "$state_file" "lastInstalledAt" 2>/dev/null || true)" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  zenmind_summary_add_ok "recorded source upgrade state: $(zenmind_install_state_path)"
  rm -f "$state_file" "$refs_file"
}

zenmind_release_checksum() {
  openssl dgst -sha256 "$1" | awk '{print $2}'
}

zenmind_release_verify_checksum() {
  local file_path="$1"
  local expected="$2"
  [[ -z "$expected" ]] && return 0
  [[ "$(zenmind_release_checksum "$file_path")" == "$expected" ]]
}

zenmind_release_materialize_artifact() {
  local kind="$1"
  local source="$2"
  local target="$3"
  local expected_sha="$4"

  mkdir -p "$(dirname "$target")"
  if [[ -f "$target" ]] && zenmind_release_verify_checksum "$target" "$expected_sha"; then
    return 0
  fi

  if [[ "$kind" == "file" ]]; then
    [[ -f "$source" ]] || {
      zenmind_summary_add_fail "release artifact missing: ${source}"
      return 1
    }
    cp "$source" "$target"
  else
    curl -fsSL "$source" -o "$target"
  fi

  if ! zenmind_release_verify_checksum "$target" "$expected_sha"; then
    zenmind_summary_add_fail "checksum mismatch for artifact: $(basename "$target")"
    return 1
  fi
}

zenmind_release_extract_bundle_fresh() {
  local bundle="$1"
  local target="$2"
  local tmp_extract extracted_root

  if [[ -d "$target" ]]; then
    return 0
  fi

  tmp_extract="$(mktemp -d)"
  tar -xzf "$bundle" -C "$tmp_extract"
  extracted_root="$(find "$tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$extracted_root" ]] || {
    rm -rf "$tmp_extract"
    zenmind_summary_add_fail "failed to extract bundle: $bundle"
    return 1
  }
  mkdir -p "$(dirname "$target")"
  mv "$extracted_root" "$target"
  rm -rf "$tmp_extract"
}

zenmind_release_prepare_env_file() {
  local service_dir="$1"
  if [[ -f "$service_dir/.env.example" && ! -f "$service_dir/.env" ]]; then
    cp "$service_dir/.env.example" "$service_dir/.env"
  fi
}

zenmind_release_current_env_value() {
  local file="$1"
  local key="$2"
  local line
  [[ -f "$file" ]] || return 1
  line="$(grep -E "^${key}=" "$file" | tail -n 1 || true)"
  printf '%s\n' "${line#*=}"
}

zenmind_release_set_env_value() {
  local file="$1"
  local key="$2"
  local value="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" -v value="$value" '
    BEGIN { done = 0 }
    index($0, key "=") == 1 {
      print key "=" value
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print key "=" value
      }
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

zenmind_release_unset_env_key() {
  local file="$1"
  local key="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v key="$key" 'index($0, key "=") != 1 { print }' "$file" >"$tmp"
  mv "$tmp" "$file"
}

zenmind_release_set_yaml_enabled_false() {
  local file="$1"
  local tmp
  tmp="$(mktemp)"
  awk '
    BEGIN { done = 0 }
    $0 ~ /^enabled:[[:space:]]*/ {
      print "enabled: false"
      done = 1
      next
    }
    { print }
    END {
      if (!done) {
        print "enabled: false"
      }
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

zenmind_release_remove_line_exact() {
  local file="$1"
  local line="$2"
  local tmp
  tmp="$(mktemp)"
  awk -v line="$line" '$0 != line { print }' "$file" >"$tmp"
  mv "$tmp" "$file"
}

zenmind_release_remove_compose_bind_mount() {
  local file="$1"
  local source_line="$2"
  local target_line="$3"
  local tmp
  tmp="$(mktemp)"
  awk -v source_line="$source_line" -v target_line="$target_line" '
    {
      if ($0 == "      - type: bind") {
        line1 = $0
        if ((getline line2) <= 0) {
          print line1
          next
        }
        if ((getline line3) <= 0) {
          print line1
          print line2
          next
        }
        if (line2 == source_line && line3 == target_line) {
          next
        }
        print line1
        print line2
        print line3
        next
      }
      print
    }
  ' "$file" >"$tmp"
  mv "$tmp" "$file"
}

zenmind_release_patch_runner_bundle() {
  local version_dir="$1"
  local runner_dir
  runner_dir="$(zenmind_release_service_dir "$version_dir" "agent-platform-runner")"
  zenmind_release_remove_line_exact "$runner_dir/.env.example" "TOOLS_DIR=./runtime/tools"
  zenmind_release_remove_line_exact "$runner_dir/.env.example" "VIEWPORTS_DIR=./runtime/viewports"
  zenmind_release_remove_line_exact "$runner_dir/compose.release.yml" "      TOOLS_DIR: /opt/runtime/tools"
  zenmind_release_remove_line_exact "$runner_dir/compose.release.yml" "      VIEWPORTS_DIR: /opt/runtime/viewports"
  zenmind_release_remove_compose_bind_mount \
    "$runner_dir/compose.release.yml" \
    '        source: ${TOOLS_DIR:-./runtime/tools}' \
    '        target: /opt/runtime/tools'
  zenmind_release_remove_compose_bind_mount \
    "$runner_dir/compose.release.yml" \
    '        source: ${VIEWPORTS_DIR:-./runtime/viewports}' \
    '        target: /opt/runtime/viewports'
  zenmind_release_remove_line_exact "$runner_dir/start.sh" 'ensure_dir "${TOOLS_DIR:-$SCRIPT_DIR/runtime/tools}"'
  zenmind_release_remove_line_exact "$runner_dir/start.sh" 'ensure_dir "${VIEWPORTS_DIR:-$SCRIPT_DIR/runtime/viewports}"'
  chmod +x "$runner_dir/start.sh" "$runner_dir/stop.sh"
}

zenmind_release_prepare_agents_bundle() {
  local version_dir="$1"
  local bundle="$2"
  local deploy_zenmind_dir runner_dir mcp_templates_dir viewport_templates_dir tmp_extract extracted_root
  deploy_zenmind_dir="$(zenmind_release_zenmind_dir "$version_dir")"
  runner_dir="$(zenmind_release_service_dir "$version_dir" "agent-platform-runner")"
  mcp_templates_dir="$runner_dir/runtime/mcp-servers"
  viewport_templates_dir="$runner_dir/runtime/viewport-servers"

  rm -rf "$deploy_zenmind_dir/agents" "$deploy_zenmind_dir/configs/models" "$deploy_zenmind_dir/configs/providers"
  mkdir -p "$deploy_zenmind_dir/configs"
  tmp_extract="$(mktemp -d)"
  tar -xzf "$bundle" -C "$tmp_extract"
  extracted_root="$(find "$tmp_extract" -mindepth 1 -maxdepth 1 -type d | head -n 1)"
  [[ -n "$extracted_root" ]] || {
    rm -rf "$tmp_extract"
    zenmind_summary_add_fail "failed to extract agents bundle: $bundle"
    return 1
  }
  cp -R "$extracted_root/agents" "$deploy_zenmind_dir/agents"
  cp -R "$extracted_root/configs/models" "$deploy_zenmind_dir/configs/models"
  cp -R "$extracted_root/configs/providers" "$deploy_zenmind_dir/configs/providers"
  rm -rf "$tmp_extract"

  if [[ ! -d "$deploy_zenmind_dir/configs/mcp-servers" ]]; then
    cp -R "$mcp_templates_dir" "$deploy_zenmind_dir/configs/mcp-servers"
  fi
  if [[ ! -d "$deploy_zenmind_dir/configs/viewport-servers" ]]; then
    cp -R "$viewport_templates_dir" "$deploy_zenmind_dir/configs/viewport-servers"
  fi
}

zenmind_release_copy_previous_state() {
  local previous_version_dir="$1"
  local version_dir="$2"
  local previous_deploy target_deploy service_name
  [[ -n "$previous_version_dir" && -d "$previous_version_dir" ]] || return 0
  previous_deploy="$(zenmind_release_deploy_dir "$previous_version_dir")"
  target_deploy="$(zenmind_release_deploy_dir "$version_dir")"
  [[ -d "$previous_deploy" ]] || return 0

  if [[ -d "$previous_deploy/.zenmind" ]]; then
    mkdir -p "$target_deploy/.zenmind"
    cp -R "$previous_deploy/.zenmind/." "$target_deploy/.zenmind/"
  fi

  for service_name in "agent-container-hub" "agent-platform-runner" "mcp-server-imagine" "mcp-server-mock" "pan-webclient" "term-webclient" "zenmind-app-server" "zenmind-gateway" "zenmind-voice-server"; do
    if [[ -f "$previous_deploy/$service_name/.env" ]]; then
      cp "$previous_deploy/$service_name/.env" "$target_deploy/$service_name/.env"
    fi
    if [[ -d "$previous_deploy/$service_name/configs" ]]; then
      mkdir -p "$target_deploy/$service_name/configs"
      cp -R "$previous_deploy/$service_name/configs/." "$target_deploy/$service_name/configs/"
    fi
    if [[ -d "$previous_deploy/$service_name/data" ]]; then
      rm -rf "$target_deploy/$service_name/data"
      cp -R "$previous_deploy/$service_name/data" "$target_deploy/$service_name/data"
    fi
  done
}

zenmind_release_prepare_runner_runtime() {
  local version_dir="$1"
  local runner_dir deploy_zenmind_dir
  local current_agents_dir current_models_dir current_providers_dir current_mcp_servers_dir current_viewport_servers_dir
  runner_dir="$(zenmind_release_service_dir "$version_dir" "agent-platform-runner")"
  deploy_zenmind_dir="$(zenmind_release_zenmind_dir "$version_dir")"

  zenmind_release_prepare_env_file "$runner_dir"
  [[ -f "$runner_dir/configs/container-hub.yml" ]] || cp "$runner_dir/configs/container-hub.example.yml" "$runner_dir/configs/container-hub.yml"
  [[ -f "$runner_dir/configs/bash.yml" ]] || cp "$runner_dir/configs/bash.example.yml" "$runner_dir/configs/bash.yml"
  [[ -f "$runner_dir/configs/cors.yml" ]] || cp "$runner_dir/configs/cors.example.yml" "$runner_dir/configs/cors.yml"

  zenmind_release_set_env_value "$runner_dir/.env" "AGENT_AUTH_ENABLED" "true"
  zenmind_release_set_env_value "$runner_dir/.env" "AGENT_AUTH_LOCAL_PUBLIC_KEY_FILE" "./configs/local-public-key.pem"
  zenmind_release_set_env_value "$runner_dir/.env" "AGENT_AUTH_JWKS_URI" ""
  zenmind_release_set_env_value "$runner_dir/.env" "AGENT_AUTH_ISSUER" "http://127.0.0.1:11945"
  zenmind_release_unset_env_key "$runner_dir/.env" "TOOLS_DIR"
  zenmind_release_unset_env_key "$runner_dir/.env" "VIEWPORTS_DIR"

  current_agents_dir="$(zenmind_release_current_env_value "$runner_dir/.env" "AGENTS_DIR" || true)"
  if [[ -z "$current_agents_dir" || "$current_agents_dir" == "./runtime/agents" ]]; then
    zenmind_release_set_env_value "$runner_dir/.env" "AGENTS_DIR" "$deploy_zenmind_dir/agents"
  fi
  current_models_dir="$(zenmind_release_current_env_value "$runner_dir/.env" "MODELS_DIR" || true)"
  if [[ -z "$current_models_dir" || "$current_models_dir" == "./runtime/models" ]]; then
    zenmind_release_set_env_value "$runner_dir/.env" "MODELS_DIR" "$deploy_zenmind_dir/configs/models"
  fi
  current_providers_dir="$(zenmind_release_current_env_value "$runner_dir/.env" "PROVIDERS_DIR" || true)"
  if [[ -z "$current_providers_dir" || "$current_providers_dir" == "./runtime/providers" ]]; then
    zenmind_release_set_env_value "$runner_dir/.env" "PROVIDERS_DIR" "$deploy_zenmind_dir/configs/providers"
  fi
  current_mcp_servers_dir="$(zenmind_release_current_env_value "$runner_dir/.env" "MCP_SERVERS_DIR" || true)"
  if [[ -z "$current_mcp_servers_dir" || "$current_mcp_servers_dir" == "./runtime/mcp-servers" ]]; then
    zenmind_release_set_env_value "$runner_dir/.env" "MCP_SERVERS_DIR" "$deploy_zenmind_dir/configs/mcp-servers"
  fi
  current_viewport_servers_dir="$(zenmind_release_current_env_value "$runner_dir/.env" "VIEWPORT_SERVERS_DIR" || true)"
  if [[ -z "$current_viewport_servers_dir" || "$current_viewport_servers_dir" == "./runtime/viewport-servers" ]]; then
    zenmind_release_set_env_value "$runner_dir/.env" "VIEWPORT_SERVERS_DIR" "$deploy_zenmind_dir/configs/viewport-servers"
  fi

  zenmind_release_set_yaml_enabled_false "$deploy_zenmind_dir/configs/mcp-servers/bash.yml"
  zenmind_release_set_yaml_enabled_false "$deploy_zenmind_dir/configs/mcp-servers/database.yml"
  zenmind_release_set_yaml_enabled_false "$deploy_zenmind_dir/configs/mcp-servers/email.yml"
}

zenmind_release_prepare_term_config() {
  local version_dir="$1"
  local term_dir
  term_dir="$(zenmind_release_service_dir "$version_dir" "term-webclient")"
  zenmind_release_prepare_env_file "$term_dir"
  [[ -f "$term_dir/configs/agents.yml" ]] || cp "$term_dir/configs/agents.example.yml" "$term_dir/configs/agents.yml"
  zenmind_release_set_env_value "$term_dir/.env" "APP_AUTH_LOCAL_PUBLIC_KEY_FILE" "./configs/local-public-key.pem"
  zenmind_release_set_env_value "$term_dir/.env" "APP_AUTH_JWKS_URI" ""
  zenmind_release_set_env_value "$term_dir/.env" "APP_AUTH_ISSUER" "http://127.0.0.1:11945"
}

zenmind_release_patch_term_start() {
  local version_dir="$1"
  local start_script tmp
  start_script="$(zenmind_release_service_dir "$version_dir" "term-webclient")/start.sh"
  if grep -Fq 'BACKEND_PORT="${BACKEND_PORT}"' "$start_script"; then
    return 0
  fi
  tmp="$(mktemp)"
  awk '
    {
      print
      if ($0 ~ /-e PORT=11947 \\$/) {
        print "  -e BACKEND_PORT=\"${BACKEND_PORT}\" \\"
      }
    }
  ' "$start_script" >"$tmp"
  mv "$tmp" "$start_script"
  chmod +x "$start_script"
}

zenmind_release_prepare_pan_config() {
  local version_dir="$1"
  local pan_dir
  pan_dir="$(zenmind_release_service_dir "$version_dir" "pan-webclient")"
  zenmind_release_prepare_env_file "$pan_dir"
  zenmind_release_set_env_value "$pan_dir/.env" "APP_AUTH_LOCAL_PUBLIC_KEY_FILE" "./configs/local-public-key.pem"
}

zenmind_release_prepare_voice_config() {
  local version_dir="$1"
  local voice_dir
  voice_dir="$(zenmind_release_service_dir "$version_dir" "zenmind-voice-server")"
  zenmind_release_prepare_env_file "$voice_dir"
  zenmind_release_set_env_value "$voice_dir/.env" "APP_VOICE_TTS_LLM_RUNNER_BASE_URL" "http://agent-platform-runner:8080"
}

zenmind_release_copy_public_key_to_clients() {
  local version_dir="$1"
  local public_key
  public_key="$(zenmind_release_shared_auth_dir "$version_dir")/publicKey.pem"
  [[ -f "$public_key" ]] || {
    zenmind_summary_add_fail "missing exported public key: $public_key"
    return 1
  }
  cp "$public_key" "$(zenmind_release_service_dir "$version_dir" "pan-webclient")/configs/local-public-key.pem"
  cp "$public_key" "$(zenmind_release_service_dir "$version_dir" "term-webclient")/configs/local-public-key.pem"
  cp "$public_key" "$(zenmind_release_service_dir "$version_dir" "agent-platform-runner")/configs/local-public-key.pem"
}

zenmind_release_prepare_active_workspace() {
  local version_dir="$1"
  local deploy_dir
  deploy_dir="$(zenmind_release_deploy_dir "$version_dir")"

  [[ -d "$deploy_dir" ]] || {
    zenmind_summary_add_fail "release deploy directory missing: $deploy_dir"
    return 1
  }

  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "agent-container-hub")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "agent-platform-runner")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "mcp-server-imagine")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "mcp-server-mock")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "pan-webclient")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "term-webclient")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "zenmind-app-server")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "zenmind-gateway")"
  zenmind_release_prepare_env_file "$(zenmind_release_service_dir "$version_dir" "zenmind-voice-server")"

  zenmind_release_set_env_value "$(zenmind_release_service_dir "$version_dir" "zenmind-app-server")/.env" "AUTH_ISSUER" "http://127.0.0.1:11945"
  [[ -f "$(zenmind_release_service_dir "$version_dir" "mcp-server-imagine")/configs/provider.yml" ]] || \
    cp "$(zenmind_release_service_dir "$version_dir" "mcp-server-imagine")/configs/provider.example.yml" "$(zenmind_release_service_dir "$version_dir" "mcp-server-imagine")/configs/provider.yml"

  zenmind_release_patch_runner_bundle "$version_dir"
  zenmind_release_prepare_runner_runtime "$version_dir"
  zenmind_release_prepare_pan_config "$version_dir"
  zenmind_release_prepare_term_config "$version_dir"
  zenmind_release_patch_term_start "$version_dir"
  zenmind_release_prepare_voice_config "$version_dir"
}

zenmind_release_ensure_network() {
  if docker network inspect zenmind-network >/dev/null 2>&1; then
    return 0
  fi
  docker network create zenmind-network >/dev/null
}

zenmind_release_start_service() {
  local version_dir="$1"
  local service_name="$2"
  shift 2 || true
  local service_dir
  service_dir="$(zenmind_release_service_dir "$version_dir" "$service_name")"
  [[ -x "$service_dir/start.sh" ]] || {
    zenmind_summary_add_fail "release start script missing: ${service_dir}/start.sh"
    return 1
  }
  (
    cd "$service_dir"
    ./start.sh "$@"
  )
}

zenmind_release_stop_service_if_present() {
  local version_dir="$1"
  local service_name="$2"
  local service_dir
  service_dir="$(zenmind_release_service_dir "$version_dir" "$service_name")"
  if [[ -x "$service_dir/stop.sh" ]]; then
    (
      cd "$service_dir"
      ./stop.sh
    ) >/dev/null 2>&1 || true
  fi
}

zenmind_release_verify_http() {
  local url="$1"
  local label="$2"
  curl -fsS "$url" >/dev/null
  zenmind_summary_add_ok "verified ${label}: ${url}"
}

zenmind_release_verify_mcp() {
  local url="$1"
  local label="$2"
  local response
  response="$(curl -fsS -X POST "$url" -H 'Content-Type: application/json' -d '{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}')"
  if [[ "$response" != *'"jsonrpc":"2.0"'* && "$response" != *'"jsonrpc": "2.0"'* ]]; then
    zenmind_summary_add_fail "unexpected MCP response for ${label}: ${url}"
    return 1
  fi
  zenmind_summary_add_ok "verified ${label}: ${url}"
}

zenmind_release_verify_runner_agents() {
  local url="http://127.0.0.1:11949/api/agents"
  local response
  local attempt
  for attempt in $(seq 1 20); do
    response="$(curl -fsS "$url" 2>/dev/null || true)"
    if [[ "$response" == *'"code":0'* && "$response" == *'dailyOfficeAssistant'* ]]; then
      zenmind_summary_add_ok "verified runner agent catalog: ${url}"
      return 0
    fi
    sleep 2
  done
  zenmind_summary_add_fail "runner agent catalog did not become ready: ${url}"
  return 1
}

zenmind_release_start_version() {
  local version_dir="$1"
  local key_script

  if ! setup_prepare_docker_alias; then
    zenmind_summary_add_fail "docker is required for release start"
    return 1
  fi
  docker compose version >/dev/null 2>&1 || {
    zenmind_summary_add_fail "docker compose is required for release start"
    return 1
  }
  setup_docker_daemon_running || {
    zenmind_summary_add_fail "docker daemon is not running; start Docker first"
    return 1
  }
  key_script="$(zenmind_app_server_key_script)"
  [[ -x "$key_script" ]] || {
    zenmind_summary_add_fail "app-server key export script missing: ${key_script}"
    return 1
  }

  zenmind_release_prepare_active_workspace "$version_dir" || return 1
  zenmind_release_ensure_network || return 1

  zenmind_release_start_service "$version_dir" "zenmind-app-server" || return 1
  "$key_script" \
    --db "$(zenmind_release_service_dir "$version_dir" "zenmind-app-server")/data/auth.db" \
    --out "$(zenmind_release_shared_auth_dir "$version_dir")" \
    --public-out "$(zenmind_release_shared_auth_dir "$version_dir")/publicKey.pem" || return 1

  zenmind_release_copy_public_key_to_clients "$version_dir" || return 1

  zenmind_release_start_service "$version_dir" "pan-webclient" || return 1
  zenmind_release_start_service "$version_dir" "term-webclient" || return 1
  zenmind_release_start_service "$version_dir" "mcp-server-mock" || return 1
  zenmind_release_start_service "$version_dir" "mcp-server-imagine" || return 1
  zenmind_release_start_service "$version_dir" "agent-container-hub" --daemon || return 1
  zenmind_release_start_service "$version_dir" "agent-platform-runner" || return 1
  zenmind_release_start_service "$version_dir" "zenmind-voice-server" || return 1
  zenmind_release_start_service "$version_dir" "zenmind-gateway" || return 1

  zenmind_release_verify_http "http://127.0.0.1:11945/healthz" "gateway health" || return 1
  zenmind_release_verify_http "http://127.0.0.1:11946/pan/" "pan frontend" || return 1
  zenmind_release_verify_http "http://127.0.0.1:11947/term/" "term frontend" || return 1
  zenmind_release_verify_http "http://127.0.0.1:11950/admin/" "app admin frontend" || return 1
  zenmind_release_verify_http "http://127.0.0.1:11953/actuator/health" "voice backend health" || return 1
  zenmind_release_verify_runner_agents || return 1
  zenmind_release_verify_mcp "http://127.0.0.1:11969/mcp" "mock MCP" || return 1
  zenmind_release_verify_mcp "http://127.0.0.1:11962/mcp" "imagine MCP" || return 1
}

zenmind_release_stop_version() {
  local version_dir="$1"
  local service_name
  for service_name in "${ZENMIND_RELEASE_STOP_SERVICES[@]}"; do
    zenmind_release_stop_service_if_present "$version_dir" "$service_name"
  done
  zenmind_summary_add_ok "stopped release services under: ${version_dir}"
}

zenmind_release_state_write() {
  local current_version="$1"
  local previous_version="$2"
  local manifest_source="$3"
  local active_version_dir="$4"
  local staged_version_dir="$5"
  local install_stamp="$6"
  local upgrade_stamp="$7"
  local tmp_file
  tmp_file="$(mktemp)"
  node --input-type=module - "$current_version" "$previous_version" "$manifest_source" "$active_version_dir" "$staged_version_dir" "$install_stamp" "$upgrade_stamp" "$(zenmind_release_root_path)" <<'NODE' >"$tmp_file"
const [
  currentVersion,
  previousVersion,
  manifestSource,
  activeVersionDir,
  stagedVersionDir,
  installStamp,
  upgradeStamp,
  installRoot
] = process.argv.slice(2);

process.stdout.write(JSON.stringify({
  schemaVersion: 1,
  installMode: "release",
  channel: "stable",
  currentVersion,
  previousVersion,
  manifestSource,
  lastCheckedAt: "",
  lastInstalledAt: installStamp,
  lastUpgradedAt: upgradeStamp,
  release: {
    installRoot,
    activeVersionDir,
    stagedVersionDir
  }
}, null, 2));
NODE
  zenmind_state_write_from_file "$tmp_file"
  rm -f "$tmp_file"
}

zenmind_release_prepare_version_dir() {
  local target_version="$1"
  local previous_active="$2"
  local manifest_source="$3"
  local manifest_file host_os host_arch manifest_version artifacts_json artifacts_dir version_dir deploy_dir
  local service_name file_name runtime sha256 source_kind source_value target_path agents_bundle=""

  manifest_file="$(mktemp)"
  artifacts_json="$(mktemp)"
  if ! zenmind_manifest_load_to_file "$manifest_file"; then
    rm -f "$manifest_file" "$artifacts_json"
    zenmind_summary_add_fail "failed to load release manifest"
    return 1
  fi
  manifest_version="$(zenmind_json_get "$manifest_file" "stackVersion")"
  if [[ "$target_version" != "$manifest_version" ]]; then
    rm -f "$manifest_file" "$artifacts_json"
    zenmind_summary_add_fail "target version ${target_version} does not match manifest version ${manifest_version}"
    return 1
  fi
  host_os="$(zenmind_host_os)" || { rm -f "$manifest_file" "$artifacts_json"; return 1; }
  host_arch="$(zenmind_host_arch)" || { rm -f "$manifest_file" "$artifacts_json"; return 1; }
  MANIFEST_SOURCE_ARG="${MANIFEST_SOURCE_ARG:-$manifest_source}"
  zenmind_manifest_artifacts_to_file "$artifacts_json" "$host_os" "$host_arch" || {
    rm -f "$manifest_file" "$artifacts_json"
    zenmind_summary_add_fail "failed to resolve release artifacts"
    return 1
  }

  version_dir="$(zenmind_release_version_dir "$target_version")"
  artifacts_dir="$(zenmind_release_artifacts_dir "$version_dir")"
  deploy_dir="$(zenmind_release_deploy_dir "$version_dir")"
  mkdir -p "$artifacts_dir" "$deploy_dir"

  while IFS=$'\t' read -r service_name file_name runtime sha256 source_kind source_value; do
    [[ -n "$service_name" ]] || continue
    target_path="$artifacts_dir/$file_name"
    zenmind_release_materialize_artifact "$source_kind" "$source_value" "$target_path" "$sha256" || {
      rm -f "$manifest_file" "$artifacts_json"
      return 1
    }
    if [[ "$service_name" == "zenmind-agents" ]]; then
      agents_bundle="$target_path"
      continue
    fi
    zenmind_release_extract_bundle_fresh "$target_path" "$deploy_dir/$service_name" || {
      rm -f "$manifest_file" "$artifacts_json"
      return 1
    }
  done < <(zenmind_manifest_artifacts_to_tsv "$artifacts_json")

  [[ -n "$agents_bundle" ]] || {
    rm -f "$manifest_file" "$artifacts_json"
    zenmind_summary_add_fail "manifest is missing zenmind-agents artifact"
    return 1
  }
  zenmind_release_prepare_agents_bundle "$version_dir" "$agents_bundle" || {
    rm -f "$manifest_file" "$artifacts_json"
    return 1
  }
  zenmind_release_copy_previous_state "$previous_active" "$version_dir"
  zenmind_release_prepare_active_workspace "$version_dir" || {
    rm -f "$manifest_file" "$artifacts_json"
    return 1
  }
  cp "$manifest_file" "$version_dir/release-manifest.json"
  rm -f "$manifest_file" "$artifacts_json"
  ZENMIND_PREPARED_RELEASE_VERSION_DIR="$version_dir"
}

zenmind_run_install_release() {
  local manifest_file state_file target_version manifest_version manifest_source previous_active="" version_dir

  manifest_file="$(mktemp)"
  if ! zenmind_manifest_load_to_file "$manifest_file"; then
    rm -f "$manifest_file"
    zenmind_summary_add_fail "failed to load release manifest"
    return 1
  fi
  manifest_version="$(zenmind_json_get "$manifest_file" "stackVersion")"
  target_version="${TARGET_VERSION:-$manifest_version}"
  manifest_source="$(zenmind_json_get "$manifest_file" "__source" 2>/dev/null || true)"

  state_file="$(mktemp)"
  if zenmind_state_read_to_file "$state_file"; then
    previous_active="$(zenmind_json_get "$state_file" "release.activeVersionDir" 2>/dev/null || true)"
  fi
  rm -f "$state_file" "$manifest_file"

  zenmind_release_prepare_version_dir "$target_version" "$previous_active" "$manifest_source" || return 1
  version_dir="$ZENMIND_PREPARED_RELEASE_VERSION_DIR"
  zenmind_release_state_write "$target_version" "" "$manifest_source" "$version_dir" "" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" ""
  zenmind_summary_add_ok "prepared release workspace: ${version_dir}"
  zenmind_summary_add_ok "recorded release install state: $(zenmind_install_state_path)"
}

zenmind_run_upgrade_release() {
  local state_file manifest_file current_version active_version_dir target_version manifest_version manifest_source staged_version_dir install_stamp

  state_file="$(mktemp)"
  manifest_file="$(mktemp)"
  if ! zenmind_resolve_or_bootstrap_state_to_file "$state_file"; then
    rm -f "$state_file" "$manifest_file"
    zenmind_summary_add_fail "release upgrade requires an existing installation"
    return 1
  fi
  if [[ "$(zenmind_json_get "$state_file" "installMode")" != "release" ]]; then
    rm -f "$state_file" "$manifest_file"
    zenmind_summary_add_fail "current install mode is not release"
    return 1
  fi
  current_version="$(zenmind_json_get "$state_file" "currentVersion")"
  active_version_dir="$(zenmind_json_get "$state_file" "release.activeVersionDir")"
  install_stamp="$(zenmind_json_get "$state_file" "lastInstalledAt" 2>/dev/null || true)"

  zenmind_manifest_load_to_file "$manifest_file" || {
    rm -f "$state_file" "$manifest_file"
    zenmind_summary_add_fail "failed to load release manifest"
    return 1
  }
  manifest_version="$(zenmind_json_get "$manifest_file" "stackVersion")"
  target_version="${TARGET_VERSION:-$manifest_version}"
  manifest_source="$(zenmind_json_get "$manifest_file" "__source" 2>/dev/null || true)"
  if [[ "$current_version" == "$target_version" ]]; then
    rm -f "$state_file" "$manifest_file"
    zenmind_summary_add_warn "release install is already at ${current_version}"
    return 0
  fi

  MANIFEST_SOURCE_ARG="${MANIFEST_SOURCE_ARG:-$manifest_source}"
  zenmind_release_prepare_version_dir "$target_version" "$active_version_dir" "$manifest_source" || {
    rm -f "$state_file" "$manifest_file"
    return 1
  }
  staged_version_dir="$ZENMIND_PREPARED_RELEASE_VERSION_DIR"

  zenmind_release_stop_version "$active_version_dir"
  if ! zenmind_release_start_version "$staged_version_dir"; then
    zenmind_release_stop_version "$staged_version_dir"
    zenmind_release_start_version "$active_version_dir" >/dev/null 2>&1 || true
    rm -f "$state_file" "$manifest_file"
    zenmind_summary_add_fail "release upgrade failed; previous version was restarted if possible"
    return 1
  fi

  zenmind_release_state_write "$target_version" "$current_version" "$manifest_source" "$staged_version_dir" "" "$install_stamp" "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
  zenmind_summary_add_ok "upgraded release stack: ${current_version} -> ${target_version}"
  rm -f "$state_file" "$manifest_file"
}

zenmind_run_check_update() {
  local manifest_file state_file install_mode current_version latest_version next_hint
  manifest_file="$(mktemp)"
  if ! zenmind_manifest_load_to_file "$manifest_file"; then
    rm -f "$manifest_file"
    zenmind_summary_add_fail "failed to load release manifest"
    return 1
  fi

  state_file="$(mktemp)"
  if ! zenmind_resolve_or_bootstrap_state_to_file "$state_file"; then
    latest_version="$(zenmind_json_get "$manifest_file" "stackVersion")"
    zenmind_summary_add_ok "latest stable version: ${latest_version}"
    zenmind_summary_add_warn "no install state found; next step: ./setup-${ZENMIND_OS}.sh --action install --source --manifest ${MANIFEST_SOURCE_ARG:-https://www.zenmind.cc/install/manifest.json}"
    rm -f "$manifest_file" "$state_file"
    return 0
  fi

  install_mode="$(zenmind_json_get "$state_file" "installMode")"
  current_version="$(zenmind_json_get "$state_file" "currentVersion")"
  if [[ "$install_mode" == "source" ]]; then
    latest_version="$(zenmind_json_get "$manifest_file" "sourceTag")"
    zenmind_summary_add_ok "source current tag: ${current_version}"
    zenmind_summary_add_ok "source latest stable tag: ${latest_version}"
    if [[ "$current_version" != "$latest_version" ]]; then
      zenmind_summary_add_warn "source upgrade available: ${current_version} -> ${latest_version}"
    fi
  else
    latest_version="$(zenmind_json_get "$manifest_file" "stackVersion")"
    zenmind_summary_add_ok "release current version: ${current_version}"
    zenmind_summary_add_ok "release latest stable version: ${latest_version}"
    if [[ "$current_version" != "$latest_version" ]]; then
      zenmind_summary_add_warn "release upgrade available: ${current_version} -> ${latest_version}"
    fi
  fi

  next_hint="$(zenmind_json_get "$manifest_file" "__source" 2>/dev/null || true)"
  [[ -n "$next_hint" ]] && zenmind_summary_add_ok "version source: ${next_hint}"
  rm -f "$manifest_file" "$state_file"
}

zenmind_release_logs() {
  local version_dir="$1"
  local target="$2"
  local tail_count="${VIEW_TAIL:-100}"
  local service_dir compose_file mounts_file

  case "$target" in
    agent-container-hub)
      tail -n "$tail_count" "$(zenmind_release_service_dir "$version_dir" "agent-container-hub")/.runtime/agent-container-hub.log"
      return 0
      ;;
    term-webclient)
      tail -n "$tail_count" "$(zenmind_release_service_dir "$version_dir" "term-webclient")/logs/backend.out"
      return 0
      ;;
    all)
      zenmind_summary_add_warn "release log target 'all' is not supported in one command; choose a service name"
      return 1
      ;;
  esac

  service_dir="$(zenmind_release_service_dir "$version_dir" "$target")"
  compose_file=""
  if [[ -f "$service_dir/compose.release.yml" ]]; then
    compose_file="$service_dir/compose.release.yml"
  elif [[ -f "$service_dir/docker-compose.release.yml" ]]; then
    compose_file="$service_dir/docker-compose.release.yml"
  fi
  [[ -n "$compose_file" ]] || {
    zenmind_summary_add_fail "no release compose file found for log target: ${target}"
    return 1
  }

  mounts_file="$service_dir/.runtime/docker-compose.mounts.yml"
  if [[ -f "$mounts_file" ]]; then
    docker compose -f "$compose_file" -f "$mounts_file" logs --tail "$tail_count"
  else
    docker compose -f "$compose_file" logs --tail "$tail_count"
  fi
}

zenmind_run_view_release() {
  local state_file version_dir pid_file
  state_file="$(mktemp)"
  if ! zenmind_resolve_or_bootstrap_state_to_file "$state_file"; then
    rm -f "$state_file"
    zenmind_summary_add_fail "release view requires an existing installation"
    return 1
  fi
  version_dir="$(zenmind_json_get "$state_file" "release.activeVersionDir")"
  zenmind_summary_add_ok "active release version dir: ${version_dir}"

  docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'
  pid_file="$(zenmind_release_service_dir "$version_dir" "agent-container-hub")/.runtime/agent-container-hub.pid"
  if [[ -f "$pid_file" ]]; then
    zenmind_summary_add_ok "agent-container-hub pid file: ${pid_file}"
  else
    zenmind_summary_add_warn "agent-container-hub pid file missing"
  fi
  if curl -fsS http://127.0.0.1:11945/healthz >/dev/null 2>&1; then
    zenmind_summary_add_ok "gateway healthz reachable"
  else
    zenmind_summary_add_warn "gateway healthz unavailable"
  fi
  if [[ -n "${VIEW_LOG_TARGET:-}" ]]; then
    zenmind_release_logs "$version_dir" "$VIEW_LOG_TARGET" || {
      rm -f "$state_file"
      return 1
    }
  fi
  rm -f "$state_file"
}

zenmind_run_install() {
  zenmind_prompt_install_mode "install" || return 1
  case "$INSTALL_MODE" in
    source) zenmind_run_install_source ;;
    release) zenmind_run_install_release ;;
    *) zenmind_summary_add_fail "unsupported install mode: ${INSTALL_MODE}"; return 1 ;;
  esac
}

zenmind_run_upgrade() {
  zenmind_prompt_install_mode "upgrade" || return 1
  case "$INSTALL_MODE" in
    source) zenmind_run_upgrade_source ;;
    release) zenmind_run_upgrade_release ;;
    *) zenmind_summary_add_fail "unsupported upgrade mode: ${INSTALL_MODE}"; return 1 ;;
  esac
}

zenmind_run_start() {
  local install_mode state_file version_dir
  install_mode="$(zenmind_current_mode_for_runtime_action)" || return 1
  case "$install_mode" in
    source)
      zenmind_run_start_source
      ;;
    release)
      state_file="$(mktemp)"
      zenmind_resolve_or_bootstrap_state_to_file "$state_file" || { rm -f "$state_file"; return 1; }
      version_dir="$(zenmind_json_get "$state_file" "release.activeVersionDir")"
      rm -f "$state_file"
      zenmind_release_start_version "$version_dir"
      ;;
    *)
      zenmind_summary_add_fail "unsupported install mode: ${install_mode}"
      return 1
      ;;
  esac
}

zenmind_run_stop() {
  local install_mode state_file version_dir
  install_mode="$(zenmind_current_mode_for_runtime_action)" || return 1
  case "$install_mode" in
    source)
      zenmind_run_stop_source
      ;;
    release)
      state_file="$(mktemp)"
      zenmind_resolve_or_bootstrap_state_to_file "$state_file" || { rm -f "$state_file"; return 1; }
      version_dir="$(zenmind_json_get "$state_file" "release.activeVersionDir")"
      rm -f "$state_file"
      zenmind_release_stop_version "$version_dir"
      ;;
    *)
      zenmind_summary_add_fail "unsupported install mode: ${install_mode}"
      return 1
      ;;
  esac
}

zenmind_run_view() {
  local install_mode
  install_mode="$(zenmind_current_mode_for_runtime_action)" || return 1
  case "$install_mode" in
    source) zenmind_run_view_source ;;
    release) zenmind_run_view_release ;;
    *)
      zenmind_summary_add_fail "unsupported install mode: ${install_mode}"
      return 1
      ;;
  esac
}

zenmind_run_download_all() {
  INSTALL_MODE="source"
  zenmind_summary_add_warn "download-all is deprecated; using install --source"
  zenmind_run_install_source
}

zenmind_usage() {
  cat <<USAGE
Usage: ./setup-<os>.sh [--action ACTION] [options]

Interactive menu (default):
  1) 环境检测
  2) 用户配置
  3) 安装
  4) 升级
  5) 启动
  6) 停止
  7) 查看状态/日志
  8) 检查新版本
  0) 退出

Options:
  --action         check | configure | install | upgrade | start | stop | view | check-update | download-all
  --source         install/upgrade mode: source repos
  --release        install/upgrade mode: release bundles
  --manifest <x>   manifest URL, manifest file path, or a local dist/<version> directory
  --target-version <vX.Y.Z>
  --web            configure mode: open the local HTML config editor
  --cli            configure mode: run the interactive CLI wizard
  --sync-only      configure mode: regenerate derived files only
  --logs <name>    view mode: show logs for one product/service
  --tail <N>       view mode: number of log lines to show (default 100)
  --follow         view mode: follow logs
  --yes            non-interactive mode
  -h, --help

Deprecated aliases (still accepted for now):
  precheck -> check
  edit-config -> configure --web
  apply-config -> configure --sync-only
  status -> view
  download-all -> install --source
USAGE
}

zenmind_menu() {
  cat <<MENU
1) 环境检测
2) 用户配置
3) 安装
4) 升级
5) 启动
6) 停止
7) 查看状态/日志
8) 检查新版本
0) 退出
MENU
}

zenmind_parse_args() {
  ACTION=""
  NON_INTERACTIVE=0
  CONFIGURE_MODE=""
  VIEW_LOG_TARGET=""
  VIEW_TAIL=100
  VIEW_FOLLOW=0
  INSTALL_MODE=""
  MANIFEST_SOURCE_ARG=""
  TARGET_VERSION=""

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --action)
        ACTION="$2"
        shift 2
        ;;
      --web)
        CONFIGURE_MODE="web"
        shift
        ;;
      --cli)
        CONFIGURE_MODE="cli"
        shift
        ;;
      --sync-only)
        CONFIGURE_MODE="sync-only"
        shift
        ;;
      --source)
        INSTALL_MODE="source"
        shift
        ;;
      --release)
        INSTALL_MODE="release"
        shift
        ;;
      --manifest)
        MANIFEST_SOURCE_ARG="$2"
        shift 2
        ;;
      --target-version)
        TARGET_VERSION="$2"
        shift 2
        ;;
      --logs)
        VIEW_LOG_TARGET="$2"
        shift 2
        ;;
      --tail)
        VIEW_TAIL="$2"
        shift 2
        ;;
      --follow)
        VIEW_FOLLOW=1
        shift
        ;;
      --yes)
        NON_INTERACTIVE=1
        shift
        ;;
      -h|--help)
        zenmind_usage
        exit 0
        ;;
      *)
        setup_err "unknown option: $1"
        zenmind_usage
        exit 1
        ;;
    esac
  done

  case "$ACTION" in
    precheck)
      zenmind_warn_deprecated_alias "precheck -> check"
      ACTION="check"
      ;;
    edit-config)
      zenmind_warn_deprecated_alias "edit-config -> configure --web"
      ACTION="configure"
      CONFIGURE_MODE="${CONFIGURE_MODE:-web}"
      ;;
    apply-config)
      zenmind_warn_deprecated_alias "apply-config -> configure --sync-only"
      ACTION="configure"
      CONFIGURE_MODE="${CONFIGURE_MODE:-sync-only}"
      ;;
    status)
      zenmind_warn_deprecated_alias "status -> view"
      ACTION="view"
      ;;
    download-all)
      zenmind_warn_deprecated_alias "download-all -> install --source"
      ACTION="install"
      INSTALL_MODE="source"
      ;;
  esac
}

zenmind_dispatch() {
  case "$ACTION" in
    check) zenmind_run_check ;;
    configure) zenmind_run_configure ;;
    install) zenmind_run_install ;;
    upgrade) zenmind_run_upgrade ;;
    start) zenmind_run_start ;;
    stop) zenmind_run_stop ;;
    view) zenmind_run_view ;;
    check-update) zenmind_run_check_update ;;
    download-all) zenmind_run_download_all ;;
    *)
      zenmind_summary_add_fail "unsupported action: $ACTION"
      return 1
      ;;
  esac
}

zenmind_interactive_loop() {
  local choice
  while true; do
    echo
    zenmind_menu
    read -r -p "Select an action: " choice
    case "$choice" in
      1) ACTION="check" ;;
      2) ACTION="configure"; CONFIGURE_MODE="" ;;
      3) ACTION="install"; INSTALL_MODE="" ;;
      4) ACTION="upgrade"; INSTALL_MODE="" ;;
      5) ACTION="start" ;;
      6) ACTION="stop" ;;
      7) ACTION="view" ;;
      8) ACTION="check-update" ;;
      0) exit 0 ;;
      *) setup_warn "unknown choice: $choice"; continue ;;
    esac
    zenmind_summary_reset
    zenmind_dispatch
    zenmind_print_summary "$ACTION"
  done
}
