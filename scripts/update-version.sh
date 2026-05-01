#!/usr/bin/env bash
# Script to update CLIProxyAPI edition version and compute new hashes
set -euo pipefail

EDITION="${1:-}"
NEW_VERSION="${2:-}"

# Edition metadata (must match flake.nix editions attrset)
declare -A REPOS=(
    ["cliproxyapi"]="router-for-me/CLIProxyAPI"
    ["cliproxyapi-plus"]="router-for-me/CLIProxyAPIPlus"
    ["cliproxyapi-business"]="router-for-me/CLIProxyAPIBusiness"
)

declare -A ARCHIVE_PREFIXES=(
    ["cliproxyapi"]="CLIProxyAPI"
    ["cliproxyapi-plus"]="CLIProxyAPIPlus"
    ["cliproxyapi-business"]="cpab"
)

# Usage help
if [ -z "$EDITION" ] || [ -z "$NEW_VERSION" ]; then
    echo "Usage: $0 <edition> <version>"
    echo ""
    echo "Editions:"
    echo "  cliproxyapi          - Base CLIProxyAPI"
    echo "  cliproxyapi-plus     - CLIProxyAPI Plus edition"
    echo "  cliproxyapi-business - CLIProxyAPI Business edition"
    echo ""
    echo "Example: $0 cliproxyapi-plus 6.6.68-0"
    exit 1
fi

# Validate edition
if [[ ! -v "REPOS[$EDITION]" ]]; then
    echo "Error: Unknown edition '$EDITION'"
    echo "Valid editions: ${!REPOS[*]}"
    exit 1
fi

REPO="${REPOS[$EDITION]}"
ARCHIVE_PREFIX="${ARCHIVE_PREFIXES[$EDITION]}"

echo "Updating $EDITION to version: $NEW_VERSION"

SYSTEMS=(
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
)

asset_candidates() {
    case "$1" in
        x86_64-linux)
            printf '%s\n' "linux_amd64"
            ;;
        aarch64-linux)
            printf '%s\n' "linux_arm64" "linux_aarch64"
            ;;
        x86_64-darwin)
            printf '%s\n' "darwin_amd64"
            ;;
        aarch64-darwin)
            printf '%s\n' "darwin_arm64" "darwin_aarch64"
            ;;
        *)
            echo "Error: unsupported Nix system '$1'" >&2
            return 1
            ;;
    esac
}

# Compute hashes for each platform
declare -A HASHES
declare -A ASSETS

for nixSystem in "${SYSTEMS[@]}"; do
    hash=""
    rawHash=""
    asset=""

    for candidate in $(asset_candidates "$nixSystem"); do
        url="https://github.com/${REPO}/releases/download/v${NEW_VERSION}/${ARCHIVE_PREFIX}_${NEW_VERSION}_${candidate}.tar.gz"

        echo "Fetching hash for $nixSystem ($candidate)..."

        if rawHash=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null); then
            hash=$(nix hash convert --hash-algo sha256 --to sri "$rawHash" 2>/dev/null || nix hash to-sri --type sha256 "$rawHash" 2>/dev/null)
            asset="$candidate"
            break
        fi
    done

    if [ -z "$hash" ]; then
        echo "Error: Failed to fetch hash for $nixSystem"
        echo "Tried asset suffixes:"
        asset_candidates "$nixSystem" | sed 's/^/  - /'
        exit 1
    fi

    HASHES["$nixSystem"]="$hash"
    ASSETS["$nixSystem"]="$asset"
    echo "  $nixSystem ($asset): $hash"
done

echo ""
echo "Updating flake.nix..."

# Update version within the specific edition block using multiline perl
# The /s modifier allows . to match newlines
# Use environment variables to avoid shell escaping issues with version strings
export EDITION NEW_VERSION
perl -i -0pe 's/($ENV{EDITION} = \{[^}]*?)version = "[^"]*"/$1version = "$ENV{NEW_VERSION}"/s' flake.nix

# Update each asset suffix within the specific edition block. Upstream has used
# both arm64 and aarch64 naming for ARM releases.
for nixSystem in "${SYSTEMS[@]}"; do
    asset="${ASSETS[$nixSystem]}"
    export nixSystem asset
    perl -i -0pe 's/($ENV{EDITION} = \{.*?assetSuffixes = \{.*?)"$ENV{nixSystem}" = "[^"]+";/$1"$ENV{nixSystem}" = "$ENV{asset}";/s' flake.nix
done

# Update each hash within the specific edition block
# Match both quoted strings ("sha256-...") and Nix expressions (nixpkgs.lib.fakeHash)
for nixSystem in "${SYSTEMS[@]}"; do
    hash="${HASHES[$nixSystem]}"
    export nixSystem hash
    perl -i -0pe 's/($ENV{EDITION} = \{.*?hashes = \{.*?)"$ENV{nixSystem}" = [^;]+;/$1"$ENV{nixSystem}" = "$ENV{hash}";/s' flake.nix
done

echo "Done! Updated flake.nix $EDITION to version $NEW_VERSION"
echo ""
echo "Changes for $EDITION:"
grep -A 10 "${EDITION} = {" flake.nix | head -11
