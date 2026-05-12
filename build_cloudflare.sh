#!/bin/bash
set -e

if [ ! -d "flutter" ]; then
  git clone https://github.com/flutter/flutter.git -b stable
fi

./flutter/bin/flutter build web --release --dart-define=SB_URL=$SB_URL --dart-define=SB_TOKEN=$SB_TOKEN
