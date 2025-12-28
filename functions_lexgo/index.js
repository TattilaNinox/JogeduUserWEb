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
      const webhookUrl = `https://europe-west1-${projectId}.cloudfunctions.net/simplepayWebhook`;

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
