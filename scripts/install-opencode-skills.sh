#!/usr/bin/env bash
# Install/remove OpenCode skills from this marketplace as symlinks.
# Usage: ./scripts/install-opencode-skills.sh [-n|--dry-run] [-r|--remove] [-h|--help]
# Requires: bash 4.0+
set -euo pipefail
((BASH_VERSINFO[0] >= 4)) || { echo "Requires bash 4.0+ (found $BASH_VERSION)" >&2; exit 1; }

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode/skills"
DRY=false REMOVE=false ERRORS=0

warn() { echo "Warning: $1" >&2; }
err() { echo "Error: $1" >&2; ((++ERRORS)); }
die() { err "$1"; exit 1; }

get_name() {
    local f="$1" n=""
    if command -v yq &>/dev/null; then
        n=$(yq --front-matter=extract '.name' "$f" 2>/dev/null) || true
        [[ -n "$n" && "$n" != "null" ]] && { echo "$n"; return; }
    fi
    sed -n '/^---$/,/^---$/p' "$f" | grep -m1 '^name:' | sed "s/^name:[[:space:]]*//;s/^[\"']//;s/[\"']$//"
}

build_map() {
    declare -A seen; local dups=false
    while IFS= read -r f; do
        [[ -z "$f" ]] && continue
        local name=$(get_name "$f") dir=$(dirname "$f")
        [[ -z "$name" ]] && { warn "No name in $f"; continue; }
        [[ "$name" =~ ^[a-zA-Z0-9_-]+$ ]] || { warn "Invalid name '$name' in $f"; continue; }
        [[ -n "${seen[$name]:-}" ]] && { err "Duplicate '$name': ${seen[$name]} vs $f"; dups=true; continue; }
        seen[$name]="$f"
        echo "$name:$dir"
    done < <(find "$REPO/plugins" -path "*/skills/*/SKILL.md" -type f 2>/dev/null)
    $dups && return 1 || return 0
}

install() {
    echo "Installing to: $SKILLS_DIR"; $DRY && echo "(dry-run)"
    local map; map=$(build_map) || die "Aborting: duplicate names"
    [[ -z "$map" ]] && { echo "No skills found"; return; }
    $DRY || mkdir -p "$SKILLS_DIR"
    while IFS=: read -r name dir; do
        local link="$SKILLS_DIR/$name"
        if [[ -L "$link" ]]; then
            [[ "$(readlink "$link")" == "$dir" ]] && { echo "  [ok] $name"; continue; }
            $DRY && echo "  [update] $name" || { ln -snf "$dir" "$link"; echo "  [updated] $name"; }
        elif [[ -e "$link" ]]; then
            warn "$link exists (not a symlink)"
        else
            $DRY && echo "  [install] $name" || { ln -snf "$dir" "$link"; echo "  [installed] $name"; }
        fi
    done <<< "$map"
}

remove() {
    echo "Removing from: $SKILLS_DIR"; $DRY && echo "(dry-run)"
    [[ -d "$SKILLS_DIR" ]] || { echo "No skills dir"; return; }
    local map; map=$(build_map 2>/dev/null) || true
    [[ -z "$map" ]] && { echo "No skills found"; return; }
    while IFS=: read -r name dir; do
        local link="$SKILLS_DIR/$name"
        [[ -L "$link" && "$(readlink "$link")" == "$dir" ]] || continue
        $DRY && echo "  [remove] $name" || { rm "$link"; echo "  [removed] $name"; }
    done <<< "$map"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY=true;;
        -r|--remove) REMOVE=true;;
        -h|--help) echo "Usage: $0 [-n|--dry-run] [-r|--remove] [-h|--help]"; exit 0;;
        *) die "Unknown: $1";;
    esac; shift
done

$REMOVE && remove || install
((ERRORS)) && exit 1 || exit 0
