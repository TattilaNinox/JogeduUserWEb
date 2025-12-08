#!/bin/bash
# Preview deployment script Linux/Mac-re
# Feltölt egy preview channel-re, NEM írja felül az éles verziót
# Használat: ./deploy-preview.sh [channel-name]

set -e  # Exit on error

echo ""
echo "========================================"
echo "  Lomedu Web App - Preview Deployment"
echo "  (Nem írja felül az éles verziót!)"
echo "========================================"
echo ""

# Channel név beállítása
CHANNEL_NAME=${1:-preview}

# Verzió frissítés
echo "[1/4] Updating version.json..."
dart tools/update_version.dart
echo "✅ Version updated successfully"
echo ""

# Build
echo "[2/4] Building web app..."
flutter build web --release
echo "✅ Build completed successfully"
echo ""

# Version.json ellenőrzés
echo "[3/4] Verifying version.json in build..."
if [ -f "build/web/version.json" ]; then
    echo "✅ version.json found in build/web"
else
    echo "⚠️  Warning: version.json not found, copying..."
    cp web/version.json build/web/version.json
fi
echo ""

# Firebase deploy to preview channel
echo "[4/4] Deploying to Firebase Hosting Preview Channel: $CHANNEL_NAME..."
echo "⚠️  NOTE: This will NOT overwrite the production version!"
echo ""
firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 30d
echo ""
echo "========================================"
echo "  ✅ Preview deployment completed!"
echo "  The production version was NOT changed."
echo "========================================"
echo ""



















