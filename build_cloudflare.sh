#!/bin/bash
set -e

git clone https://github.com/flutter/flutter.git -b stable
./flutter/bin/flutter build web --release --dart-define=SB_URL=$SB_URL --dart-define=SB_TOKEN=$SB_TOKEN
