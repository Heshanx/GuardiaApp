#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .firebase-tools
if [ ! -x .firebase-tools/firebase ]; then
  echo "Downloading the official standalone Firebase CLI (Node.js is not required)…"
  curl --fail --location --retry 2 'https://firebase.tools/bin/macos/latest' -o .firebase-tools/firebase.download
  chmod +x .firebase-tools/firebase.download
  mv .firebase-tools/firebase.download .firebase-tools/firebase
fi
echo "Sign in with the Google account that owns guardia-a63bd."
.firebase-tools/firebase login
echo "Publishing Guardia's live-sharing rules and tracker page to guardia-a63bd…"
.firebase-tools/firebase deploy --only firestore:rules,hosting --project guardia-a63bd
echo "Tracker page: https://guardia-a63bd.web.app/track.html"
echo "Return to Guardia, start/resume a trip and enable live sharing."
read -r -p "Press Return to close. "
