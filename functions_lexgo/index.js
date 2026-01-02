const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { onSchedule } = require('firebase-functions/v2/scheduler');
const { setGlobalOptions } = require('firebase-functions/v2');
const admin = require('firebase-admin');
const crypto = require('crypto');

const { PAYMENT_PLANS, CANONICAL_PLAN_ID } = require('./payment_plans_lexgo');

admin.initializeApp();
setGlobalOptions({ region: 'europe-west1', cpu: 1 });

const db = admin.firestore();

function getSimplePayConfig() {
  const env = (process.env.SIMPLEPAY_ENV || 'sandbox').toLowerCase().trim();
  return {
    merchantId: (process.env.SIMPLEPAY_MERCHANT_ID || '').trim(),
    secretKey: (process.env.SIMPLEPAY_SECRET_KEY || '').trim(),
    baseUrl:
      env === 'production'
        ? 'https://secure.simplepay.hu/payment/v2/'
        : 'https://sandbox.simplepay.hu/payment/v2/',
    nextAuthUrl: (process.env.NEXTAUTH_URL || '').trim(),
    allowedReturnBases: (process.env.RETURN_BASES || process.env.NEXTAUTH_URL || '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
    env,
  };
}

/**
 * LexGO: Webes fizetés indítása SimplePay v2 API-val.
 *
 * IMPORTANT:
 * - New function name so legacy app calling `initiateWebPayment` is unaffected.
 * - Uses LexGO plan names (LexGO 30 day open) in the SimplePay item title.
 */
exports.initiateWebPaymentLexgo = onCall(
  {
    // NOTE: keep secrets list minimal; missing Secret Manager entries will fail deploy.
    // RETURN_BASES is optional, we fall back to NEXTAUTH_URL if not set.
    secrets: ['SIMPLEPAY_MERCHANT_ID', 'SIMPLEPAY_SECRET_KEY', 'NEXTAUTH_URL', 'SIMPLEPAY_ENV', 'RETURN_BASES'],
  },
  async (request) => {
    try {
      const SIMPLEPAY_CONFIG = getSimplePayConfig();
      const { planId, userId } = request.data || {};
      console.log('[initiateWebPaymentLexgo] input', { planId, userId });

      if (!planId || !userId) {
        throw new HttpsError('invalid-argument', 'planId és userId szükséges');
      }

      const canonicalPlanId = CANONICAL_PLAN_ID[planId] || planId;
      const plan = PAYMENT_PLANS[canonicalPlanId];
      if (!plan) {
        throw new HttpsError('invalid-argument', 'Érvénytelen csomag');
      }

      if (!SIMPLEPAY_CONFIG.merchantId || !SIMPLEPAY_CONFIG.secretKey || !SIMPLEPAY_CONFIG.baseUrl) {
        throw new HttpsError('failed-precondition', 'SimplePay konfiguráció hiányzik');
      }

      const userDoc = await db.collection('users').doc(userId).get();
      if (!userDoc.exists) {
        throw new HttpsError('not-found', 'Felhasználó nem található');
      }
      const userData = userDoc.data() || {};

      // Admin discount parity with legacy: admin pays 5 HUF.
      const isAdmin = userData.isAdmin === true || userData.email === 'tattila.ninox@gmail.com';
      const finalPrice = isAdmin ? 5 : plan.price;

      // Server-side check: data transfer consent required.
      if (!userData.dataTransferConsentLastAcceptedDate) {
        throw new HttpsError(
          'failed-precondition',
          'Az adattovábbítási nyilatkozat elfogadása szükséges a fizetés indításához.'
        );
      }

      const email = userData.email;
      if (!email) {
        throw new HttpsError('failed-precondition', 'A felhasználóhoz nem tartozik email cím');
      }

      // NOTE: legacy backend flows expect orderRef to start with `WEB_` in multiple places
      // (callback/confirm/webhook parsing). We keep this prefix for compatibility, while the
      // callable function name itself is LexGO-specific.
      const orderRef = `WEB_${userId}_${Date.now()}`;

      const returnBase =
        SIMPLEPAY_CONFIG.allowedReturnBases && SIMPLEPAY_CONFIG.allowedReturnBases.length > 0
          ? SIMPLEPAY_CONFIG.allowedReturnBases[0]
          : SIMPLEPAY_CONFIG.nextAuthUrl;
      const nextAuthBase = (returnBase || '').replace(/\/$/, '');

      const projectId = process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT || '';
      const webhookUrl = `https://europe-west1-${projectId}.cloudfunctions.net/simplepayWebhookLexgo`;

      const timeout = new Date(Date.now() + 30 * 60 * 1000)
        .toISOString()
        .replace(/\.\d{3}Z$/, 'Z');

      const simplePayRequest = {
        salt: crypto.randomBytes(16).toString('hex'),
        merchant: SIMPLEPAY_CONFIG.merchantId.trim(),
        orderRef,
        customerEmail: email,
        language: 'HU',
        sdkVersion: 'LexGO_Functions_v1',
        currency: 'HUF',
        timeout,
        methods: ['CARD'],
        url: webhookUrl,
        urls: {
          success: `${nextAuthBase}/account?payment=success&orderRef=${orderRef}`,
          fail: `${nextAuthBase}/account?payment=fail&orderRef=${orderRef}`,
          timeout: `${nextAuthBase}/account?payment=timeout&orderRef=${orderRef}`,
          cancel: `${nextAuthBase}/account?payment=cancelled&orderRef=${orderRef}`,
        },
        items: [
          {
            ref: canonicalPlanId,
            title: plan.name,
            description: plan.description,
            amount: 1,
            price: finalPrice,
          },
        ],
      };

      const requestBody = JSON.stringify(simplePayRequest);
      const signature = crypto
        .createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim())
        .update(requestBody)
        .digest('base64');

      const response = await fetch(`${SIMPLEPAY_CONFIG.baseUrl.trim()}start`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          Signature: signature,
        },
        body: requestBody,
      });

      if (!response.ok) {
        const errorText = await response.text();
        console.error('[initiateWebPaymentLexgo] SimplePay HTTP error', { status: response.status, errorText, orderRef });
        throw new HttpsError('internal', 'Fizetési szolgáltató API hiba');
      }

      const paymentData = await response.json();
      if (!paymentData?.paymentUrl) {
        console.error('[initiateWebPaymentLexgo] SimplePay missing paymentUrl', { orderRef, paymentData });
        throw new HttpsError('failed-precondition', 'SimplePay hiba: paymentUrl hiányzik');
      }

      // Store into same collection as legacy, but different orderRef prefix.
      await db.collection('web_payments').doc(orderRef).set({
        userId,
        planId: canonicalPlanId,
        orderRef,
        source: 'lexgo',
        simplePayTransactionId: paymentData.transactionId || null,
        amount: finalPrice,
        status: 'INITIATED',
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      return {
        success: true,
        paymentUrl: paymentData.paymentUrl,
        orderRef,
        amount: finalPrice,
      };
    } catch (error) {
      console.error('[initiateWebPaymentLexgo] error', { message: error?.message, stack: error?.stack });
      if (error instanceof HttpsError) throw error;
      throw new HttpsError('internal', error?.message || 'Ismeretlen szerverhiba');
    }
  }
);



