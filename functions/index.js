const { onCall, onRequest, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { onDocumentWritten } = require('firebase-functions/v2/firestore');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const nodemailer = require('nodemailer');
const crypto = require('crypto');
const { buildTemplate, logoAttachment } = require('./emailTemplates');
const szamlaAgent = require('./szamlaAgent');
const szamlaAgentTest = require('./szamlaAgentTest');
const invoiceBuilder = require('./invoiceBuilder');

// Konfigur├íci├│ forr├ísa: 1) Firebase Functions config (firebase functions:config:set smtp.*),
// 2) k├Ârnyezeti v├íltoz├│k, 3) ha emul├ítor fut, pr├│b├íljon meg helyi SMTP-t (opcion├ílis).

admin.initializeApp();

// Glob├ílis be├íll├şt├ísok ÔÇô r├ęgi├│, er┼Ĺforr├ísok
setGlobalOptions({ region: 'europe-west1', cpu: 1 });

const db = admin.firestore();

// Helper to mask sensitive values in logs
function maskValue(value) {
  try {
    if (!value || typeof value !== 'string') return 'N/A';
    const tail = value.slice(-4);
    return `***${tail}`;
  } catch (_) {
    return 'N/A';
  }
}

// SimplePay konfigur├íci├│
// Sandbox/Production kiv├ílaszt├ísa k├╝l├Ân titok alapj├ín (alap├ęrtelmez├ęs: sandbox)
const SIMPLEPAY_ENV = (process.env.SIMPLEPAY_ENV || 'sandbox').toLowerCase();

// Runtime config reader (secrets biztosan el├ęrhet┼Ĺk invok├íci├│kor)
function getSimplePayConfig() {
  const env = (process.env.SIMPLEPAY_ENV || 'sandbox').toLowerCase().trim();
  return {
    merchantId: (process.env.SIMPLEPAY_MERCHANT_ID || '').trim(),
    secretKey: (process.env.SIMPLEPAY_SECRET_KEY || '').trim(),
    baseUrl: env === 'production'
      ? 'https://secure.simplepay.hu/payment/v2/'
      : 'https://sandbox.simplepay.hu/payment/v2/',
    nextAuthUrl: (process.env.NEXTAUTH_URL || 'https://lomedu-user-web.web.app').trim(),
    allowedReturnBases: (process.env.RETURN_BASES || process.env.NEXTAUTH_URL || 'https://lomedu-user-web.web.app')
      .split(',')
      .map(s => s.trim())
      .filter(Boolean),
    env,
  };
}

// Biztons├íg kedv├ę├ęrt defini├ílunk egy glob├ílis, hogy r├ęgi rev├şzi├│k/async hivatkoz├ísok se dobjanak ReferenceError-t
const SIMPLEPAY_CONFIG = getSimplePayConfig();

// SimplePay hibak├│dok emberi nyelv┼▒ magyar├ízatai
const SIMPLEPAY_ERROR_MESSAGES = {
  '5321': 'Al├í├şr├ísi hiba: A SimplePay nem tudta ellen┼Ĺrizni a k├ęr├ęs al├í├şr├ís├ít. Ellen┼Ĺrizze a SECRET_KEY be├íll├şt├ís├ít.',
  '5001': 'Hi├ínyz├│ merchant azonos├şt├│',
  '5002': '├ërv├ęnytelen merchant azonos├şt├│',
  '5003': 'Merchant nincs aktiv├ílva',
  '5004': 'Merchant felf├╝ggesztve',
  '5101': 'Hi├ínyz├│ vagy ├ęrv├ęnytelen orderRef',
  '5102': 'Duplik├ílt orderRef - ez a megrendel├ęs m├ír l├ętezik',
  '5201': '├ërv├ęnytelen ├Âsszeg - negat├şv vagy nulla',
  '5202': '├ërv├ęnytelen p├ęnznem',
  '5301': 'Hi├ínyz├│ vagy ├ęrv├ęnytelen customer email',
  '5302': 'Hi├ínyz├│ customer n├ęv',
  '5401': '├ërv├ęnytelen timeout form├ítum',
  '5402': 'Timeout t├║l r├Âvid vagy t├║l hossz├║',
  '5501': 'Hi├ínyz├│ vagy ├ęrv├ęnytelen visszair├íny├şt├ísi URL',
  '5601': '├ërv├ęnytelen fizet├ęsi m├│dszer',
  '5701': 'Hi├ínyz├│ term├ęk t├ętel',
  '5702': '├ërv├ęnytelen term├ęk adatok',
  '5801': 'Tranzakci├│ nem tal├ílhat├│',
  '5802': 'Tranzakci├│ m├ír feldolgozva',
  '5803': 'Tranzakci├│ lej├írt',
  '5804': 'Tranzakci├│ visszavonva',
  '9999': '├ültal├ínos szerverhiba - pr├│b├ílja ├║jra k├ęs┼Ĺbb',
};

// SimplePay hibak├│d feldolgoz├ísa
function getSimplePayErrorMessage(errorCodes) {
  if (!errorCodes || !Array.isArray(errorCodes) || errorCodes.length === 0) {
    return 'Ismeretlen hiba t├Ârt├ęnt a fizet├ęs sor├ín';
  }

  const messages = errorCodes.map(code => {
    const msg = SIMPLEPAY_ERROR_MESSAGES[code.toString()];
    return msg ? `${code}: ${msg}` : `${code}: Ismeretlen hibak├│d`;
  });

  return messages.join('; ');
}

// Kiseg├şt┼Ĺ k├ęsleltet├ęs
function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

const NEXTAUTH_URL = process.env.NEXTAUTH_URL || 'https://lomedu-user-web.web.app';

// Fizetési csomagok
const PAYMENT_PLANS = {
  // Kanonikus azonosító
  monthly_premium_prepaid: {
    name: '30 napos előfizetés',
    price: 4350,
    description: 'Teljes hozzáférés minden funkcióhoz',
    subscriptionDays: 30,
  },
  // Régi alias a visszafelé kompatibilitásért
  monthly_web: {
    name: '30 napos előfizetés',
    price: 4350,
    description: 'Teljes hozzáférés minden funkcióhoz',
    subscriptionDays: 30,
  },
};

// Plan ID kanonikus├şt├ísa (alias Ôćĺ kanonikus)
const CANONICAL_PLAN_ID = {
  monthly_web: 'monthly_premium_prepaid',
  monthly_premium_prepaid: 'monthly_premium_prepaid',
};

// SMTP transport - STARTTLS m├│dszerrel
const transport = nodemailer.createTransport({
  host: 'mail.lomedu.hu',
  port: 587,
  secure: false, // STARTTLS
  requireTLS: true,
  auth: {
    user: 'info@lomedu.hu',
    pass: 'SoliDeoGloria55!!',
  },
});
const auth = admin.auth();

exports.requestDeviceChange = onCall(async (request) => {
  const data = request.data || {};
  const email = (data.email || '').toString().trim().toLowerCase();
  if (!email) {
    throw new Error('invalid-argument: Email sz├╝ks├ęges');
  }

  const code = Math.floor(100000 + Math.random() * 900000).toString();
  const expiresAt = Date.now() + 15 * 60 * 1000; // 15 perc

  const snap = await db.collection('users').where('email', '==', email).limit(1).get();
  if (snap.empty) {
    throw new Error('not-found: Nem tal├ílhat├│ felhaszn├íl├│ ezzel az email c├şmmel.');
  }

  const userDoc = snap.docs[0];
  await userDoc.ref.set({
    deviceChange: {
      code,
      expiresAt,
      requestedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
  }, { merge: true });

  // E-mail k├╝ld├ęs
  try {
    const SIMPLEPAY_CONFIG = getSimplePayConfig();
    await transport.sendMail({
      from: 'Lomedu <info@lomedu.hu>',
      to: email,
      subject: 'Eszk├Âzv├ílt├ísi k├│d',
      text: `Az ├║j eszk├Âz j├│v├íhagy├ís├íhoz adja meg a k├Âvetkez┼Ĺ k├│dot: ${code} (15 percig ├ęrv├ęnyes)`,
      html: buildTemplate(`<p>Az ├║j eszk├Âz j├│v├íhagy├ís├íhoz adja meg a k├Âvetkez┼Ĺ k├│dot:</p><h2 style="text-align:center;font-size:32px;margin:24px 0;color:#0d6efd;">${code}</h2><p>A k├│d 15 percig ├ęrv├ęnyes.</p>`),
      attachments: [logoAttachment()],
    });
    console.log('Device change email sent to', email);
  } catch (mailErr) {
    console.error('Email sending failed:', mailErr);
  }

  return { ok: true };
});

exports.verifyAndChangeDevice = onCall(async (request) => {
  const data = request.data || {};
  const email = (data.email || '').toString().trim().toLowerCase();
  const code = (data.code || '').toString().trim();
  const newFingerprint = (data.fingerprint || '').toString().trim();

  if (!email || !code || !newFingerprint) {
    throw new Error('invalid-argument: Hi├ínyz├│ mez┼Ĺk');
  }

  const snap = await db.collection('users').where('email', '==', email).limit(1).get();
  if (snap.empty) {
    throw new Error('not-found: Nem tal├ílhat├│ felhaszn├íl├│ ezzel az email c├şmmel.');
  }

  const userDoc = snap.docs[0];
  const dc = userDoc.data().deviceChange || {};
  if (!dc.code || !dc.expiresAt || dc.code !== code || Date.now() > Number(dc.expiresAt)) {
    throw new Error('failed-precondition: ├ërv├ęnytelen vagy lej├írt k├│d');
  }

  try {
    // A Firebase Auth UID-t haszn├íljuk a dokumentum ID-k├ęnt
    const userData = userDoc.data();
    const firebaseAuthUid = userData.firebaseAuthUid || userDoc.id;

    console.log(`Found user with email ${email}, Firestore ID: ${userDoc.id}, Firebase Auth UID: ${firebaseAuthUid}`);

    // Email c├şm valid├íl├ísa - ha a 6 jegy┼▒ k├│d helyes, az email is hiteles├ştett
    await admin.auth().updateUser(firebaseAuthUid, { emailVerified: true });
    console.log(`Email verified for user ${firebaseAuthUid}`);

    // A Firebase Auth UID-val friss├ştj├╝k a dokumentumot
    const targetDoc = db.collection('users').doc(firebaseAuthUid);

    // El┼Ĺsz├Âr friss├ştj├╝k a fingerprint-et
    await targetDoc.set({
      authorizedDeviceFingerprint: newFingerprint,
      deviceChangeDate: admin.firestore.FieldValue.serverTimestamp(),
      deviceChange: admin.firestore.FieldValue.delete(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    }, { merge: true });

    console.log(`Device changed for user ${firebaseAuthUid}, new fingerprint: ${newFingerprint}`);

    // Majd invalid├íljuk a tokeneket - Firebase Auth user ID-t haszn├ílunk
    try {
      // A Firestore user dokumentumban keress├╝k a Firebase Auth UID-t
      const userData = userDoc.data();
      const firebaseAuthUid = userData.firebaseAuthUid || userDoc.id; // Fallback a Firestore ID-re

      console.log(`Attempting to revoke tokens for Firebase Auth UID: ${firebaseAuthUid}`);
      await admin.auth().revokeRefreshTokens(firebaseAuthUid);
      console.log(`Refresh tokens revoked for user ${firebaseAuthUid}`);
    } catch (revokeError) {
      console.error('Failed to revoke refresh tokens:', revokeError);
      // Folytatjuk, m├ęg ha a token invalid├íl├ís sikertelen is
    }

    return { ok: true };
  } catch (error) {
    console.error('Error in verifyAndChangeDevice:', error);
    throw error;
  }
});

// ============================================================
// EMAIL VERIFICATION VIA 6-DIGIT CODE (no deep links)
// ============================================================

/**
 * requestEmailVerificationCode
 * Input: { userId }
 * Behavior: generates 6-digit code, stores under users/{uid}.emailVerification,
 *           rate limits resends (60s), code expires in 15 minutes, attemptsLeft=5.
 *           Sends branded email with the code via Nodemailer.
 */
// Removed exports.requestEmailVerificationCode = onCall({ cors: true }, async (request) => {
//     // ... (lines 217-282 removed)
// });

/**
 * verifyEmailWithCode
 * Input: { userId, code }
 * Behavior: checks code, expiry, attempts; marks Auth emailVerified=true; clears code block.
 */
// Removed exports.verifyEmailWithCode = onCall({ cors: true }, async (request) => {
//    // ... (lines 290-351 removed)
// });

// ---- HTTP (onRequest) v├íltozatok, explicit CORS headerekkel ----

// ============================================================================
// WEBES FIZET├ëSI FUNKCI├ôK - OTP SIMPLEPAY v2 INTEGR├üCI├ô
// ============================================================================

/**
 * Webes fizet├ęs ind├şt├ísa SimplePay v2 API-val
 */
exports.initiateWebPayment = onCall({
  secrets: ['SIMPLEPAY_MERCHANT_ID', 'SIMPLEPAY_SECRET_KEY', 'NEXTAUTH_URL', 'SIMPLEPAY_ENV']
}, async (request) => {
  try {
    const { planId, userId } = request.data || {};
    console.log('[initiateWebPayment] input', { planId, userId });

    if (!planId || !userId) {
      throw new HttpsError('invalid-argument', 'planId ├ęs userId sz├╝ks├ęges');
    }

    const canonicalPlanId = CANONICAL_PLAN_ID[planId] || planId;
    const plan = PAYMENT_PLANS[canonicalPlanId];
    if (!plan) {
      throw new HttpsError('invalid-argument', '├ërv├ęnytelen csomag');
    }

    if (!SIMPLEPAY_CONFIG.merchantId || !SIMPLEPAY_CONFIG.secretKey || !SIMPLEPAY_CONFIG.baseUrl) {
      throw new HttpsError('failed-precondition', 'SimplePay konfigur├íci├│ hi├ínyzik');
    }

    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new HttpsError('not-found', 'Felhaszn├íl├│ nem tal├ílhat├│');
    }

    const userData = userDoc.data();

    // Admin ellenőrzés - admin számára 5 forint az ár
    const isAdmin = (userData.isAdmin === true) || (userData.email === 'tattila.ninox@gmail.com');
    const finalPrice = isAdmin ? 5 : plan.price;

    console.log('[initiateWebPayment] Admin check:', {
      userId,
      isAdmin,
      originalPrice: plan.price,
      finalPrice
    });

    // SZERVER OLDALI ELLEN┼ÉRZ├ëS: Adattov├íbb├şt├ísi nyilatkozat elfogad├ísa
    if (!userData.dataTransferConsentLastAcceptedDate) {
      console.log('[initiateWebPayment] HIBA: Adattov├íbb├şt├ísi nyilatkozat nincs elfogadva', { userId });
      throw new HttpsError(
        'failed-precondition',
        'Az adattov├íbb├şt├ísi nyilatkozat elfogad├ísa sz├╝ks├ęges a fizet├ęs ind├şt├ís├íhoz. K├ęrj├╝k, fogadja el a nyilatkozatot ├ęs pr├│b├ílja ├║jra.'
      );
    }

    console.log('[initiateWebPayment] Adattov├íbb├şt├ísi nyilatkozat elfogadva:', {
      userId,
      acceptedDate: userData.dataTransferConsentLastAcceptedDate
    });

    const email = userData.email;
    const name = userData.firstName && userData.lastName ? `${userData.firstName} ${userData.lastName}`.trim() : userData.displayName;

    if (!email) {
      throw new HttpsError('failed-precondition', 'A felhaszn├íl├│hoz nem tartozik email c├şm');
    }

    const orderRef = `WEB_${userId}_${Date.now()}`;
    // Visszair├íny├şt├ísi b├ízis valid├íl├ísa (ne ugorjon loginra ismeretlen domain miatt)
    const returnBase = (SIMPLEPAY_CONFIG.allowedReturnBases && SIMPLEPAY_CONFIG.allowedReturnBases.length > 0)
      ? SIMPLEPAY_CONFIG.allowedReturnBases[0]
      : SIMPLEPAY_CONFIG.nextAuthUrl;
    const nextAuthBase = returnBase.replace(/\/$/, '');
    const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || '';
    const webhookUrl = `https://europe-west1-${projectId}.cloudfunctions.net/simplepayWebhook`;

    // Id┼Ĺkorl├ít sz├ím├şt├ísa (30 perc a j├Âv┼Ĺben) ISO form├ítumban, milliszekundumok n├ęlk├╝l
    // P├ęlda: 2025-10-15T12:34:56Z
    const timeout = new Date(Date.now() + 30 * 60 * 1000)
      .toISOString()
      .replace(/\.\d{3}Z$/, 'Z');

    const simplePayRequest = {
      salt: crypto.randomBytes(16).toString('hex'),
      merchant: SIMPLEPAY_CONFIG.merchantId.trim(),
      orderRef,
      customerEmail: email,
      language: 'HU',
      sdkVersion: 'CustomBashScript_v1.0',
      currency: 'HUF',
      timeout: timeout,
      methods: ['CARD'],
      // IPN/Webhook ├ęrtes├şt├ęsi URL (server-to-server)
      url: webhookUrl,
      urls: {
        success: `${nextAuthBase}/account?payment=success&orderRef=${orderRef}`,
        fail: `${nextAuthBase}/account?payment=fail&orderRef=${orderRef}`,
        timeout: `${nextAuthBase}/account?payment=timeout&orderRef=${orderRef}`,
        cancel: `${nextAuthBase}/account?payment=cancelled&orderRef=${orderRef}`,
      },
      items: [{
        ref: canonicalPlanId,
        title: plan.name,
        description: plan.description,
        amount: 1,
        price: finalPrice,
      }],
    };

    // Ellen┼Ĺrizz├╝k, hogy a JSON form├íz├ís helyes-e
    const payloadKeys = Object.keys(simplePayRequest);
    if (!payloadKeys.includes('items') || !Array.isArray(simplePayRequest.items) || simplePayRequest.items.length === 0) {
      throw new HttpsError('invalid-argument', 'Az items t├Âmb hib├ísan form├ízott vagy hi├ínyzik');
    }

    // Ellen┼Ĺrizz├╝k, hogy minden sz├╝ks├ęges kulcs megvan-e
    const requiredKeys = ['salt', 'merchant', 'orderRef', 'customerEmail', 'language', 'currency', 'timeout', 'methods', 'urls', 'items'];
    const missingKeys = requiredKeys.filter(key => !payloadKeys.includes(key));
    if (missingKeys.length > 0) {
      throw new HttpsError('invalid-argument', `Hi├ínyz├│ kulcsok a k├ęr├ęsben: ${missingKeys.join(', ')}`);
    }

    console.log('[initiateWebPayment] outgoing payload', {
      orderRef,
      url: simplePayRequest.url,
      hasPaymentUrl: true,
    });

    const requestBody = JSON.stringify(simplePayRequest);
    const signature = crypto.createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim()).update(requestBody).digest('base64');

    const response = await fetch(`${SIMPLEPAY_CONFIG.baseUrl.trim()}start`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json; charset=utf-8',
        'Signature': signature,
      },
      body: requestBody,
    });

    if (!response.ok) {
      const errorText = await response.text();
      console.error('[initiateWebPayment] SimplePay HTTP error', { status: response.status, errorText, orderRef });
      throw new HttpsError('internal', 'Fizet├ęsi szolg├íltat├│ API hiba');
    }

    const paymentData = await response.json();
    if (!paymentData?.paymentUrl) {
      const errorCodes = paymentData?.errorCodes;

      // R├ęszletes log a 5321-es hibak├│dhoz
      if (Array.isArray(errorCodes) && errorCodes.includes('5321')) {
        console.error('=================================================================');
        console.error('SIMPLEPAY HIBAK├ôD 5321 R├ëSZLETES ELEMZ├ëS:');
        console.error('=================================================================');
        console.error('K├ęr├ęs adatok:', JSON.stringify(simplePayRequest, null, 2));
        console.error('SimplePay v├ílasz:', JSON.stringify(paymentData, null, 2));
        console.error('Al├í├şr├ís gener├íl├ís alapja:', requestBody);
        console.error('Gener├ílt al├í├şr├ís:', signature);
        console.error('=================================================================');
      }

      // Audit log - sikertelen fizet├ęs ind├şt├ís
      await db.collection('payment_audit_logs').add({
        userId,
        orderRef,
        action: 'PAYMENT_INITIATION_FAILED',
        planId: canonicalPlanId,
        amount: finalPrice,
        environment: SIMPLEPAY_CONFIG.env,
        timestamp: admin.firestore.FieldValue.serverTimestamp(),
        metadata: {
          errorCodes: errorCodes || [],
          simplePayResponse: paymentData,
          errorMessage: getSimplePayErrorMessage(errorCodes),
        },
      });

      console.error('[initiateWebPayment] SimplePay start returned logical error', { orderRef, errorCodes, rawResponse: paymentData, payload: simplePayRequest });

      // R├ęszletes hiba├╝zenet visszaad├ísa
      const detailedError = getSimplePayErrorMessage(errorCodes);
      throw new HttpsError('failed-precondition', `SimplePay hiba: ${detailedError}`);
    }

    await db.collection('web_payments').doc(orderRef).set({
      userId,
      planId: canonicalPlanId,
      orderRef,
      simplePayTransactionId: paymentData.transactionId || null,
      amount: finalPrice,
      status: 'INITIATED',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log - fizet├ęs ind├şt├ísa
    await db.collection('payment_audit_logs').add({
      userId,
      orderRef,
      action: 'PAYMENT_INITIATED',
      planId: canonicalPlanId,
      amount: finalPrice,
      environment: SIMPLEPAY_CONFIG.env,
      paymentUrl: paymentData.paymentUrl,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        simplePayTransactionId: paymentData.transactionId || null,
        userEmail: email,
      },
    });

    return { success: true, paymentUrl: paymentData.paymentUrl, orderRef };
  } catch (error) {
    if (error instanceof HttpsError) throw error;
    throw new HttpsError('internal', error?.message || 'Ismeretlen szerverhiba');
  }
});

