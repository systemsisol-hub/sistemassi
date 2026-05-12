#!/bin/bash
set -e

FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Fetching latest stable Flutter version..."
  FLUTTER_VERSION=$(curl -sL https://storage.googleapis.com/flutter_infra_release/releases/releases_linux.json | python3 -c "import sys,json; data=json.load(sys.stdin); print(next(r['version'] for r in data['releases'] if r['channel']=='stable'))")
  echo "Installing Flutter $FLUTTER_VERSION..."
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
  tar xf flutter.tar.xz -C "$HOME"
  rm flutter.tar.xz
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter --version
flutter config --no-analytics
flutter precache --web

flutter build web --release \
  --dart-define=SB_URL="$SB_URL" \
  --dart-define=SB_TOKEN="$SB_TOKEN"
