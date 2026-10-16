#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LINUX_OUT="Linux_Tamriel_Trade_Center.sh"
MACOS_OUT="macOS_Tamriel_Trade_Center.sh"
WINDOWS_OUT="Windows_Tamriel_Trade_Center.bat"

bundle() {
    perl -e '
        my ($main, $src) = @ARGV;
        open(my $fh, "<", $main) or die "build: cannot read $main\n";
        local $/; my $text = <$fh>;
        for my $line (split /(?<=\n)/, $text) {
            if ($line =~ /^[ \t]*(?:source|\.) "\$LTTC_SRC[\/\\]([^"]+)"[ \t]*\r?\n?$/) {
                (my $rel = $1) =~ s{\\}{/}g;
                open(my $inc, "<", "$src/$rel") or die "build: $main sources $rel, which does not exist\n";
                print <$inc>;
            } elsif ($line !~ /#src-only/) {
                print $line;
            }
        }' "$1" "$2"
}

build_to() {
    local dest="$1"
    mkdir -p "$dest"
    bundle "$ROOT/src/linux/main.sh" "$ROOT/src/linux" > "$dest/$LINUX_OUT"
    bundle "$ROOT/src/macos/main.sh" "$ROOT/src/macos" > "$dest/$MACOS_OUT"
    { cat "$ROOT/src/windows/launcher.bat"; bundle "$ROOT/src/windows/main.ps1" "$ROOT/src/windows"; } \
        | perl -pe 's/\r?\n/\r\n/' > "$dest/$WINDOWS_OUT"
    chmod +x "$dest/$LINUX_OUT" "$dest/$MACOS_OUT"
    for f in "$LINUX_OUT" "$MACOS_OUT"; do
        if ! bash -n "$dest/$f"; then
            echo "build: $f has a syntax error" >&2
            return 1
        fi
    done
}

check_version() {
    local want got f
    want="$(tr -d ' \r\n' < "$ROOT/VERSION" 2>/dev/null || true)"
    [ -z "$want" ] && return 0
    for f in "$1/$LINUX_OUT" "$1/$MACOS_OUT" "$1/$WINDOWS_OUT"; do
        got="$(grep -m1 -oE 'APP_VERSION ?= ?"[^"]+"' "$f" | grep -oE '"[^"]+"' | tr -d '"')"
        if [ "$got" != "$want" ]; then
            echo "build: $(basename "$f") says version $got, VERSION says $want" >&2
            return 1
        fi
    done
}

if [ "${1:-}" = "--check" ]; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    build_to "$tmp"
    check_version "$tmp"
    stale=0
    for f in "$LINUX_OUT" "$MACOS_OUT" "$WINDOWS_OUT"; do
        if ! cmp -s "$tmp/$f" "$ROOT/dist/$f"; then
            echo "build: dist/$f is out of date, run make build" >&2
            stale=1
        fi
    done
    [ "$stale" -eq 0 ] && echo "build: dist/ matches src/"
    exit "$stale"
fi

build_to "$ROOT/dist"
check_version "$ROOT/dist"
echo "build: wrote dist/$LINUX_OUT, dist/$MACOS_OUT and dist/$WINDOWS_OUT"