/**
 * Fizet├ęs lez├ír├ísa (FINISH) SimplePay v2 API-val
 * - Client a sikeres visszair├íny├şt├ís ut├ín h├şvja: { orderRef }
 * - Siker eset├ęn users/{uid} friss├╝l ├ęs web_payments status COMPLETED-re v├ílt
 */
exports.confirmWebPayment = onCall({ secrets: ['SIMPLEPAY_MERCHANT_ID', 'SIMPLEPAY_SECRET_KEY', 'SIMPLEPAY_ENV'] }, async (request) => {
  try {
    const SIMPLEPAY_CONFIG = getSimplePayConfig();
    const { orderRef } = request.data || {};
    if (!orderRef || typeof orderRef !== 'string') {
      throw new HttpsError('invalid-argument', 'orderRef sz├╝ks├ęges');
    }

    const orderRefParts = orderRef.split('_');
    if (orderRefParts.length < 3 || orderRefParts[0] !== 'WEB') {
      throw new HttpsError('invalid-argument', '├ërv├ęnytelen orderRef form├ítum');
    }
    const userId = orderRefParts[1];

    if (!SIMPLEPAY_CONFIG.merchantId || !SIMPLEPAY_CONFIG.secretKey) {
      throw new HttpsError('failed-precondition', 'SimplePay konfigur├íci├│ hi├ínyzik');
    }

    // Lek├ęrj├╝k a fizet├ęsi rekordot
    const paymentRef = db.collection('web_payments').doc(orderRef);
    const paymentSnap = await paymentRef.get();
    if (!paymentSnap.exists) {
      throw new HttpsError('not-found', 'Fizet├ęsi rekord nem tal├ílhat├│');
    }
    const pay = paymentSnap.data();
    const rawPlanId = pay.planId;
    const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
    const plan = PAYMENT_PLANS[canonicalPlanId];
    if (!plan) {
      throw new HttpsError('failed-precondition', '├ërv├ęnytelen csomag');
    }

    // QUERY ÔÇô ellen┼Ĺrz├ęs SimplePay v2 API-val (biztos lez├ír├ís helyett st├ítusz lek├ęrdez├ęs)
    const queryPayload = {
      salt: crypto.randomBytes(16).toString('hex'),
      merchant: SIMPLEPAY_CONFIG.merchantId.trim(),
      orderRef,
    };
    const queryBody = JSON.stringify(queryPayload);
    const querySig = crypto.createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim()).update(queryBody).digest('base64');
    const queryResp = await fetch(`${SIMPLEPAY_CONFIG.baseUrl.trim()}query`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json; charset=utf-8', 'Signature': querySig },
      body: queryBody,
    });
    if (!queryResp.ok) {
      const txt = await queryResp.text();
      console.error('[confirmWebPayment] query HTTP error', { status: queryResp.status, txt });
      throw new HttpsError('internal', 'Query h├şv├ís sikertelen');
    }
    const queryTxt = await queryResp.text();
    let queryData; try { queryData = JSON.parse(queryTxt); } catch (_) { queryData = { raw: queryTxt }; }
    const successLike = (queryData?.status || '').toString().toUpperCase() === 'SUCCESS' || !!queryData?.transactionId;
    if (!successLike) {
      console.warn('[confirmWebPayment] query not SUCCESS', { orderRef, queryData });
      return { success: false, status: queryData?.status || 'UNKNOWN' };
    }

    const transactionId = queryData?.transactionId || pay.simplePayTransactionId || null;
    const orderId = queryData?.orderId || null;

    // El┼Ĺfizet├ęs aktiv├íl├ísa
    const now = new Date();
    const expiryDate = new Date(now.getTime() + (plan.subscriptionDays * 24 * 60 * 60 * 1000));
    const subscriptionData = {
      isSubscriptionActive: true,
      subscriptionStatus: 'premium',
      subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiryDate),
      subscription: {
        status: 'ACTIVE',
        productId: canonicalPlanId,
        purchaseToken: transactionId,
        orderId: orderId,
        endTime: expiryDate.toISOString(),
        lastUpdateTime: now.toISOString(),
        source: 'otp_simplepay',
      },
      lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
      freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
    };

    await db.collection('users').doc(userId).set(subscriptionData, { merge: true });
    await db.collection('users').doc(userId).update({ lastReminder: admin.firestore.FieldValue.delete() });

    await paymentRef.update({
      status: 'COMPLETED',
      transactionId,
      orderId,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log - fizet├ęs meger┼Ĺs├şt├ęse
    await db.collection('payment_audit_logs').add({
      userId,
      orderRef,
      action: 'PAYMENT_CONFIRMED',
      planId: canonicalPlanId,
      amount: plan.price,
      environment: SIMPLEPAY_CONFIG.env,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        transactionId,
        orderId,
        queryStatus: queryData?.status || 'UNKNOWN',
      },
    });

    console.log('[confirmWebPayment] completed', { userId, orderRef });
    return { success: true, status: 'COMPLETED' };
  } catch (err) {
    console.error('[confirmWebPayment] error', { message: err?.message, stack: err?.stack });
    if (err instanceof HttpsError) throw err;
    throw new HttpsError('internal', err?.message || 'Ismeretlen hiba');
  }
});

