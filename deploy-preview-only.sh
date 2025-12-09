#!/bin/bash
# Preview deployment script Linux/Mac-re - CSAK DEPLOY, BUILD NÉLKÜL
# Feltölt egy preview channel-re, NEM írja felül az éles verziót
# Használat: ./deploy-preview-only.sh [channel-name]
# Előfeltétel: build/web mappa létezik (flutter build web --release után)

set -e  # Exit on error

echo ""
echo "========================================"
echo "  Lomedu Web App - Preview Deploy Only"
echo "  (Nem buildel, csak deployol!)"
echo "  (Nem írja felül az éles verziót!)"
echo "========================================"
echo ""

# Channel név beállítása
CHANNEL_NAME=${1:-preview}

# Build mappa ellenőrzése
if [ ! -d "build/web" ]; then
    echo "❌ Error: build/web mappa nem található!"
    echo "   Először futtasd: flutter build web --release"
    exit 1
fi

# Version.json ellenőrzés
echo "[1/2] Verifying version.json in build..."
if [ -f "build/web/version.json" ]; then
    echo "✅ version.json found in build/web"
else
    echo "⚠️  Warning: version.json not found, copying..."
    if [ -f "web/version.json" ]; then
        cp web/version.json build/web/version.json
        echo "✅ version.json copied"
    else
        echo "❌ Error: version.json not found in web/ folder either!"
        exit 1
    fi
fi
echo ""

# Firebase deploy to preview channel
echo "[2/2] Deploying to Firebase Hosting Preview Channel: $CHANNEL_NAME..."
echo "⚠️  NOTE: This will NOT overwrite the production version!"
echo ""

# Deploy és output mentése
DEPLOY_OUTPUT=$(firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 30d 2>&1)
DEPLOY_EXIT_CODE=$?

# Output megjelenítése
echo "$DEPLOY_OUTPUT"

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ Error: Deployment failed"
    exit $DEPLOY_EXIT_CODE
fi

# Preview URL kinyerése az output-ból
PREVIEW_URL=$(echo "$DEPLOY_OUTPUT" | grep -i "Hosting URL:" | sed 's/.*Hosting URL: *//' | tr -d ' ')

echo ""
echo "========================================"
echo "  ✅ Preview deployment completed!"
echo "  The production version was NOT changed."
echo "========================================"
echo ""

if [ -n "$PREVIEW_URL" ]; then
    echo "🔗 Preview URL:"
    echo "$PREVIEW_URL"
    echo ""
    echo "📋 Copy this URL and share it with testers."
    echo "⏰ This preview will expire in 30 days."
else
    echo "⚠️  Preview URL not found in output."
    echo "   Check Firebase Console for the preview URL."
fi

echo "========================================"
echo ""

