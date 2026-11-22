#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v flutter >/dev/null 2>&1; then
  flutter_bin="$(command -v flutter)"
else
  sdk_root="${FLUTTER_ROOT:-${TMPDIR:-/tmp}/flutter-sdk}"
  if [[ ! -x "$sdk_root/bin/flutter" ]]; then
    release_json="$(curl --fail --silent --show-error https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json)"
    archive="$(python3 -c 'import json,sys; data=json.load(sys.stdin); stable=data["current_release"]["stable"]; print(next(r["archive"] for r in data["releases"] if r["hash"] == stable and r["channel"] == "stable"))' <<< "$release_json")"
    mkdir -p "$(dirname "$sdk_root")"
    curl --fail --location --silent --show-error "https://storage.googleapis.com/flutter_infra_release/releases/$archive" | tar -xz -C "$(dirname "$sdk_root")"
    # Flutter archives extract to a directory named `flutter`.
    if [[ "$sdk_root" != "$(dirname "$sdk_root")/flutter" ]]; then
      mv "$(dirname "$sdk_root")/flutter" "$sdk_root"
    fi
  fi
  flutter_bin="$sdk_root/bin/flutter"
fi

cd "$repo_root/due_it"
"$flutter_bin" config --enable-web
"$flutter_bin" pub get

build_args=(build web --release --base-href /)
if [[ -n "${FIREBASE_VAPID_KEY:-}" ]]; then
  build_args+=(--dart-define="FIREBASE_VAPID_KEY=$FIREBASE_VAPID_KEY")
fi
"$flutter_bin" "${build_args[@]}"