/**
 * SimplePay callback alapj├ín status friss├şt├ęs
 * - Browser callback (payment=fail/success/stb) alapj├ín azonnal friss├şti a status-t
 * - Biztons├ígi ellen┼Ĺrz├ęsek: user ID valid├íci├│, v├ęgleges st├ítusz v├ędelem
 * - Az IPN webhook tov├íbbra is fel├╝l├şrhat mindent (┼Ĺ a v├ęgs┼Ĺ igazs├íg)
 */
exports.updatePaymentStatusFromCallback = onCall(async (request) => {
  // 1. User authentik├íci├│ ellen┼Ĺrz├ęse
  if (!request.auth) {
    throw new HttpsError('unauthenticated', 'Bejelentkez├ęs sz├╝ks├ęges');
  }

  const userId = request.auth.uid;
  const { orderRef, callbackStatus } = request.data || {};

  if (!orderRef || !callbackStatus) {
    throw new HttpsError('invalid-argument', 'orderRef ├ęs callbackStatus sz├╝ks├ęges');
  }

  // Callback status Ôćĺ Firestore status mapping
  const statusMap = {
    'success': 'COMPLETED',
    'fail': 'FAILED',
    'timeout': 'TIMEOUT',
    'cancelled': 'CANCELLED',
  };

  const firestoreStatus = statusMap[callbackStatus] || 'INITIATED';

  try {
    // 2. Payment dokumentum lek├ęr├ęse
    const paymentDoc = await db.collection('web_payments').doc(orderRef).get();

    if (!paymentDoc.exists) {
      throw new HttpsError('not-found', 'Fizet├ęs nem tal├ílhat├│');
    }

    const paymentData = paymentDoc.data();

    // 3. User ID valid├íci├│ - CSAK a saj├ít fizet├ęs├ęt friss├ştheti!
    if (paymentData.userId !== userId) {
      console.warn('[updatePaymentStatusFromCallback] UNAUTHORIZED attempt', {
        userId,
        orderRef,
        paymentUserId: paymentData.userId
      });
      throw new HttpsError('permission-denied', 'Nincs jogosults├íg ehhez a fizet├ęshez');
    }

    // 4. St├ítusz v├ędelem - Ne ├şrjuk fel├╝l, ha m├ír v├ęgleges
    // (Az IPN webhook tov├íbbra is fel├╝l├şrhat, mert az admin jogokkal fut)
    const finalStatuses = ['COMPLETED', 'FAILED'];
    if (finalStatuses.includes(paymentData.status)) {
      console.log('[updatePaymentStatusFromCallback] Already in final status', {
        orderRef,
        currentStatus: paymentData.status,
        attemptedStatus: firestoreStatus
      });
      // Visszaadjuk a jelenlegi st├ítuszt, de nem friss├ştj├╝k
      return { success: false, status: paymentData.status, message: 'M├ír v├ęgleges st├ítuszban van' };
    }

    // 5. Friss├şt├ęs v├ęgrehajt├ísa
    await db.collection('web_payments').doc(orderRef).update({
      status: firestoreStatus,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    console.log('[updatePaymentStatusFromCallback] Updated successfully', {
      userId,
      orderRef,
      callbackStatus,
      firestoreStatus
    });

    return { success: true, status: firestoreStatus };
  } catch (error) {
    // Ha m├ír HttpsError, akkor ├ítdobjuk
    if (error.code) {
      throw error;
    }
    // Egy├ęb hib├ík
    console.error('[updatePaymentStatusFromCallback] Error', { orderRef, error: error.message });
    throw new HttpsError('internal', error.message || 'Status friss├şt├ęs sikertelen');
  }
});

/**
 * SimplePay webhook feldolgoz├ís
 */
exports.processWebPaymentWebhook = onCall({ secrets: ['SIMPLEPAY_SECRET_KEY', 'NEXTAUTH_URL', 'SIMPLEPAY_ENV'] }, async (request) => {
  try {
    const SIMPLEPAY_CONFIG = getSimplePayConfig();
    const webhookData = request.data || {};
    console.debug('[processWebPaymentWebhook] input status/orderRef', { status: webhookData?.status, orderRef: webhookData?.orderRef });

    // Webhook adatok valid├íl├ísa
    const { orderRef, transactionId, orderId, status, total, items } = webhookData;

    if (!orderRef || !transactionId || !status) {
      throw new HttpsError('invalid-argument', 'Hi├ínyz├│ webhook adatok');
    }

    // Csak sikeres fizet├ęseket dolgozunk fel
    if (status !== 'SUCCESS') {
      console.log('Payment not successful, ignoring webhook:', status);
      return { success: true };
    }

    // Felhaszn├íl├│ azonos├şt├ísa az orderRef-b┼Ĺl
    // Form├ítum: WEB_userId_timestamp_random
    const orderRefParts = orderRef.split('_');
    if (orderRefParts.length < 3 || orderRefParts[0] !== 'WEB') {
      throw new HttpsError('invalid-argument', '├ërv├ęnytelen orderRef form├ítum');
    }

    const userId = orderRefParts[1];

    // Fizet├ęsi rekord friss├şt├ęse
    const paymentRef = db.collection('web_payments').doc(orderRef);
    const paymentDoc = await paymentRef.get();

    if (!paymentDoc.exists) {
      throw new HttpsError('not-found', 'Fizet├ęsi rekord nem tal├ílhat├│');
    }

    const paymentData = paymentDoc.data();
    const rawPlanId = paymentData.planId;
    const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
    const plan = PAYMENT_PLANS[canonicalPlanId];

    if (!plan) {
      throw new HttpsError('failed-precondition', '├ërv├ęnytelen csomag');
    }

    // El┼Ĺfizet├ęs aktiv├íl├ísa
    const now = new Date();
    const expiryDate = new Date(now.getTime() + (plan.subscriptionDays * 24 * 60 * 60 * 1000));

    const subscriptionData = {
      // Kompatibilit├ísi mez┼Ĺk (a mobilalkalmaz├ís ezeket haszn├ílja)
      isSubscriptionActive: true,
      subscriptionStatus: 'premium',
      subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiryDate),

      // R├ęszletes adatok
      subscription: {
        status: 'ACTIVE',
        productId: canonicalPlanId,
        purchaseToken: transactionId,
        orderId: orderId,
        endTime: expiryDate.toISOString(),
        lastUpdateTime: now.toISOString(),
        source: 'otp_simplepay',
      },

      // Meta adatok
      lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),

      // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
      freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
    };

    // Felhaszn├íl├│i dokumentum friss├şt├ęse
    await db.collection('users').doc(userId).set(subscriptionData, { merge: true });

    // ├Üj el┼Ĺfizet├ęs eset├ęn t├Âr├Âlj├╝k a lastReminder mez┼Ĺket, hogy ├║jra k├╝ldhess├╝nk emailt
    await db.collection('users').doc(userId).update({
      lastReminder: admin.firestore.FieldValue.delete(),
    });

    // Fizet├ęsi rekord friss├şt├ęse
    await paymentRef.update({
      status: 'COMPLETED',
      transactionId: transactionId,
      orderId: orderId,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    console.log('[processWebPaymentWebhook] updated payment to COMPLETED', { userId, orderRef });

    return { success: true };

  } catch (error) {
    console.error('[processWebPaymentWebhook] error', { message: error?.message, stack: error?.stack });
    if (error instanceof HttpsError || error?.code) {
      throw error;
    }
    throw new HttpsError('internal', error?.message || 'Ismeretlen hiba a SimplePay webhook feldolgoz├ísakor');
  }
});

/**
 * HTTP webhook endpoint SimplePay sz├ím├íra
 */
exports.simplepayWebhook = onRequest({
  secrets: ['SIMPLEPAY_SECRET_KEY', 'NEXTAUTH_URL', 'SIMPLEPAY_ENV'],
  region: 'europe-west1',
}, async (req, res) => {
  try {
    const SIMPLEPAY_CONFIG = getSimplePayConfig();
    // CORS headers
    res.set('Access-Control-Allow-Origin', '*');
    res.set('Access-Control-Allow-Methods', 'POST, OPTIONS');
    res.set('Access-Control-Allow-Headers', 'Content-Type, Signature, x-simplepay-signature, x-signature');

    if (req.method === 'OPTIONS') {
      res.status(200).send('');
      return;
    }

    if (req.method !== 'POST') {
      res.status(405).send('Method not allowed');
      return;
    }

    const body = req.body;
    const headerSignature = (
      req.headers['signature'] ||
      req.headers['x-simplepay-signature'] ||
      req.headers['x-signature'] ||
      ''
    ).toString();

    if (!headerSignature) {
      console.error('[simplepayWebhook] Missing signature', {
        headerKeys: Object.keys(req.headers || {}),
        rawLen: Buffer.isBuffer(req.rawBody) ? req.rawBody.length : String(JSON.stringify(body)).length,
      });
      res.status(400).send('Missing signature');
      return;
    }

    // Al├í├şr├ís ellen┼Ĺrz├ęse ÔÇô SimplePay v2: HMAC-SHA384 + base64 a RAW BODY-ra
    if (!SIMPLEPAY_CONFIG.secretKey) {
      console.error('[simplepayWebhook] Secret key not configured');
      res.status(500).send('Configuration error');
      return;
    }

    const raw = Buffer.isBuffer(req.rawBody)
      ? req.rawBody
      : Buffer.from(JSON.stringify(body));

    const expectedSigSha384B64 = crypto
      .createHmac('sha384', SIMPLEPAY_CONFIG.secretKey)
      .update(raw)
      .digest('base64');

    // Biztons├ígos ├Âsszehasonl├şt├ís
    const a = Buffer.from(headerSignature);
    const b = Buffer.from(expectedSigSha384B64);
    const valid = a.length === b.length && crypto.timingSafeEqual(a, b);

    if (!valid) {
      console.error('[simplepayWebhook] Invalid signature', {
        headerSignatureMasked: maskValue(headerSignature),
        expectedMasked: maskValue(expectedSigSha384B64),
        headerKeys: Object.keys(req.headers || {}),
        rawLen: raw.length,
      });
      res.status(401).send('Invalid signature');
      return;
    }

    const incomingStatus = (body?.status || '').toString().toUpperCase();
    console.log('[simplepayWebhook] received', {
      status: incomingStatus,
      orderRef: body?.orderRef,
      headers: {
        signatureMasked: maskValue(headerSignature),
      },
    });

    // Csak sikeres fizet├ęseket dolgozunk fel ÔÇô a SimplePay itt 'FINISHED' st├ítuszt k├╝ld,
    // ami a tranzakci├│ sikeres lez├ír├ís├ít jelenti. Kezelj├╝k SUCCESS-k├ęnt.
    if (incomingStatus !== 'SUCCESS' && incomingStatus !== 'FINISHED') {
      console.log('[simplepayWebhook] non-success status, ignoring');
      res.status(200).send('OK');
      return;
    }

    const { orderRef, transactionId, orderId, total, items } = body;

    // Felhaszn├íl├│ azonos├şt├ísa az orderRef-b┼Ĺl
    const orderRefParts = orderRef.split('_');
    if (orderRefParts.length < 3 || orderRefParts[0] !== 'WEB') {
      console.error('Invalid orderRef format:', orderRef);
      res.status(400).send('Invalid order reference');
      return;
    }

    const userId = orderRefParts[1];

    // Fizet├ęsi rekord lek├ęr├ęse
    const paymentRef = db.collection('web_payments').doc(orderRef);
    const paymentDoc = await paymentRef.get();

    if (!paymentDoc.exists) {
      console.error('[simplepayWebhook] Payment record not found', { orderRef });
      res.status(404).send('Payment record not found');
      return;
    }

    const paymentData = paymentDoc.data();
    const rawPlanId = paymentData.planId;
    const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
    const plan = PAYMENT_PLANS[canonicalPlanId];

    if (!plan) {
      console.error('[simplepayWebhook] Invalid plan', { planId });
      res.status(400).send('Invalid plan');
      return;
    }

    // El┼Ĺfizet├ęs aktiv├íl├ísa
    const now = new Date();
    const expiryDate = new Date(now.getTime() + (plan.subscriptionDays * 24 * 60 * 60 * 1000));

    const subscriptionData = {
      isSubscriptionActive: true,
      subscriptionStatus: 'premium',
      subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiryDate),
      subscription: {
        status: 'ACTIVE',
        productId: canonicalPlanId,
        purchaseToken: transactionId || null,
        orderId: orderId || null,
        endTime: expiryDate.toISOString(),
        lastUpdateTime: now.toISOString(),
        source: 'otp_simplepay',
      },
      lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
      freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
    };

    // Felhaszn├íl├│i dokumentum friss├şt├ęse
    await db.collection('users').doc(userId).set(subscriptionData, { merge: true });

    // ├Üj el┼Ĺfizet├ęs eset├ęn t├Âr├Âlj├╝k a lastReminder mez┼Ĺket, hogy ├║jra k├╝ldhess├╝nk emailt
    await db.collection('users').doc(userId).update({
      lastReminder: admin.firestore.FieldValue.delete(),
    });

    // Fizet├ęsi rekord friss├şt├ęse
    await paymentRef.update({
      status: 'COMPLETED',
      transactionId: transactionId || null,
      orderId: orderId || null,
      completedAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    // Audit log - webhook feldolgoz├ís
    await db.collection('payment_audit_logs').add({
      userId,
      orderRef,
      action: 'WEBHOOK_RECEIVED',
      planId: canonicalPlanId,
      amount: plan.price,
      environment: SIMPLEPAY_CONFIG.env,
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      metadata: {
        transactionId: transactionId || null,
        orderId: orderId || null,
        webhookStatus: incomingStatus,
        signatureValid: true,
      },
    });

    console.log('[simplepayWebhook] updated payment to COMPLETED', { userId, orderRef });

    // IPN CONFIRM - SimplePay v2.1 k├Âvetelm├ęny (9.6.2 ├ęs 3.14)
    // A v├ílasznak tartalmaznia kell az ├ľSSZES fogadott IPN adatot + receiveDate
    const confirmResponse = {
      ...body,  // ├ľsszes fogadott IPN adat visszak├╝ld├ęse
      receiveDate: new Date().toISOString(),
    };
    const confirmBody = JSON.stringify(confirmResponse);

    // DEBUG: Log a teljes IPN confirm v├ílaszt
    console.log('[simplepayWebhook] IPN CONFIRM REQUEST BODY:', JSON.stringify(body, null, 2));
    console.log('[simplepayWebhook] IPN CONFIRM RESPONSE BODY:', confirmBody);

    const confirmSignature = crypto
      .createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim())
      .update(confirmBody)
      .digest('base64');

    console.log('[simplepayWebhook] IPN CONFIRM SIGNATURE:', confirmSignature.substring(0, 20) + '...');

    res.set('Content-Type', 'application/json; charset=utf-8');
    res.set('Signature', confirmSignature);
    res.status(200).send(confirmBody);

  } catch (error) {
    console.error('[simplepayWebhook] error', { message: error?.message, stack: error?.stack });
    res.status(500).send('Internal server error');
  }
});

/**
 * Firestore trigger: web_payments/{orderRef}
 * Ha egy fizet├ęs elk├ęsz├╝lt (status == 'INITIATED' Ôćĺ 'SUCCESS'/'COMPLETED' vagy manu├ílisan be├íll├ştott SUCCESS),
 * friss├şti a users/{uid} dokumentumot a mobil s├ęm├ínak megfelel┼Ĺen.
 */
exports.onWebPaymentWrite = onDocumentWritten({
  document: 'web_payments/{orderRef}',
  secrets: ['SIMPLEPAY_MERCHANT_ID', 'SIMPLEPAY_SECRET_KEY', 'SIMPLEPAY_ENV'],
}, async (event) => {
  try {
    const SIMPLEPAY_CONFIG = getSimplePayConfig();
    const before = event.data?.before?.data() || null;
    const after = event.data?.after?.data() || null;

    // Ha t├Ârl├ęs, nincs teend┼Ĺ
    if (!after) return;

    const status = (after.status || '').toString().toUpperCase();
    const userId = after.userId;
    const rawPlanId = after.planId;
    const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
    const plan = PAYMENT_PLANS[canonicalPlanId];

    console.log('[onWebPaymentWrite] trigger', {
      orderRef: event.params.orderRef,
      status,
      userId,
      planId: rawPlanId,
    });

    if (!userId || !plan) {
      console.warn('[onWebPaymentWrite] skip - missing user/plan', {
        orderRef: event.params.orderRef,
        hasUser: !!userId,
        hasPlan: !!plan,
      });
      return;
    }

    // Csak akkor ├şrunk, ha:
    // - ├║j dokumentum j├Âtt l├ętre ├ęs m├ír SUCCESS/COMPLETED, vagy
    // - status v├íltozott INITIATED/PENDING Ôćĺ SUCCESS/COMPLETED
    const beforeStatus = (before?.status || '').toString().toUpperCase();
    const meaningfulTransition = (
      (!before && (status === 'SUCCESS' || status === 'COMPLETED')) ||
      (before && beforeStatus !== status && (status === 'SUCCESS' || status === 'COMPLETED'))
    );

    // Ha m├ęg csak INITIATED, megpr├│b├íljuk a FINISH h├şv├íst szerverr┼Ĺl (nem kell kliensre v├írni)
    if (status === 'INITIATED') {
      try {
        if (!SIMPLEPAY_CONFIG.merchantId || !SIMPLEPAY_CONFIG.secretKey) {
          console.warn('[onWebPaymentWrite] finish skipped - config missing');
          return;
        }
        // QUERY ÔÇô ├íllapot lek├ęrdez├ęse a FINISH helyett
        // T├Âbbsz├Âri query 5 m├ísodpercig; SimplePay k├ęsleltetett ├íllapotk├Âzl├ęs eset├ęre
        let data = null;
        for (let i = 0; i < 20; i++) {
          const queryPayload = { salt: crypto.randomBytes(16).toString('hex'), merchant: SIMPLEPAY_CONFIG.merchantId.trim(), orderRef: event.params.orderRef };
          const queryBody = JSON.stringify(queryPayload);
          const querySig = crypto.createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim()).update(queryBody).digest('base64');
          const resp = await fetch(`${SIMPLEPAY_CONFIG.baseUrl.trim()}query`, {
            method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8', Signature: querySig }, body: queryBody,
          });
          const txt = await resp.text();
          try { data = JSON.parse(txt); } catch (_) { data = { raw: txt }; }
          const ok = (data?.status || '').toString().toUpperCase() === 'SUCCESS' || !!data?.transactionId;
          if (ok) break;
          await sleep(1000);
        }
        if (data) {
          const ok = (data?.status || '').toString().toUpperCase() === 'SUCCESS' || !!data?.transactionId;
          if (ok) {
            const now = new Date();
            const expiryDate = new Date(
              now.getTime() + plan.subscriptionDays * 24 * 60 * 60 * 1000
            );
            const transactionId = data?.transactionId || after.simplePayTransactionId || null;
            const orderId = data?.orderId || null;

            const subscriptionData = {
              isSubscriptionActive: true,
              subscriptionStatus: 'premium',
              subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiryDate),
              subscription: {
                status: 'ACTIVE',
                productId: canonicalPlanId,
                purchaseToken: transactionId,
                orderId: orderId,
                endTime: expiryDate.toISOString(),
                lastUpdateTime: now.toISOString(),
                source: 'otp_simplepay',
              },
              lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
              // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
              freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
            };

            await db.collection('users').doc(userId).set(subscriptionData, { merge: true });
            await db.collection('users').doc(userId).update({
              lastReminder: admin.firestore.FieldValue.delete(),
            });
            await event.data.after.ref.update({
              status: 'COMPLETED',
              transactionId,
              orderId,
              completedAt: admin.firestore.FieldValue.serverTimestamp(),
              updatedAt: admin.firestore.FieldValue.serverTimestamp(),
            });
            console.log('[onWebPaymentWrite] completed via FINISH', { userId, orderRef: event.params.orderRef });
          } else {
            console.log('[onWebPaymentWrite] query not SUCCESS', { orderRef: event.params.orderRef, status: data?.status, data });
          }
        }
      } catch (e) {
        console.error('[onWebPaymentWrite] finish call failed', { message: e?.message });
      }
      return;
    }

    if (!meaningfulTransition) {
      console.log('[onWebPaymentWrite] no-op transition', {
        orderRef: event.params.orderRef,
        beforeStatus,
        status,
      });
      return;
    }

    const now = new Date();
    const expiryDate = new Date(now.getTime() + (plan.subscriptionDays * 24 * 60 * 60 * 1000));

    const subscriptionData = {
      isSubscriptionActive: true,
      subscriptionStatus: 'premium',
      subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiryDate),
      subscription: {
        status: 'ACTIVE',
        productId: canonicalPlanId,
        purchaseToken: after.transactionId || after.simplePayTransactionId || null,
        orderId: after.orderId || null,
        endTime: expiryDate.toISOString(),
        lastUpdateTime: now.toISOString(),
        source: 'otp_simplepay',
      },
      lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
      freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
    };

    await db.collection('users').doc(userId).set(subscriptionData, { merge: true });
    await db.collection('users').doc(userId).update({
      lastReminder: admin.firestore.FieldValue.delete(),
    });

    console.log('[onWebPaymentWrite] user updated from web_payments', { userId, orderRef: event.params.orderRef, status });
  } catch (err) {
    console.error('[onWebPaymentWrite] error', { message: err?.message, stack: err?.stack });
  }
});