/**
 * Ütemezett függvény (óránként), ami frissíti az aktív metaadatokat.
 * Cél: A kliens oldali szűrés (N+1 query) kiváltása egyetlen olvasásra.
 * Skálázható megoldás 6000+ felhasználóhoz.
 */
exports.maintainActiveMetadata = onSchedule('every 60 minutes', async (event) => {
  console.log('Starting maintainActiveMetadata...');
  const science = 'Jogász'; // Jelenleg fix, később paraméterezhető

  // 1. Gyűjtés a 3 fő kollekcióból
  // Csak a 'Published' és 'Public' státuszúakat vesszük figyelembe a felhasználók számára
  const collections = ['notes', 'jogesetek', 'memoriapalota_allomasok'];
  const activeCategories = new Set();
  const activeTags = new Set();
  let totalDocsProcessed = 0;

  try {
    for (const collName of collections) {

      const snapshot = await db.collection(collName)
        .where('science', '==', science)
        .where('status', 'in', ['Published', 'Public'])
        .get();

      totalDocsProcessed += snapshot.size;

      snapshot.forEach(doc => {
        const data = doc.data();
        if (data.category && typeof data.category === 'string' && data.category.trim() !== '') {
          activeCategories.add(data.category);
        }
        if (data.tags && Array.isArray(data.tags)) {
          data.tags.forEach(tag => {
            if (tag && typeof tag === 'string' && tag.trim() !== '') {
              activeTags.add(tag);
            }
          });
        }
      });
    }

    // 2. Mentés aggregált dokumentumba
    // A dokumentum ID legyen 'jogasz_active', így a kliens könnyen megtalálja
    const outputDocId = 'jogasz_active';
    const categoriesList = Array.from(activeCategories).sort();
    const tagsList = Array.from(activeTags).sort();

    await db.collection('metadata').doc(outputDocId).set({
      categories: categoriesList,
      tags: tagsList,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      docsProcessed: totalDocsProcessed,
      source: 'cloud_function_maintainActiveMetadata'
    });

    console.log(`Updated active metadata (jogasz_active). Processed ${totalDocsProcessed} docs.`);
    console.log(`Active Categories: ${categoriesList.length}, Active Tags: ${tagsList.length}`);
    return null;
  } catch (error) {
    console.error('Error in maintainActiveMetadata:', error);
    return null;
  }
});

