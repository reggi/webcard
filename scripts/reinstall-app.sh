#!/bin/bash

set -euo pipefail

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
destination="${WEBCARD_INSTALL_PATH:-/Applications/Webcard.app}"
lock_directory="${TMPDIR:-/tmp}/webcard-reinstall-${UID}.lock"
owner_file="${lock_directory}/owner"
stale_lock=""

case "${destination}" in
    /*/Webcard.app) ;;
    *)
        echo "WEBCARD_INSTALL_PATH must be an absolute path ending in Webcard.app." >&2
        exit 64
        ;;
esac

describe_lock() {
    echo "Another agent is already rebuilding or reinstalling Webcard." >&2
    if [[ -f "${owner_file}" ]]; then
        sed 's/^/  /' "${owner_file}" >&2
    else
        echo "  The lock is being initialized. Try again after the other agent finishes." >&2
    fi
}

acquire_lock() {
    if mkdir "${lock_directory}" 2>/dev/null; then
        return
    fi

    if [[ ! -f "${owner_file}" ]]; then
        describe_lock
        exit 75
    fi

    local owner_pid
    owner_pid="$(sed -n 's/^pid=//p' "${owner_file}")"
    if [[ ! "${owner_pid}" =~ ^[0-9]+$ ]] || kill -0 "${owner_pid}" 2>/dev/null; then
        describe_lock
        exit 75
    fi

    stale_lock="${lock_directory}.stale.$$"
    if ! mv "${lock_directory}" "${stale_lock}" 2>/dev/null; then
        describe_lock
        exit 75
    fi
    rm -rf "${stale_lock}"
    stale_lock=""

    if ! mkdir "${lock_directory}" 2>/dev/null; then
        describe_lock
        exit 75
    fi
}

release_lock() {
    if [[ -f "${owner_file}" ]] && [[ "$(sed -n 's/^pid=//p' "${owner_file}")" == "$$" ]]; then
        rm -rf "${lock_directory}"
    fi
    if [[ -n "${stale_lock}" ]] && [[ -d "${stale_lock}" ]]; then
        rm -rf "${stale_lock}"
    fi
}

acquire_lock
trap release_lock EXIT HUP INT TERM

cat > "${owner_file}" <<EOF
owner=${WEBCARD_INSTALL_OWNER:-${USER:-unknown}@$(hostname -s)}
pid=$$
started=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
repository=${repository_root}
destination=${destination}
EOF

cd "${repository_root}"

echo "Testing Webcard..."
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=safe.bareRepository \
GIT_CONFIG_VALUE_0=all \
swift test --quiet

echo "Building Webcard..."
GIT_CONFIG_COUNT=1 \
GIT_CONFIG_KEY_0=safe.bareRepository \
GIT_CONFIG_VALUE_0=all \
xcodebuild \
    -quiet \
    -project Webcard.xcodeproj \
    -target Webcard \
    -configuration Debug \
    SYMROOT="${repository_root}/.build/xcode-target" \
    OBJROOT="${repository_root}/.build/xcode-target/obj" \
    ONLY_ACTIVE_ARCH=YES \
    ARCHS=arm64 \
    CODE_SIGN_IDENTITY=- \
    CODE_SIGN_STYLE=Manual \
    build

built_app="${repository_root}/.build/xcode-target/Debug/Webcard.app"
if [[ ! -d "${built_app}" ]]; then
    echo "Build succeeded but ${built_app} was not created." >&2
    exit 1
fi

destination_parent="$(dirname "${destination}")"
staging_app="${destination}.installing.$$"
backup_app="${destination}.previous.$$"

mkdir -p "${destination_parent}"
rm -rf "${staging_app}" "${backup_app}"
ditto "${built_app}" "${staging_app}"

osascript -e 'tell application "Webcard" to quit' >/dev/null 2>&1 || true
sleep 1

if [[ -e "${destination}" ]]; then
    mv "${destination}" "${backup_app}"
fi

if ! mv "${staging_app}" "${destination}"; then
    if [[ -e "${backup_app}" ]]; then
        mv "${backup_app}" "${destination}"
    fi
    echo "Could not install Webcard at ${destination}." >&2
    exit 1
fi

rm -rf "${backup_app}"
open "${destination}"

echo "Installed and opened ${destination}"
