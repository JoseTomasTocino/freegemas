#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_dir="${1:-"$repo_root/build-wasm"}"

if ! command -v emcmake >/dev/null 2>&1; then
    if [[ -n "${EMSDK:-}" && -f "${EMSDK}/emsdk_env.sh" ]]; then
        # shellcheck disable=SC1091
        source "${EMSDK}/emsdk_env.sh"
    else
        echo "emcmake not found. Install/activate emsdk and set EMSDK." >&2
        exit 1
    fi
fi

generator=()
if command -v ninja >/dev/null 2>&1; then
    generator=(-G Ninja)
fi

mkdir -p "$build_dir"
cd "$repo_root"
emcmake cmake -S "$repo_root" -B "$build_dir" "${generator[@]}" -DCMAKE_BUILD_TYPE=Release
cmake --build "$build_dir" --parallel

echo
echo "Built: $build_dir/freegemas.html"
echo "Serve it over HTTP, for example:"
echo "  python3 -m http.server 8000 --directory '$build_dir'"
echo "Then open http://127.0.0.1:8000/freegemas.html"