// ============================================================================
// LEXGO PREMIUM CLAIMS HELPER
// ============================================================================

/**
 * Helper: Custom Claims beállítása a Firebase Auth tokenben.
 * Ezáltal a Firestore rules 0 extra read-del tudja ellenőrizni a prémium státuszt.
 */
async function setPremiumClaims(userId, expiryDate) {
  try {
    await admin.auth().setCustomUserClaims(userId, {
      premium: true,
      premiumUntil: expiryDate.getTime(),
    });
    console.log(`[LexGO] Premium claims set for user ${userId}, expires: ${expiryDate.toISOString()}`);
  } catch (error) {
    console.error(`[LexGO] Failed to set premium claims for ${userId}:`, error);
    // Ne dobjunk hibát, a Firestore fallback működni fog
  }
}

/**
 * Helper: Custom Claims törlése (előfizetés lejáratakor).
 */
async function clearPremiumClaims(userId) {
  try {
    await admin.auth().setCustomUserClaims(userId, {
      premium: false,
      premiumUntil: null,
    });
    console.log(`[LexGO] Premium claims cleared for user ${userId}`);
  } catch (error) {
    console.error(`[LexGO] Failed to clear premium claims for ${userId}:`, error);
  }
}

// ============================================================================
// ADMIN ONLY: TESZT FUNKCIÓ CUSTOM CLAIMS BEÁLLÍTÁSÁHOZ
// ============================================================================

/**
 * Admin-only: Custom Claims beállítása teszteléshez.
 * Csak a tattila.ninox@gmail.com email címről hívható.
 * 
 * Input: { targetUserId, action: 'set' | 'clear', days?: number }
 */
exports.adminSetPremiumClaimsLexgo = onCall(async (request) => {
  // Admin ellenőrzés
  const callerEmail = request.auth?.token?.email;
  if (callerEmail !== 'tattila.ninox@gmail.com') {
    throw new HttpsError('permission-denied', 'Csak admin használhatja ezt a funkciót');
  }

  const { targetUserId, action, days } = request.data || {};

  if (!targetUserId) {
    throw new HttpsError('invalid-argument', 'targetUserId szükséges');
  }

  if (action === 'set') {
    const daysToAdd = days || 30;
    const expiryDate = new Date(Date.now() + daysToAdd * 24 * 60 * 60 * 1000);
    await setPremiumClaims(targetUserId, expiryDate);

    return {
      success: true,
      action: 'set',
      targetUserId,
      premiumUntil: expiryDate.toISOString(),
      message: `Custom Claims beállítva ${daysToAdd} napra`
    };
  } else if (action === 'clear') {
    await clearPremiumClaims(targetUserId);

    return {
      success: true,
      action: 'clear',
      targetUserId,
      message: 'Custom Claims törölve'
    };
  } else {
    throw new HttpsError('invalid-argument', 'action: "set" vagy "clear" szükséges');
  }
});

// ============================================================================
// LEXGO PAYMENT CONFIRMATION (kliens hívja sikeres fizetés után)
// ============================================================================

/**
 * Fizetés lezárása (CONFIRM) SimplePay v2 API-val - LexGO verzió.
 * - Client a sikeres visszairányítás után hívja: { orderRef }
 * - Siker esetén users/{uid} frissül, web_payments status COMPLETED-re vált
 * - Custom Claims beállítása a tokenben
 */
