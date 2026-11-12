#!/usr/bin/env bash
set -euo pipefail

# Vercel build environment does not include Flutter by default.
# This script installs Flutter (stable) and builds the web bundle to build/web.

# Pinned to the version the app is built and tested with locally. "stable"
# moved to 3.50.0 on 2026-11-11 and the next deploy failed. Override with the
# FLUTTER_VERSION env var in Vercel when upgrading on purpose.
FLUTTER_VERSION="${FLUTTER_VERSION:-3.47.7}"
FLUTTER_DIR="${FLUTTER_DIR:-/tmp/flutter}"

if [ ! -d "$FLUTTER_DIR" ]; then
  git clone --depth 1 --branch "$FLUTTER_VERSION" https://github.com/flutter/flutter.git "$FLUTTER_DIR"
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version

flutter config --enable-web
flutter pub get

# Build for Flutter web. (Default renderer is fine; override via env if desired.)
BASE_HREF="${FLUTTER_BASE_HREF:-/}"

BUILD_ARGS=(--release --base-href "$BASE_HREF" --no-wasm-dry-run)

# Optional: pass OCR_BASE_URL at build time. If not set, web will default to the
# same-origin `/api/ocr` proxy route.
OCR_BASE_URL_VALUE="${OCR_BASE_URL:-}"
if [ -n "$OCR_BASE_URL_VALUE" ]; then
  BUILD_ARGS+=(--dart-define=OCR_BASE_URL="$OCR_BASE_URL_VALUE")
fi

# Optional: pass GEMINI_API_KEY at build time for the Surprise Me! feature.
GEMINI_API_KEY_VALUE="${GEMINI_API_KEY:-}"
if [ -n "$GEMINI_API_KEY_VALUE" ]; then
  BUILD_ARGS+=(--dart-define=GEMINI_API_KEY="$GEMINI_API_KEY_VALUE")
fi

flutter build web "${BUILD_ARGS[@]}"