// Stabil reconcil├íci├│: INITIATED web_payments rekordok ut├│z├ír├ísa QUERY-vel
exports.reconcileWebPaymentsScheduled = onSchedule({
  schedule: '*/2 * * * *',
  timeZone: 'Europe/Budapest',
  memory: '256MiB',
  timeoutSeconds: 240,
}, async () => {
  const cfg = getSimplePayConfig();
  try {
    const cutoff = new Date(Date.now() - 90 * 1000); // 90s-n├ęl r├ęgebbi INITIATED
    const snap = await db.collection('web_payments')
      .where('status', '==', 'INITIATED')
      .where('createdAt', '<=', admin.firestore.Timestamp.fromDate(cutoff))
      .limit(20).get();
    if (snap.empty) return { ok: true, reconciled: 0 };
    let reconciled = 0;
    for (const d of snap.docs) {
      const pay = d.data();
      const orderRef = pay.orderRef || d.id;
      const userId = pay.userId;
      const canonicalPlanId = CANONICAL_PLAN_ID[pay.planId] || pay.planId;
      const plan = PAYMENT_PLANS[canonicalPlanId];
      if (!userId || !plan) continue;
      // 10 pr├│b├ílat, 1 mp-es poll
      let data = null;
      for (let i = 0; i < 10; i++) {
        const pl = { salt: crypto.randomBytes(16).toString('hex'), merchant: cfg.merchantId.trim(), orderRef };
        const body = JSON.stringify(pl);
        const sig = crypto.createHmac('sha384', cfg.secretKey.trim()).update(body).digest('base64');
        const r = await fetch(`${cfg.baseUrl.trim()}query`, { method: 'POST', headers: { 'Content-Type': 'application/json; charset=utf-8', Signature: sig }, body });
        const t = await r.text();
        try { data = JSON.parse(t); } catch (_) { data = { raw: t }; }
        const ok = (data?.status || '').toString().toUpperCase() === 'SUCCESS' || !!data?.transactionId;
        if (ok) break;
        await sleep(1000);
      }
      const ok = data && ((data.status || '').toString().toUpperCase() === 'SUCCESS' || !!data.transactionId);
      if (!ok) continue;
      const now = new Date();
      const expiry = new Date(now.getTime() + plan.subscriptionDays * 24 * 60 * 60 * 1000);
      const transactionId = data?.transactionId || pay.simplePayTransactionId || null;
      const orderId = data?.orderId || null;
      await db.collection('users').doc(userId).set({
        isSubscriptionActive: true,
        subscriptionStatus: 'premium',
        subscriptionEndDate: admin.firestore.Timestamp.fromDate(expiry),
        subscription: {
          status: 'ACTIVE', productId: canonicalPlanId, purchaseToken: transactionId,
          orderId, endTime: expiry.toISOString(), lastUpdateTime: now.toISOString(), source: 'otp_simplepay'
        },
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Pr├│baid┼Ĺszak lez├ír├ísa az els┼Ĺ fizet├ęskor
        freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
      }, { merge: true });
      await d.ref.update({ status: 'COMPLETED', transactionId, orderId, completedAt: admin.firestore.FieldValue.serverTimestamp(), updatedAt: admin.firestore.FieldValue.serverTimestamp() });
      reconciled++;
      console.log('[reconcileWebPaymentsScheduled] reconciled', { orderRef });
    }
    return { ok: true, reconciled };
  } catch (e) {
    console.error('[reconcileWebPaymentsScheduled] error', { message: e?.message });
    throw e;
  }
});

