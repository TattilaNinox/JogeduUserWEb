#!/bin/bash
# Preview deployment script Linux/Mac-re - CSAK DEPLOY, BUILD NÉLKÜL
# Feltölt egy preview channel-re, NEM írja felül az éles verziót
# Használat: ./deploy-preview-only.sh [channel-name]
# Előfeltétel: build/web mappa létezik (flutter build web --release után)

# Ne lépjünk ki azonnal hibánál, hogy lássuk a teljes hibaüzenetet
set +e

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

# Ideiglenesen létrehozunk egy firebase.json-t csak hosting-gel (functions nélkül)
echo "Creating temporary firebase.json (hosting only)..."
cp firebase.json firebase.json.backup
cat > firebase.json.tmp << 'EOF'
{
  "firestore": {
    "rules": "firestore.rules"
  },
  "storage": {
    "rules": "storage.rules"
  },
  "hosting": {
    "site": "lomedu-user-web",
    "public": "build/web",
    "ignore": [
      "firebase.json",
      "**/.*",
      "**/node_modules/**"
    ],
    "rewrites": [
      { "source": "/api/webhook/simplepay", "function": { "functionId": "simplepayWebhook", "region": "europe-west1", "pinTag": true } },
      {
        "source": "**",
        "destination": "/index.html"
      }
    ],
    "headers": [
      {
        "source": "/version.json",
        "headers": [
          { "key": "Cache-Control", "value": "no-store, no-cache, must-revalidate, max-age=0" },
          { "key": "Pragma", "value": "no-cache" },
          { "key": "Expires", "value": "0" }
        ]
      },
      {
        "source": "/index.html",
        "headers": [
          { "key": "Cache-Control", "value": "no-store, no-cache, must-revalidate, max-age=0" }
        ]
      },
      {
        "source": "/flutter_service_worker.js",
        "headers": [
          { "key": "Cache-Control", "value": "no-store, no-cache, must-revalidate, max-age=0" }
        ]
      },
      {
        "source": "/initiateWebPayment",
        "headers": [
          { "key": "Access-Control-Allow-Origin", "value": "http://localhost:59955" }
        ]
      },
      {
        "source": "**/*.@(jpg|jpeg|gif|png|svg|webp|ico)",
        "headers": [
          { "key": "Cache-Control", "value": "public, max-age=86400, immutable" }
        ]
      },
      {
        "source": "**/*.@(js|css)",
        "headers": [
          { "key": "Cache-Control", "value": "public, max-age=31536000, immutable" }
        ]
      },
      {
        "source": "**",
        "headers": [
          { "key": "Cache-Control", "value": "public, max-age=3600" }
        ]
      }
    ]
  }
}
EOF
mv firebase.json.tmp firebase.json

# Deploy csak hosting-gel
echo "Deploying hosting only (functions skipped)..."
DEPLOY_OUTPUT=$(firebase hosting:channel:deploy "$CHANNEL_NAME" --expires 30d 2>&1)
DEPLOY_EXIT_CODE=$?

# Visszaállítjuk az eredeti firebase.json-t
echo "Restoring original firebase.json..."
mv firebase.json.backup firebase.json

# Output megjelenítése
echo "$DEPLOY_OUTPUT"

if [ $DEPLOY_EXIT_CODE -ne 0 ]; then
    echo ""
    echo "❌ Error: Deployment failed with exit code $DEPLOY_EXIT_CODE"
    echo ""
    echo "💡 Troubleshooting tips:"
    echo "   1. Check Firebase login: firebase login"
    echo "   2. Check Firebase project: firebase use"
    echo "   3. Check build/web folder exists"
    echo "   4. Try manual deploy: firebase hosting:channel:deploy $CHANNEL_NAME --expires 30d"
    exit $DEPLOY_EXIT_CODE
fi

# Preview URL kinyerése az output-ból
# Keresünk Channel URL-t (preview channel URL)
PREVIEW_URL=$(echo "$DEPLOY_OUTPUT" | grep -i "Channel URL" | sed 's/.*Channel URL[^:]*: *//' | sed 's/\[expires.*//' | tr -d ' ')

# Ha nem találtunk Channel URL-t, próbáljuk meg a Hosting URL-t
if [ -z "$PREVIEW_URL" ]; then
    PREVIEW_URL=$(echo "$DEPLOY_OUTPUT" | grep -i "Hosting URL:" | grep -i "preview" | sed 's/.*Hosting URL: *//' | tr -d ' ')
fi

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

