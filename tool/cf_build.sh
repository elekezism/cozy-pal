#!/usr/bin/env bash
# Cloudflare Pages build for the web version of Cozy Pal.
#   Build command:          bash tool/cf_build.sh
#   Build output directory: build/web
# Installs Flutter (stable) into the build machine, adds the web platform
# files, and builds. Pages Functions in functions/ are deployed alongside.
set -euo pipefail

FLUTTER_CHANNEL="${FLUTTER_CHANNEL:-stable}"
if ! command -v flutter >/dev/null 2>&1; then
  if [ ! -x "$HOME/flutter/bin/flutter" ]; then
    git clone --depth 1 --branch "$FLUTTER_CHANNEL" https://github.com/flutter/flutter.git "$HOME/flutter"
  fi
  export PATH="$HOME/flutter/bin:$PATH"
fi
export FLUTTER_SUPPRESS_ANALYTICS=true
flutter config --no-analytics --enable-web >/dev/null
flutter --version

# web/ only holds our extra files (oauth.html, _headers); let Flutter add the rest
flutter create --org com.cozypal --project-name cozy_pal --platforms web . >/dev/null
# friendlier page title + colors
sed -i 's|<title>.*</title>|<title>Cozy Pal</title>|' web/index.html
sed -i 's|content="A new Flutter project."|content="A cozy pet that helps you: notes, mail, answers, and cheering you up."|' web/index.html || true
if [ -f web/manifest.json ]; then
  sed -i 's/"name": "cozy_pal"/"name": "Cozy Pal"/; s/"short_name": "cozy_pal"/"short_name": "Cozy Pal"/; s/"background_color": "#[0-9A-Fa-f]*"/"background_color": "#BDE8F1"/; s/"theme_color": "#[0-9A-Fa-f]*"/"theme_color": "#BDE8F1"/' web/manifest.json
fi

flutter pub get
flutter build web --release
# copy our extra web files (flutter build copies web/*, but make sure)
cp web/oauth.html web/_headers build/web/ 2>/dev/null || true
echo "Built $(du -sh build/web | cut -f1) into build/web"