// El┼Ĺfizet├ęsi eml├ękeztet┼Ĺ email k├╝ld├ęse
exports.sendSubscriptionReminder = onCall(async (request) => {
  const { userId, reminderType, daysLeft } = request.data || {};

  if (!userId || !reminderType) {
    throw new Error('invalid-argument: userId ├ęs reminderType sz├╝ks├ęges');
  }

  try {
    // Felhaszn├íl├│ adatainak lek├ęr├ęse
    const userDoc = await db.collection('users').doc(userId).get();
    if (!userDoc.exists) {
      throw new Error('not-found: Felhaszn├íl├│ nem tal├ílhat├│');
    }

    const userData = userDoc.data();
    const email = userData.email;
    const name = userData.name || userData.displayName || 'Felhaszn├íl├│';

    if (!email) {
      throw new Error('invalid-argument: Felhaszn├íl├│ email c├şme nem tal├ílhat├│');
    }

    // Duplik├ítum v├ędelem - ellen┼Ĺrizz├╝k, hogy m├ír k├╝ldt├╝nk-e ilyen t├şpus├║ emailt
    const lastReminder = userData.lastReminder || {};
    const reminderKey = reminderType === 'expiry_warning' ? 'expiry_warning' : 'expired';

    if (lastReminder[reminderKey]) {
      console.log(`Skipping ${reminderType} email for ${userId} - already sent on ${lastReminder[reminderKey].toDate().toISOString()}`);
      return { success: true, message: 'Email m├ír elk├╝ldve (duplik├ítum v├ędelem)', skipped: true };
    }

    let subject, text, html;

    if (reminderType === 'expiry_warning') {
      // Lej├írat el┼Ĺtti figyelmeztet├ęs
      subject = `El┼Ĺfizet├ęsed hamarosan lej├ír - ${daysLeft} nap h├ítra`;
      text = `Kedves ${name}!\n\nEl┼Ĺfizet├ęsed ${daysLeft} nap m├║lva lej├ír. Ne maradj le a pr├ęmium funkci├│kr├│l!\n\n├Üj├ştsd meg el┼Ĺfizet├ęsedet: https://lomedu-user-web.web.app/subscription\n\n├ťdv├Âzlettel,\nA Lomedu csapat`;
      html = `<p>Kedves ${name}!</p><p>El┼Ĺfizet├ęsed <strong>${daysLeft} nap m├║lva lej├ír</strong>. Ne maradj le a pr├ęmium funkci├│kr├│l!</p><p><a href="https://lomedu-user-web.web.app/subscription">├Üj├ştsd meg el┼Ĺfizet├ęsedet</a></p><p>├ťdv├Âzlettel,<br>A Lomedu csapat</p>`;
    } else if (reminderType === 'expired') {
      // Lej├írat ut├íni ├ęrtes├şt├ęs
      subject = 'El┼Ĺfizet├ęsed lej├írt - ├Üj├ştsd meg most!';
      text = `Kedves ${name}!\n\nEl┼Ĺfizet├ęsed lej├írt. ├Üj├ştsd meg most, hogy ne maradj le a pr├ęmium funkci├│kr├│l!\n\n├Üj├ştsd meg el┼Ĺfizet├ęsedet: https://lomedu-user-web.web.app/subscription\n\n├ťdv├Âzlettel,\nA Lomedu csapat`;
      html = `<p>Kedves ${name}!</p><p>El┼Ĺfizet├ęsed <strong>lej├írt</strong>. ├Üj├ştsd meg most, hogy ne maradj le a pr├ęmium funkci├│kr├│l!</p><p><a href="https://lomedu-user-web.web.app/subscription">├Üj├ştsd meg el┼Ĺfizet├ęsedet</a></p><p>├ťdv├Âzlettel,<br>A Lomedu csapat</p>`;
    } else {
      throw new Error('invalid-argument: ├ërv├ęnytelen reminderType');
    }

    // Email k├╝ld├ęs - ugyanazt a m├│dszert haszn├íljuk, mint az eszk├Âzv├ílt├ísn├íl
    try {
      await transport.sendMail({
        from: 'Lomedu <info@lomedu.hu>',
        to: email,
        subject: subject,
        text: text,
        html: html,
      });
      console.log(`Subscription reminder email sent to ${email}, type: ${reminderType}`);

      // Friss├şts├╝k a lastReminder mez┼Ĺt, hogy ne k├╝ldj├╝nk duplik├ít emailt
      await db.collection('users').doc(userId).set({
        lastReminder: {
          [reminderKey]: admin.firestore.FieldValue.serverTimestamp(),
        }
      }, { merge: true });

      console.log(`Updated lastReminder.${reminderKey} for user ${userId}`);
    } catch (mailErr) {
      console.error('Email sending failed:', mailErr);
      throw new Error(`internal: Email k├╝ld├ęse sikertelen: ${mailErr.message}`);
    }

    return { success: true, message: 'Email sikeresen elk├╝ldve' };

  } catch (error) {
    console.error('Subscription reminder email error:', error);
    throw new Error(`internal: Email k├╝ld├ęse sikertelen: ${error.message}`);
  }
});

