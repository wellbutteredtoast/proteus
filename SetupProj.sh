#!/usr/bin/env sh
#
# Proteus Setup shell script
# Using (sh) for maximal compatability
# SPDX-License-Identifier: MPL-2.0

set -eu

info() {
    printf '[?] :: %s\n' "$*"
}

ok() {
    printf '[*] :: %s\n' "$*"
}

err() {
    printf '[X] :: %s\n' "$*"
}

sleep 1
ok "========== Proteus Engine Setup =========="
info "Preparing to set up the project..."

if [ -f ".psetupdone" ] || [ -f ".pbuilddone" ]; then
    ok "Setup has already been done before, to redo setup, do the following:"
    ok " rm -rf Build"
    ok " rm -rf Dependencies"
    ok " rm -f .psetupdone"
    ok "And rerun the setup script."
    exit 0
fi

## Step 0: Prepare directories
if [ ! -d "$PWD/Dependencies" ]; then
    if mkdir "$PWD/Dependencies" >/dev/null 2>&1; then
        ok "Created dependencies dir successfully."
    else
        err "Could not create the directory, maybe there is a permissions issue?"
        err "(Try running this script as a superuser [sudo])"
        exit 1
    fi
else
    info "Dependencies dir already exists, skipping."
fi
if [ ! -d "$PWD/Build" ]; then
    if mkdir "$PWD/Build" >/dev/null 2>&1; then
        ok "Created build dir successfully."
    else
        err "Could not create the directory, maybe there is a permissions issue?"
        err "(Try running this script as a superuser [sudo])"
        exit 1
    fi
else
    info "Build dir already exists, skipping."
fi

## Step 1: Check for all required tooling
sleep 1
info "Checking now for required tools..."

# This magic function can pull ver numbers out of most apps' --version flags
get_version() {
    $1 2>&1 | head -n1 | grep -Eo '[0-9]+\.[0-9]+(\.[0-9]+)?([.-][0-9A-Za-z]+)*' | head -n1
}

normalize_arch() {
    case "$1" in
        x86_64|amd64)  echo "x86_64" ;;
        arm64|aarch64) echo "arm64"  ;;
        i386|i686)     echo "i386"   ;;
        *)             echo "$1"     ;;
    esac
}
 
# Checks that clang++'s default target triple matches the actual host arch
check_target_arch() {
    host_arch=$(uname -m)
    # Weird macOS hack since sometimes this can just be mis-reported
    # Also we're not targeting Intel Macs, sorry!
    if [ "$(uname -s)" = "Darwin" ]; then
        if sysctl -n hw.optional.arm64 2>/dev/null | grep -q '^1$'; then
            host_arch="arm64"
        fi
    fi
 
    compiler_triple=$(clang++ -dumpmachine 2>/dev/null) || {
        err "Could not determine clang++'s default target triple."
        return 1
    }
    compiler_arch=$(echo "$compiler_triple" | cut -d- -f1)
 
    host_norm=$(normalize_arch "$host_arch")
    compiler_norm=$(normalize_arch "$compiler_arch")
 
    if [ "$host_norm" != "$compiler_norm" ]; then
        err "Arch mismatch: host is $host_arch, but clang++ defaults to $compiler_triple"
        err "Building without explicit -arch/-target flags will produce wrong-arch object files."
        return 1
    fi
 
    ok "clang++ default target ($compiler_triple) matches host ($host_arch)."
}
 
for dep in git curl make lldb gdb clang++; do
    if ! command -v "$dep" >/dev/null 2>&1; then
        err "Missing dependency $dep !"
        continue
    fi
    case "$dep" in
        make)
            info 'Make version:  '  "$(get_version "make --version")"
            ;;
        git)
            info 'Git  version:  '  "$(get_version "git --version")"
            ;;
        curl)
            info 'Curl version:  '  "$(get_version "curl --version")"
            ;;
        lldb)
            info 'LLDB version:  '  "$(get_version "lldb --version")"
            ;;
        gdb)
            info 'GDB  version:  '  "$(get_version "gdb --version")"
            ;;
        clang++)
            info 'Clang version: '  "$(get_version "clang++ --version")"
            check_target_arch || exit 1
            ;;
    esac
done
 
# Warn the user if no debugger is present
if ! command -v lldb >/dev/null 2>&1 && ! command -v gdb >/dev/null 2>&1; then
    err "No debugger found (need lldb or gdb)."
fi

## Step 2, tooling looks good now we can worry about dependencies
##         not as many as you think since Proteus tries to stand on its
##         own in most accords, some things however are not worth doing

sleep 1
info "Tooling check complete, moving on to dependency fecthing..."

