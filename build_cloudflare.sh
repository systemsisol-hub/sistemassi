#!/bin/bash
set -e

FLUTTER_VERSION="3.29.3"
FLUTTER_DIR="$HOME/flutter"

if [ ! -d "$FLUTTER_DIR" ]; then
  echo "Installing Flutter $FLUTTER_VERSION..."
  curl -sL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" -o flutter.tar.xz
  tar xf flutter.tar.xz -C "$HOME"
  rm flutter.tar.xz
fi

export PATH="$FLUTTER_DIR/bin:$PATH"

flutter config --no-analytics
flutter precache --web

flutter build web --release \
  --dart-define=SB_URL="$SB_URL" \
  --dart-define=SB_TOKEN="$SB_TOKEN"