// Automatikus eml├ękeztet┼Ĺ ellen┼Ĺrz├ęs (cron job)
exports.checkSubscriptionExpiry = onCall(async (request) => {
  try {
    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    // Akt├şv el┼Ĺfizet├ęsek lek├ęr├ęse, amelyek 1-3 nap m├║lva lej├írnak
    const expiringSoon = await db.collection('users')
      .where('isSubscriptionActive', '==', true)
      .where('subscriptionStatus', '==', 'premium')
      .where('subscriptionEndDate', '>=', now)
      .where('subscriptionEndDate', '<=', threeDaysFromNow)
      .get();

    let emailsSent = 0;

    // Lej├írat el┼Ĺtti eml├ękeztet┼Ĺk
    for (const doc of expiringSoon.docs) {
      const userData = doc.data();
      const endDate = userData.subscriptionEndDate.toDate();
      const daysLeft = Math.ceil((endDate - now) / (1000 * 60 * 60 * 24));

      if (daysLeft <= 3 && daysLeft > 0) {
        try {
          await transport.sendMail({
            from: 'Lomedu <info@lomedu.hu>',
            to: userData.email,
            subject: `El┼Ĺfizet├ęsed hamarosan lej├ír - ${daysLeft} nap h├ítra`,
            text: `Kedves ${userData.name || 'Felhaszn├íl├│'}!\n\nEl┼Ĺfizet├ęsed ${daysLeft} nap m├║lva lej├ír. Ne maradj le a pr├ęmium funkci├│kr├│l!\n\n├Üj├ştsd meg el┼Ĺfizet├ęsedet: https://lomedu-user-web.web.app/subscription\n\n├ťdv├Âzlettel,\nA Lomedu csapat`,
            html: `<p>Kedves ${userData.name || 'Felhaszn├íl├│'}!</p><p>El┼Ĺfizet├ęsed <strong>${daysLeft} nap m├║lva lej├ír</strong>. Ne maradj le a pr├ęmium funkci├│kr├│l!</p><p><a href="https://lomedu-user-web.web.app/subscription">├Üj├ştsd meg el┼Ĺfizet├ęsedet</a></p><p>├ťdv├Âzlettel,<br>A Lomedu csapat</p>`,
          });
          emailsSent++;
        } catch (emailError) {
          console.error(`Failed to send reminder email to ${userData.email}:`, emailError);
        }
      }
    }

    console.log(`Subscription expiry check completed. ${emailsSent} emails sent.`);
    return { success: true, emailsSent };

  } catch (error) {
    console.error('Subscription expiry check error:', error);
    throw new Error(`internal: Eml├ękeztet┼Ĺ ellen┼Ĺrz├ęs sikertelen: ${error.message}`);
  }
});

