#!/bin/bash
set -e

# Install Flutter SDK
git clone https://github.com/flutter/flutter.git --depth 1 -b stable /tmp/flutter
export PATH="$PATH:/tmp/flutter/bin"

# Required asset (not committed to repo)
touch .env

# Install dependencies and build
flutter pub get
flutter build web \
  --dart-define=SB_URL=$SB_URL \
  --dart-define=SB_TOKEN=$SB_TOKEN

# SPA routing: serve index.html for unknown routes
cp build/web/index.html build/web/404.html
