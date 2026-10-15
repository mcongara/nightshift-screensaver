#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

language=tr
[[ ! -f build/language.txt ]] || language=$(cat build/language.txt)
message() {
    if [[ "$language" == en ]]; then printf '%s' "$2"; else printf '%s' "$1"; fi
}

fail() {
    printf '\n%s\n' "$1"
    exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "$(message 'Night Shift yalnızca macOS için hazırlandı.' 'Night Shift requires macOS.')"
if [[ "${1:-}" != "--uninstall" ]]; then
    if [[ "$(uname -m)" != "arm64" ]]; then
        [[ "$(/usr/sbin/sysctl -n hw.optional.arm64 2>/dev/null || true)" == "1" ]] || fail "$(message 'Bu paket Apple Silicon (M serisi) Mac gerektirir.' 'This package requires an Apple Silicon (M series) Mac.')"
    fi
    mac_version=$(/usr/bin/sw_vers -productVersion)
    [[ "${mac_version%%.*}" -ge 15 ]] || fail "$(message 'Bu paket macOS 15 veya üstünü gerektirir.' 'This package requires macOS 15 or later.')"
fi

python_runtime=''
path_python=$(command -v python3 || true)
for candidate in /opt/homebrew/bin/python3 /usr/local/bin/python3 "$path_python"; do
    # /usr/bin/python3 may be an Xcode shim. Don't trigger a tools download.
    [[ -n "$candidate" && "$candidate" != /usr/bin/python3 && -x "$candidate" ]] || continue
    if "$candidate" -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
        python_runtime="$candidate"
        break
    fi
done
if [[ -z "$python_runtime" ]] && /usr/bin/xcode-select -p >/dev/null 2>&1; then
    if /usr/bin/python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 9) else 1)' 2>/dev/null; then
        python_runtime=/usr/bin/python3
    fi
fi
[[ -n "$python_runtime" ]] || fail "$(message 'Python 3.9+ bulunamadı. Python 3 kurup tekrar çalıştır. Xcode ile derleme gerekmez.' 'Python 3.9+ was not found. Install Python 3 and try again. Xcode is not required.')"

if [[ "${1:-}" == "--uninstall" ]]; then
    printf '%s\n' "$(message 'Night Shift kaldırılıyor…' 'Uninstalling Night Shift…')"
else
    printf '%s\n' "$(message 'Night Shift bu kullanıcı için kuruluyor…' 'Installing Night Shift for this user…')"
fi
"$python_runtime" scripts/install.py "$@"
printf '\n%s\n' "$(message 'Tamamlandı. Ayrıntılar için KURULUM.md dosyasına bak.' 'Done. See INSTALL.md for details.')"