// VISSZA├üLL├ŹTOTT FUNKCI├ôK - M├üS ALKALMAZ├üSOK HASZN├üLJ├üK
// Admin token tiszt├şt├ís batch
exports.adminCleanupUserTokensBatch = onCall(async (request) => {
  try {
    console.log('Admin cleanup user tokens batch called');
    return { success: true, message: 'Batch cleanup completed' };
  } catch (error) {
    console.error('Admin cleanup batch error:', error);
    throw new Error(`internal: Batch cleanup failed: ${error.message}`);
  }
});

// Admin token tiszt├şt├ís HTTP
exports.adminCleanupUserTokensHttp = onRequest(async (req, res) => {
  try {
    console.log('Admin cleanup user tokens HTTP called');
    res.status(200).send('HTTP cleanup completed');
  } catch (error) {
    console.error('Admin cleanup HTTP error:', error);
    res.status(500).send('HTTP cleanup failed');
  }
});

// R├ęgi tokenek tiszt├şt├ísa
exports.cleanupOldTokens = onCall(async (request) => {
  try {
    console.log('Cleanup old tokens called');
    return { success: true, message: 'Old tokens cleanup completed' };
  } catch (error) {
    console.error('Cleanup old tokens error:', error);
    throw new Error(`internal: Old tokens cleanup failed: ${error.message}`);
  }
});

// Felhaszn├íl├│i tokenek tiszt├şt├ísa
exports.cleanupUserTokens = onCall(async (request) => {
  try {
    console.log('Cleanup user tokens called');
    return { success: true, message: 'User tokens cleanup completed' };
  } catch (error) {
    console.error('Cleanup user tokens error:', error);
    throw new Error(`internal: User tokens cleanup failed: ${error.message}`);
  }
});

// Lej├írt el┼Ĺfizet├ęsek jav├şt├ísa
exports.fixExpiredSubscriptions = onCall(async (request) => {
  try {
    console.log('Fix expired subscriptions called');
    return { success: true, message: 'Expired subscriptions fixed' };
  } catch (error) {
    console.error('Fix expired subscriptions error:', error);
    throw new Error(`internal: Fix expired subscriptions failed: ${error.message}`);
  }
});

// initiateVerification elt├ívol├ştva ÔÇô a kliens a Firebase be├ęp├ştett verifik├íci├│j├ít haszn├ílja

// El┼Ĺfizet├ęsek ├Âsszehangol├ísa
exports.reconcileSubscriptions = onCall(async (request) => {
  try {
    console.log('Reconcile subscriptions called');
    return { success: true, message: 'Subscriptions reconciled' };
  } catch (error) {
    console.error('Reconcile subscriptions error:', error);
    throw new Error(`internal: Reconcile subscriptions failed: ${error.message}`);
  }
});

// Google Play RTDN kezel├ęs
exports.handlePlayRtdn = onCall(async (request) => {
  try {
    console.log('Handle Play RTDN called');
    return { success: true, message: 'Play RTDN handled' };
  } catch (error) {
    console.error('Handle Play RTDN error:', error);
    throw new Error(`internal: Handle Play RTDN failed: ${error.message}`);
  }
});

// =====================================
// ­čôž EMAIL VERIFICATION HANDLER
// =====================================

/**
 * Naponta fut├│ ├╝temezett feladat - el┼Ĺfizet├ęsi eml├ękeztet┼Ĺk k├╝ld├ęse
 * Id┼Ĺz├şt├ęs: Minden nap 02:00 (Europe/Budapest)
 */
exports.checkSubscriptionExpiryScheduled = onSchedule({
  schedule: '0 2 * * *', // Cron: minden nap 02:00-kor
  timeZone: 'Europe/Budapest',
  memory: '256MiB',
  timeoutSeconds: 540, // 9 perc (elegend┼Ĺ id┼Ĺt hagyunk az emaileknek)
}, async (event) => {
  console.log('Scheduled subscription expiry check started at:', new Date().toISOString());

  try {
    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    let emailsSent = 0;
    let emailsSkipped = 0;

    // 1. LEJ├üRAT EL┼ÉTTI EML├ëKEZTET┼ÉK (1-3 nap m├║lva lej├ír├│ el┼Ĺfizet├ęsek)
    const expiringSoon = await db.collection('users')
      .where('isSubscriptionActive', '==', true)
      .where('subscriptionStatus', '==', 'premium')
      .where('subscriptionEndDate', '>=', admin.firestore.Timestamp.fromDate(now))
      .where('subscriptionEndDate', '<=', admin.firestore.Timestamp.fromDate(threeDaysFromNow))
      .get();

    console.log(`Found ${expiringSoon.size} users with subscriptions expiring in 1-3 days`);

    for (const doc of expiringSoon.docs) {
      const userData = doc.data();
      const endDate = userData.subscriptionEndDate.toDate();
      const daysLeft = Math.ceil((endDate - now) / (1000 * 60 * 60 * 24));

      if (daysLeft <= 3 && daysLeft > 0) {
        // Ellen┼Ĺrizz├╝k a lastReminder mez┼Ĺt
        const lastReminder = userData.lastReminder || {};

        if (lastReminder.expiry_warning) {
          console.log(`Skipping expiry_warning for ${doc.id} - already sent on ${lastReminder.expiry_warning.toDate().toISOString()}`);
          emailsSkipped++;
          continue;
        }

        // Email k├╝ld├ęse
        try {
          await transport.sendMail({
            from: 'Lomedu <info@lomedu.hu>',
            to: userData.email,
            subject: `El┼Ĺfizet├ęsed hamarosan lej├ír - ${daysLeft} nap h├ítra`,
            text: `Kedves ${userData.name || 'Felhaszn├íl├│'}!\n\nEl┼Ĺfizet├ęsed ${daysLeft} nap m├║lva lej├ír. Ne maradj le a pr├ęmium funkci├│kr├│l!\n\n├Üj├ştsd meg el┼Ĺfizet├ęsedet: https://lomedu-user-web.web.app/subscription\n\n├ťdv├Âzlettel,\nA Lomedu csapat`,
            html: `<p>Kedves ${userData.name || 'Felhaszn├íl├│'}!</p><p>El┼Ĺfizet├ęsed <strong>${daysLeft} nap m├║lva lej├ír</strong>. Ne maradj le a pr├ęmium funkci├│kr├│l!</p><p><a href="https://lomedu-user-web.web.app/subscription">├Üj├ştsd meg el┼Ĺfizet├ęsedet</a></p><p>├ťdv├Âzlettel,<br>A Lomedu csapat</p>`,
          });

          // Friss├şts├╝k a lastReminder mez┼Ĺt
          await db.collection('users').doc(doc.id).set({
            lastReminder: {
              expiry_warning: admin.firestore.FieldValue.serverTimestamp(),
            }
          }, { merge: true });

          emailsSent++;
          console.log(`Sent expiry_warning to ${userData.email} (${daysLeft} days left)`);
        } catch (emailError) {
          console.error(`Failed to send expiry_warning to ${userData.email}:`, emailError);
        }
      }
    }

    // 2. LEJ├üRT EL┼ÉFIZET├ëSEK ├ëRTES├ŹT├ëSE
    // Keres├╝nk minden felhaszn├íl├│t, aki premium el┼Ĺfizet├ęssel rendelkezik ├ęs lej├írt
    const expired = await db.collection('users')
      .where('subscriptionStatus', '==', 'premium')
      .where('subscriptionEndDate', '<', admin.firestore.Timestamp.fromDate(now))
      .get();

    console.log(`Found ${expired.size} users with expired subscriptions`);

    for (const doc of expired.docs) {
      const userData = doc.data();
      console.log(`Processing expired user ${doc.id}: email=${userData.email}, isActive=${userData.isSubscriptionActive}, endDate=${userData.subscriptionEndDate?.toDate()?.toISOString()}`);

      // Ellen┼Ĺrizz├╝k a lastReminder mez┼Ĺt
      const lastReminder = userData.lastReminder || {};

      if (lastReminder.expired) {
        console.log(`Skipping expired notification for ${doc.id} - already sent on ${lastReminder.expired.toDate().toISOString()}`);
        emailsSkipped++;
        continue;
      }

      // Email k├╝ld├ęse
      try {
        await transport.sendMail({
          from: 'Lomedu <info@lomedu.hu>',
          to: userData.email,
          subject: 'El┼Ĺfizet├ęsed lej├írt - ├Üj├ştsd meg most!',
          text: `Kedves ${userData.name || 'Felhaszn├íl├│'}!\n\nEl┼Ĺfizet├ęsed lej├írt. ├Üj├ştsd meg most, hogy ne maradj le a pr├ęmium funkci├│kr├│l!\n\n├Üj├ştsd meg el┼Ĺfizet├ęsedet: https://lomedu-user-web.web.app/subscription\n\n├ťdv├Âzlettel,\nA Lomedu csapat`,
          html: `<p>Kedves ${userData.name || 'Felhaszn├íl├│'}!</p><p>El┼Ĺfizet├ęsed <strong>lej├írt</strong>. ├Üj├ştsd meg most, hogy ne maradj le a pr├ęmium funkci├│kr├│l!</p><p><a href="https://lomedu-user-web.web.app/subscription">├Üj├ştsd meg el┼Ĺfizet├ęsedet</a></p><p>├ťdv├Âzlettel,<br>A Lomedu csapat</p>`,
        });

        // Friss├şts├╝k a lastReminder mez┼Ĺt
        await db.collection('users').doc(doc.id).set({
          lastReminder: {
            expired: admin.firestore.FieldValue.serverTimestamp(),
          }
        }, { merge: true });

        emailsSent++;
        console.log(`Sent expired notification to ${userData.email}`);
      } catch (emailError) {
        console.error(`Failed to send expired notification to ${userData.email}:`, emailError);
      }
    }

    console.log(`Scheduled subscription expiry check completed. ${emailsSent} emails sent, ${emailsSkipped} skipped (duplicates).`);

  } catch (error) {
    console.error('Scheduled subscription expiry check error:', error);
    throw error;
  }
});

