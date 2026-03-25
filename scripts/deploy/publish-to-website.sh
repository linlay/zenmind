#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZENMIND_REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
DIST_ROOT="${ZENMIND_REPO_ROOT}/dist"
DEFAULT_REMOTE_ROOT="${ZENMIND_REMOTE_RELEASE_ROOT:-/docker/zenmind-releases}"
DEFAULT_SITE_MANIFEST_URL="${ZENMIND_SITE_MANIFEST_URL:-https://www.zenmind.cc/install/manifest.json}"

usage() {
  cat <<'EOF'
Usage: publish-to-website.sh <version> [--server user@host] [--remote-root /path] [--site-manifest-url https://...]

Examples:
  ./scripts/deploy/publish-to-website.sh v1.2.3 --server deploy@example.com
EOF
}

log() {
  printf '[publish-to-website] %s\n' "$*"
}

fail() {
  printf '[publish-to-website] ERROR: %s\n' "$*" >&2
  exit 1
}

release_line_for_version() {
  local version="${1#v}"
  local major minor patch
  IFS='.' read -r major minor patch <<<"$version"
  printf 'v%s.%s\n' "$major" "$minor"
}

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required command: $1"
}

VERSION="${1:-}"
[[ -n "$VERSION" ]] || {
  usage
  exit 1
}
shift || true

SERVER="${ZENMIND_WEBSITE_SERVER:-}"
REMOTE_ROOT="$DEFAULT_REMOTE_ROOT"
SITE_MANIFEST_URL="$DEFAULT_SITE_MANIFEST_URL"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --server)
      SERVER="$2"
      shift 2
      ;;
    --remote-root)
      REMOTE_ROOT="$2"
      shift 2
      ;;
    --site-manifest-url)
      SITE_MANIFEST_URL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "version must match vX.Y.Z"
[[ -n "$SERVER" ]] || fail "--server is required (or set ZENMIND_WEBSITE_SERVER)"

require_cmd rsync
require_cmd curl
require_cmd node

RELEASE_LINE="$(release_line_for_version "$VERSION")"
PATCH_DIR="${DIST_ROOT}/${RELEASE_LINE}/patches/${VERSION}"
LINE_DIR="${DIST_ROOT}/${RELEASE_LINE}"

log "refreshing dist manifests for ${VERSION}"
"${SCRIPT_DIR}/collect-dist.sh" "$VERSION"

[[ -d "$PATCH_DIR" ]] || fail "missing patch directory: $PATCH_DIR"
[[ -f "${PATCH_DIR}/release-manifest.json" ]] || fail "missing patch release-manifest.json"
[[ -f "${PATCH_DIR}/SHA256SUMS" ]] || fail "missing patch SHA256SUMS"
[[ -f "${LINE_DIR}/release-manifest.json" ]] || fail "missing release-line manifest"
[[ -f "${DIST_ROOT}/manifest.json" ]] || fail "missing top-level manifest.json"
[[ -f "${DIST_ROOT}/index.json" ]] || fail "missing top-level index.json"

log "uploading ${DIST_ROOT}/ to ${SERVER}:${REMOTE_ROOT}/"
rsync -av --delete "${DIST_ROOT}/" "${SERVER}:${REMOTE_ROOT}/"

log "verifying published manifest: ${SITE_MANIFEST_URL}"
MANIFEST_BODY="$(curl -fsSL "$SITE_MANIFEST_URL")" || fail "failed to fetch ${SITE_MANIFEST_URL}"
PUBLISHED_VERSION="$(node --input-type=module -e 'const body = JSON.parse(process.argv[1]); process.stdout.write(String(body.stackVersion || ""));' "$MANIFEST_BODY")"
[[ "$PUBLISHED_VERSION" == "$VERSION" ]] || fail "published manifest version mismatch: expected ${VERSION}, got ${PUBLISHED_VERSION:-<empty>}"

log "publish succeeded for ${VERSION}"