exports.confirmWebPaymentLexgo = onCall(
  {
    secrets: ['SIMPLEPAY_MERCHANT_ID', 'SIMPLEPAY_SECRET_KEY', 'SIMPLEPAY_ENV'],
  },
  async (request) => {
    try {
      const SIMPLEPAY_CONFIG = getSimplePayConfig();
      const { orderRef } = request.data || {};

      if (!orderRef || typeof orderRef !== 'string') {
        throw new HttpsError('invalid-argument', 'orderRef szükséges');
      }

      const orderRefParts = orderRef.split('_');
      if (orderRefParts.length < 3 || orderRefParts[0] !== 'WEB') {
        throw new HttpsError('invalid-argument', 'Érvénytelen orderRef formátum');
      }
      const userId = orderRefParts[1];

      if (!SIMPLEPAY_CONFIG.merchantId || !SIMPLEPAY_CONFIG.secretKey) {
        throw new HttpsError('failed-precondition', 'SimplePay konfiguráció hiányzik');
      }

      // Lekérjük a fizetési rekordot
      const paymentRef = db.collection('web_payments').doc(orderRef);
      const paymentSnap = await paymentRef.get();
      if (!paymentSnap.exists) {
        throw new HttpsError('not-found', 'Fizetési rekord nem található');
      }

      const pay = paymentSnap.data();

      // Ellenőrizzük, hogy LexGO fizetés-e
      if (pay.source !== 'lexgo') {
        throw new HttpsError('failed-precondition', 'Ez nem LexGO fizetés');
      }

      const rawPlanId = pay.planId;
      const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
      const plan = PAYMENT_PLANS[canonicalPlanId];
      if (!plan) {
        throw new HttpsError('failed-precondition', 'Érvénytelen csomag');
      }

      // QUERY – ellenőrzés SimplePay v2 API-val
      const queryPayload = {
        salt: crypto.randomBytes(16).toString('hex'),
        merchant: SIMPLEPAY_CONFIG.merchantId.trim(),
        orderRef,
      };
      const queryBody = JSON.stringify(queryPayload);
      const querySig = crypto
        .createHmac('sha384', SIMPLEPAY_CONFIG.secretKey.trim())
        .update(queryBody)
        .digest('base64');

      const queryResp = await fetch(`${SIMPLEPAY_CONFIG.baseUrl.trim()}query`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json; charset=utf-8',
          Signature: querySig,
        },
        body: queryBody,
      });

      if (!queryResp.ok) {
        const txt = await queryResp.text();
        console.error('[confirmWebPaymentLexgo] query HTTP error', { status: queryResp.status, txt });
        throw new HttpsError('internal', 'Query hívás sikertelen');
      }

      const queryTxt = await queryResp.text();
      let queryData;
      try {
        queryData = JSON.parse(queryTxt);
      } catch (_) {
        queryData = { raw: queryTxt };
      }

      const successLike =
        (queryData?.status || '').toString().toUpperCase() === 'SUCCESS' ||
        !!queryData?.transactionId;

      if (!successLike) {
        console.warn('[confirmWebPaymentLexgo] query not SUCCESS', { orderRef, queryData });
        return { success: false, status: queryData?.status || 'UNKNOWN' };
      }

      const transactionId = queryData?.transactionId || pay.simplePayTransactionId || null;
      const orderId = queryData?.orderId || null;

      // Előfizetés aktiválása
      const now = new Date();
      const expiryDate = new Date(now.getTime() + plan.subscriptionDays * 24 * 60 * 60 * 1000);

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
          source: 'lexgo_simplepay',
        },
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        // Próbaidőszak lezárása az első fizetéskor
        freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
      };

      await db.collection('users').doc(userId).set(subscriptionData, { merge: true });
      await db.collection('users').doc(userId).update({
        lastReminder: admin.firestore.FieldValue.delete(),
      });

      // Custom Claims beállítása (0 extra read a rules-ban)
      await setPremiumClaims(userId, expiryDate);

      await paymentRef.update({
        status: 'COMPLETED',
        transactionId,
        orderId,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log('[confirmWebPaymentLexgo] completed', { userId, orderRef });
      return { success: true, status: 'COMPLETED' };
    } catch (err) {
      console.error('[confirmWebPaymentLexgo] error', { message: err?.message, stack: err?.stack });
      if (err instanceof HttpsError) throw err;
      throw new HttpsError('internal', err?.message || 'Ismeretlen hiba');
    }
  }
);

// ============================================================================
// LEXGO SIMPLEPAY WEBHOOK (SimplePay server-to-server hívja)
// ============================================================================

const { onRequest } = require('firebase-functions/v2/https');

/**
 * HTTP webhook endpoint SimplePay számára - LexGO verzió.
 * Custom Claims beállítással.
 */
