#!/usr/bin/env bash
#
# Build the native `xmlfmt` binary for this host, pinned to the oldest CPU we
# support.
#
# Why the pin: the compilers on current distribution runners default to a
# newer x86-64 ISA level (Ubuntu 26's gcc emits x86-64-v3, i.e. AVX2), so a
# binary built there executes AVX2 instructions unconditionally and dies with
# SIGILL ("非法指令", "Illegal instruction") on any pre-Haswell CPU or any VM
# that masks AVX2. Verified by running the released 0.1.9 asset under
# `qemu-x86_64 -cpu SandyBridge`: SIGILL, while the same source built with
# `-march=x86-64` runs. The launch-time CPU check cannot help here either: the
# instruction is reached before any of our code runs.
#
# Usage:
#   scripts/build-native.sh [--static] [output-path]
#
#   --static   link fully statically against musl (portable Linux binary)
#
# Environment:
#   XMLFMT_CC        compiler driver for the dynamic build (default: cc)
#   XMLFMT_MOON      moon executable (default: moon)
#
# Requires: musl-tools for --static (Debian/Ubuntu: apt-get install musl-tools).

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
static=0
out=""
for arg in "$@"; do
  case "$arg" in
    --static) static=1 ;;
    -h | --help)
      sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      printf 'error: unknown option %s\n' "$arg" >&2
      exit 2
      ;;
    *) out="$arg" ;;
  esac
done

say() { printf '%s\n' "$*"; }
die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

# --- baseline instruction set ---------------------------------------------
case "$(uname -m)" in
  x86_64 | amd64) isa="-march=x86-64 -mtune=generic" ;;
  aarch64 | arm64) isa="-march=armv8-a" ;;
  *) die "unsupported machine: $(uname -m)" ;;
esac
say "xmlfmt: baseline flags: $isa"

work="${XMLFMT_BUILD_WORKDIR:-$(mktemp -d)}"
mkdir -p "$work"
[ -n "${XMLFMT_BUILD_WORKDIR:-}" ] || trap 'rm -rf "$work"' EXIT

# --- compiler wrapper -----------------------------------------------------
# MOON_CC drives both the compile and the link step, and `moon` looks for `ar`
# next to the compiler driver.
if [ "$static" = 1 ]; then
  command -v musl-gcc >/dev/null 2>&1 ||
    die "musl-gcc not found; install musl-tools (apt-get install musl-tools)"

  # The kernel UAPI headers live in /usr/include, which is not on musl-gcc's
  # search path; <linux/types.h> also needs the multiarch <asm/...>.
  mkdir -p "$work/headers"
  ln -sfn /usr/include/linux "$work/headers/linux"
  ln -sfn /usr/include/asm-generic "$work/headers/asm-generic"
  multiarch=""
  for dir in /usr/include/*-linux-gnu; do
    [ -d "$dir" ] || continue
    if [ -d "$dir/asm" ]; then
      multiarch="$dir"
      break
    fi
  done
  [ -n "$multiarch" ] || die "no /usr/include/*-linux-gnu/asm directory found"
  ln -sfn "$multiarch/asm" "$work/headers/asm"

  # The MoonBit runtime is compiled against glibc headers and references the
  # fortify symbols; musl has no fortify, so supply them.
  musl-gcc -O2 -c "$root/scripts/fortify-shim.c" -o "$work/fortify_shim.o"
  ar rcs "$work/libmbfortify.a" "$work/fortify_shim.o"

  cat >"$work/xmlfmt-cc" <<EOF
#!/bin/sh
for arg in "\$@"; do
  if [ "\$arg" = "-c" ]; then
    exec musl-gcc -D_GNU_SOURCE -include limits.h -I"$work/headers" $isa "\$@"
  fi
done
exec musl-gcc $isa "\$@" -static -L"$work" -lmbfortify
EOF
else
  cc="${XMLFMT_CC:-cc}"
  command -v "$cc" >/dev/null 2>&1 || die "compiler not found: $cc"
  cat >"$work/xmlfmt-cc" <<EOF
#!/bin/sh
exec $cc $isa "\$@"
EOF
fi
chmod +x "$work/xmlfmt-cc"
ln -sf "$(command -v ar)" "$work/ar"

# --- build ----------------------------------------------------------------
say "xmlfmt: building (static=$static, workdir $work)"
cd "$root"
MOON_CC="$work/xmlfmt-cc" MOON_AR=ar "${XMLFMT_MOON:-moon}" build --target native --release

bin="$root/_build/native/release/build/cmd/xmlfmt/xmlfmt.exe"
[ -f "$bin" ] || die "build did not produce $bin"

if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")"
  cp "$bin" "$out"
  chmod 755 "$out"
  bin="$out"
fi

# --- verify ---------------------------------------------------------------
file "$bin" || true
if [ "$static" = 1 ]; then
  file "$bin" | grep -q "statically linked" ||
    die "$bin is not statically linked"
fi
"$bin" --version || die "$bin does not run on this machine"
say "xmlfmt: wrote $bin"
