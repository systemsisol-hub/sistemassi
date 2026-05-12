#!/bin/bash
set -e

if [ ! -f "flutter/bin/flutter" ]; then
  rm -rf flutter
  git clone https://github.com/flutter/flutter.git -b stable
fi

./flutter/bin/flutter build web --release --dart-define=SB_URL=$SB_URL --dart-define=SB_TOKEN=$SB_TOKEN