exports.simplepayWebhookLexgo = onRequest(
  {
    secrets: ['SIMPLEPAY_SECRET_KEY', 'NEXTAUTH_URL', 'SIMPLEPAY_ENV'],
    region: 'europe-west1',
  },
  async (req, res) => {
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
        console.error('[simplepayWebhookLexgo] Missing signature');
        res.status(400).send('Missing signature');
        return;
      }

      // Aláírás ellenőrzése
      if (!SIMPLEPAY_CONFIG.secretKey) {
        console.error('[simplepayWebhookLexgo] Secret key not configured');
        res.status(500).send('Configuration error');
        return;
      }

      const raw = Buffer.isBuffer(req.rawBody)
        ? req.rawBody
        : Buffer.from(JSON.stringify(body));

      const expectedSig = crypto
        .createHmac('sha384', SIMPLEPAY_CONFIG.secretKey)
        .update(raw)
        .digest('base64');

      const a = Buffer.from(headerSignature);
      const b = Buffer.from(expectedSig);
      const valid = a.length === b.length && crypto.timingSafeEqual(a, b);

      if (!valid) {
        console.error('[simplepayWebhookLexgo] Invalid signature');
        res.status(401).send('Invalid signature');
        return;
      }

      const incomingStatus = (body?.status || '').toString().toUpperCase();
      console.log('[simplepayWebhookLexgo] received', {
        status: incomingStatus,
        orderRef: body?.orderRef,
      });

      // Csak sikeres fizetéseket dolgozunk fel
      if (incomingStatus !== 'SUCCESS' && incomingStatus !== 'FINISHED') {
        console.log('[simplepayWebhookLexgo] non-success status, ignoring');
        res.status(200).send('OK');
        return;
      }

      const { orderRef, transactionId, orderId } = body;

      // Felhasználó azonosítása az orderRef-ből
      const orderRefParts = orderRef.split('_');
      if (orderRefParts.length < 3 || orderRefParts[0] !== 'WEB') {
        console.error('[simplepayWebhookLexgo] Invalid orderRef format:', orderRef);
        res.status(400).send('Invalid order reference');
        return;
      }

      const userId = orderRefParts[1];

      // Fizetési rekord lekérése
      const paymentRef = db.collection('web_payments').doc(orderRef);
      const paymentDoc = await paymentRef.get();

      if (!paymentDoc.exists) {
        console.error('[simplepayWebhookLexgo] Payment record not found', { orderRef });
        res.status(404).send('Payment record not found');
        return;
      }

      const paymentData = paymentDoc.data();

      // Ellenőrizzük, hogy LexGO fizetés-e
      if (paymentData.source !== 'lexgo') {
        console.log('[simplepayWebhookLexgo] Not a LexGO payment, ignoring', { orderRef });
        res.status(200).send('OK - not LexGO');
        return;
      }

      const rawPlanId = paymentData.planId;
      const canonicalPlanId = CANONICAL_PLAN_ID[rawPlanId] || rawPlanId;
      const plan = PAYMENT_PLANS[canonicalPlanId];

      if (!plan) {
        console.error('[simplepayWebhookLexgo] Invalid plan', { planId: rawPlanId });
        res.status(400).send('Invalid plan');
        return;
      }

      // Előfizetés aktiválása
      const now = new Date();
      const expiryDate = new Date(now.getTime() + plan.subscriptionDays * 24 * 60 * 60 * 1000);

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
          source: 'lexgo_simplepay',
        },
        lastPaymentDate: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        freeTrialEndDate: admin.firestore.Timestamp.fromDate(now),
      };

      // Felhasználói dokumentum frissítése
      await db.collection('users').doc(userId).set(subscriptionData, { merge: true });
      await db.collection('users').doc(userId).update({
        lastReminder: admin.firestore.FieldValue.delete(),
      });

      // Custom Claims beállítása (0 extra read a rules-ban)
      await setPremiumClaims(userId, expiryDate);

      // Fizetési rekord frissítése
      await paymentRef.update({
        status: 'COMPLETED',
        transactionId: transactionId || null,
        orderId: orderId || null,
        completedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      console.log('[simplepayWebhookLexgo] completed', { userId, orderRef });
      res.status(200).send('OK');
    } catch (error) {
      console.error('[simplepayWebhookLexgo] error', { message: error?.message, stack: error?.stack });
      res.status(500).send('Internal error');
    }
  }
);