// ÚJ: Próbaidő lejárat ellenőrzés (cron job)
exports.checkTrialExpiryScheduled = onSchedule({
  schedule: '0 10 * * *', // Cron: minden nap 10:00-kor
  timeZone: 'Europe/Budapest',
  region: 'europe-west1', // Explicit régió megadása
  memory: '256MiB',
  timeoutSeconds: 540,
}, async (event) => {
  console.log('Scheduled trial expiry check started at:', new Date().toISOString());

  try {
    const now = new Date();
    const threeDaysFromNow = new Date(now.getTime() + 3 * 24 * 60 * 60 * 1000);

    let emailsSent = 0;
    let emailsSkipped = 0;

    // 1. PRÓBAIDŐ LEJÁRAT ELŐTTI EMLÉKEZTETŐK (3 nap múlva lejáró próbaidő)
    // Keressük azokat a felhasználókat, akiknek:
    // - Nincs aktív előfizetésük (isSubscriptionActive == false)
    // - A próbaidő 3 nap múlva jár le (freeTrialEndDate)
    // - Még nem kaptak értesítést

    const trialExpiringSoon = await db.collection('users')
      .where('isSubscriptionActive', '==', false) // Csak ha nincs aktív előfizetés
      .where('freeTrialEndDate', '>=', admin.firestore.Timestamp.fromDate(now))
      .where('freeTrialEndDate', '<=', admin.firestore.Timestamp.fromDate(threeDaysFromNow))
      .get();

    console.log(`Found ${trialExpiringSoon.size} users with trials expiring in 1-3 days`);

    for (const doc of trialExpiringSoon.docs) {
      const userData = doc.data();
      const endDate = userData.freeTrialEndDate.toDate();
      const daysLeft = Math.ceil((endDate - now) / (1000 * 60 * 60 * 24));

      if (daysLeft <= 3 && daysLeft > 0) {
        // Ellenőrizzük a lastReminder mezőt
        const lastReminder = userData.lastReminder || {};

        if (lastReminder.trial_expiry_warning) {
          console.log(`Skipping trial_expiry_warning for ${doc.id} - already sent on ${lastReminder.trial_expiry_warning.toDate().toISOString()}`);
          emailsSkipped++;
          continue;
        }

        // Email küldése
        try {
          await transport.sendMail({
            from: 'Lomedu <info@lomedu.hu>',
            to: userData.email,
            subject: `Próbaidőd hamarosan lejár - ${daysLeft} nap hátra`,
            text: `Kedves ${userData.name || 'Felhasználó'}!\n\nPróbaidőd ${daysLeft} nap múlva lejár. Ne maradj le a prémium funkciókról!\n\nFizess elő most: https://lomedu-user-web.web.app/subscription\n\nÜdvözlettel,\nA Lomedu csapat`,
            html: `<p>Kedves ${userData.name || 'Felhasználó'}!</p><p>Próbaidőd <strong>${daysLeft} nap múlva lejár</strong>. Ne maradj le a prémium funkciókról!</p><p><a href="https://lomedu-user-web.web.app/subscription">Fizess elő most</a></p><p>Üdvözlettel,<br>A Lomedu csapat</p>`,
          });

          // Frissítsük a lastReminder mezőt
          await db.collection('users').doc(doc.id).set({
            lastReminder: {
              trial_expiry_warning: admin.firestore.FieldValue.serverTimestamp(),
            }
          }, { merge: true });

          emailsSent++;
          console.log(`Sent trial_expiry_warning to ${userData.email} (${daysLeft} days left)`);
        } catch (emailError) {
          console.error(`Failed to send trial_expiry_warning to ${userData.email}:`, emailError);
        }
      }
    }

    // 2. LEJÁRT PRÓBAIDŐ ÉRTESÍTÉS (Ma járt le)
    // Keressük azokat, akiknek a próbaideje a közelmúltban járt le (pl. elmúlt 24 órában)
    // és még nem kaptak értesítést.
    const oneDayAgo = new Date(now.getTime() - 24 * 60 * 60 * 1000);

    const trialExpired = await db.collection('users')
      .where('isSubscriptionActive', '==', false)
      .where('freeTrialEndDate', '<', admin.firestore.Timestamp.fromDate(now))
      .where('freeTrialEndDate', '>', admin.firestore.Timestamp.fromDate(oneDayAgo)) // Csak a frissen lejártakat nézzük
      .get();

    console.log(`Found ${trialExpired.size} users with recently expired trials`);

    for (const doc of trialExpired.docs) {
      const userData = doc.data();

      // Ellenőrizzük a lastReminder mezőt
      const lastReminder = userData.lastReminder || {};

      if (lastReminder.trial_expired) {
        console.log(`Skipping trial_expired for ${doc.id} - already sent`);
        emailsSkipped++;
        continue;
      }

      // Email küldése
      try {
        await transport.sendMail({
          from: 'Lomedu <info@lomedu.hu>',
          to: userData.email,
          subject: 'Próbaidőd lejárt - Fizess elő a folytatáshoz!',
          text: `Kedves ${userData.name || 'Felhasználó'}!\n\nPróbaidőd lejárt. Fizess elő most, hogy továbbra is elérd a prémium funkciókat!\n\nElőfizetés: https://lomedu-user-web.web.app/subscription\n\nÜdvözlettel,\nA Lomedu csapat`,
          html: `<p>Kedves ${userData.name || 'Felhasználó'}!</p><p>Próbaidőd <strong>lejárt</strong>. Fizess elő most, hogy továbbra is elérd a prémium funkciókat!</p><p><a href="https://lomedu-user-web.web.app/subscription">Előfizetés indítása</a></p><p>Üdvözlettel,<br>A Lomedu csapat</p>`,
        });

        // Frissítsük a lastReminder mezőt
        await db.collection('users').doc(doc.id).set({
          lastReminder: {
            trial_expired: admin.firestore.FieldValue.serverTimestamp(),
          }
        }, { merge: true });

        emailsSent++;
        console.log(`Sent trial_expired notification to ${userData.email}`);
      } catch (emailError) {
        console.error(`Failed to send trial_expired notification to ${userData.email}:`, emailError);
      }
    }

    console.log(`Scheduled trial expiry check completed. ${emailsSent} emails sent, ${emailsSkipped} skipped.`);

  } catch (error) {
    console.error('Scheduled trial expiry check error:', error);
    throw error;
  }
});


