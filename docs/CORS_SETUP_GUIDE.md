# 🌐 CORS Beállítása Firebase Storage-hoz

Ha a képek feltöltése sikeres, de **piros felkiáltójel** jelenik meg helyettük (főleg mobilon vagy preview URL-en), az **CORS (Cross-Origin Resource Sharing) hiba**.

A Firebase Storage alapértelmezetten blokkolja a képek letöltését más domainekről (mint a preview URL-ek). Ezt egyszer be kell állítani.

## 🛠️ Megoldás (2 perc)

Mivel a `gsutil` parancssori eszköz szükséges hozzá, a legegyszerűbb a **Google Cloud Console** beépített terminálját használni.

### 1. Nyisd meg a Google Cloud Shell-t
1. Kattints ide: [Google Cloud Shell megnyitása](https://console.cloud.google.com/home/dashboard?cloudshell=true)
2. Válaszd ki a projektedet (`orlomed-f8f9f` vagy `lomedu-user-web`).
3. A lap alján megnyílik egy terminál ablak.

### 2. Hozd létre a konfigurációs fájlt
Másold be ezt a parancsot a terminálba és nyomj Entert:
```bash
echo '[{"origin": ["*"],"method": ["GET", "HEAD", "PUT", "POST", "DELETE", "OPTIONS"],"responseHeader": ["*"],"maxAgeSeconds": 3600}]' > cors.json
```

### 3. Alkalmazd a beállítást
Futtasd ezt a parancsot (cseréld le a `BUCKET_NEVE`-t a te tárolód nevére!):
```bash
gsutil cors set cors.json gs://orlomed-f8f9f.appspot.com
```
*(Megjegyzés: A bucket neve általában `projekt-id.appspot.com`. Megtalálod a Firebase Console Storage menüjében.)*

Ha a parancs sikeresen lefutott (nem ír ki hibát), akkor a CORS beállítása kész! ✅
Frissítsd az oldalt (mobilon is), és a képeknek meg kell jelenniük.

---

## ⚠️ Miért kell ez?
A `cors.json`-ban a `"origin": ["*"]` azt jelenti, hogy **bármelyik weboldal** (beleértve a preview URL-eket és a mobil böngészőket) letöltheti a képeket. Fejlesztéshez és preview teszteléshez ez a szükséges beállítás.

