/**
 * Invoice Data Builder
 * 
 * Számla adatok összeállítása user, payment és shipping address adatokból
 * Szamlazz.hu XML formátumhoz
 */

/**
 * Számla adatok összeállítása
 * 
 * @param {Object} params
 * @param {Object} params.userData - Felhasználó adatok Firestore-ból
 * @param {Object} params.shippingAddress - Szállítási cím (temporary, payment record-ból)
 * @param {Object} params.paymentData - Fizetési adatok
 * @param {Object} params.plan - Előfizetési csomag adatok
 * @returns {Object} - Számla adatok Szamlazz.hu formátumban
 */
const SELLER_CONFIG = {
  bankName: process.env.SELLER_BANK_NAME || null,
  bankAccountNumber: process.env.SELLER_BANK_ACCOUNT || null,
  emailReplyTo: process.env.SELLER_EMAIL || 'support@lomedu.hu',
  emailSubject:
    process.env.SELLER_EMAIL_SUBJECT || 'Számla értesítő - Lomedu',
  emailContent:
    process.env.SELLER_EMAIL_CONTENT ||
    'Köszönjük a vásárlást! A számlát és a befizetés részleteit mellékletben találod.'
};

function buildInvoiceData({ userData, shippingAddress, paymentData, plan }) {
  const now = new Date();
  const issueDate = formatDate(now);
  const fulfillmentDate = formatDate(now);
  const paymentDueDate = formatDate(new Date(now.getTime() + 8 * 24 * 60 * 60 * 1000)); // +8 nap

  // Vevő adatok: szállítási címből, fallback user adatokra
  const buyer = buildBuyerData(userData, shippingAddress);

  // Számla fejléc
  // Megjegyzés összeállítása
  let commentParts = [];
  
  // SimplePay tranzakció azonosító hozzáadása - HA VAN
  if (paymentData.transactionId) {
    commentParts.push(`SimplePay azonosító: ${paymentData.transactionId}`);
  }
  
  // Elállási jog lemondásának visszaigazolása - MINDIG BELEKERÜL
  commentParts.push(`Visszaigazoljuk, hogy Ön kifejezetten kérte a teljesítés azonnali megkezdését, és tudomásul vette az elállási jog ezzel járó elvesztését.`);

  // Összefűzés
  const comment = commentParts.join('\n\n');

  // Rendelésszám tisztítása a számlához (csak a timestamp/egyedi azonosító a végéről)
  // Formátum: WEB_userId_timestamp -> timestamp
  let displayOrderRef = paymentData.orderRef;
  if (displayOrderRef && displayOrderRef.includes('_')) {
    const parts = displayOrderRef.split('_');
    // Ha legalább 3 részből áll (WEB, userId, timestamp), akkor az utolsót vesszük
    if (parts.length >= 3) {
      displayOrderRef = parts[parts.length - 1];
    }
  }

  const header = {
    issueDate,
    fulfillmentDate,
    paymentDueDate,
    paymentMethod: 'bankkartya',
    currency: 'HUF',
    language: 'hu',
    orderRef: displayOrderRef,
    paid: true,
    template: 'SzlaMost',
    // Megjegyzés: a Számlázz.hu API-ban a fejléc comment nem mindig jelenik meg jól,
    // ezért a tételsorba is beillesztjük, ha kell, de a jelenlegi logika szerint
    // az invoiceBuilder-ben a comment mező a fejlécben van.
    // Az xml generálásnál (szamlaAgent.js) a fejléc commentet át kell adni.
    comment: comment
  };

  // Számla tétel
  const items = [buildInvoiceItem(plan, paymentData.amount)];

  return {
    header,
    buyer,
    seller: buildSellerData(),
    items
  };
}

/**
 * Vevő adatok összeállítása
 */
function buildBuyerData(userData, shippingAddress) {
  // Ha van szállítási cím, azt használjuk
  if (shippingAddress) {
    const isCompany = shippingAddress.isCompany === 'true';
    const taxNumber = shippingAddress.taxNumber ? shippingAddress.taxNumber.trim() : '';
    const hasTaxNumber = taxNumber !== '';
    
    // Logika: 
    // - Ha cég ÉS van adószám -> adoalany: '6', adoszam: megadott érték
    // - Ha cég DE nincs adószám -> NEM LEHET (frontend validáció miatt nem kellene előfordulnia, de biztonság kedvéért magánszemélyként kezeljük)
    // - Ha magánszemély -> adoalany: '-1' (lakossági, nincs magyar adószáma)
    // - Ha magánszemély DE van adószám -> adoalany: '6', adoszam: megadott érték
    let taxPayer;
    let finalTaxNumber;
    
    if (isCompany) {
      // Cég esetén a frontend validáció biztosítja, hogy van adószám
      if (hasTaxNumber) {
        taxPayer = '6';
        finalTaxNumber = taxNumber;
      } else {
        // Ez nem kellene előfordulnia a frontend validáció miatt, de biztonság kedvéért
        console.warn('[buildBuyerData] Cég kiválasztva de nincs adószám, magánszemélyként kezeljük');
        taxPayer = '-1'; // Lakossági (nincs magyar adószáma)
        finalTaxNumber = undefined;
      }
    } else {
      // Magánszemély
      if (hasTaxNumber) {
        // Ha van adószám, akkor '6'-ra állítjuk
        taxPayer = '6';
        finalTaxNumber = taxNumber;
      } else {
        taxPayer = '-1'; // Lakossági (nincs magyar adószáma)
        finalTaxNumber = undefined;
      }
    }
    
    const buyerData = {
      name: shippingAddress.name || `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || userData.displayName || userData.email,
      country: 'Magyarország',
      zipCode: shippingAddress.zipCode,
      city: shippingAddress.city,
      address: shippingAddress.address,
      email: userData.email,
      taxPayer: taxPayer
    };
    
    // Csak akkor adjuk hozzá a taxNumber-t, ha van értéke
    if (finalTaxNumber) {
      buyerData.taxNumber = finalTaxNumber;
    }
    
    // RÉSZLETES LOGOLÁS: buyer adatok
    console.log('[buildBuyerData] ===== BUYER DATA =====');
    console.log('[buildBuyerData] isCompany:', isCompany);
    console.log('[buildBuyerData] hasTaxNumber:', hasTaxNumber);
    console.log('[buildBuyerData] taxPayer értéke:', taxPayer);
    console.log('[buildBuyerData] taxNumber értéke:', finalTaxNumber || 'UNDEFINED (nem kerül a buyerData-ba)');
    console.log('[buildBuyerData] buyerData objektum:', JSON.stringify(buyerData, null, 2));
    console.log('[buildBuyerData] buyerData.taxNumber jelen van:', 'taxNumber' in buyerData);
    console.log('[buildBuyerData] =======================');
    
    return buyerData;
  }

  // Fallback: user adatok (ha nincs szállítási cím)
  // Megjegyzés: Ez csak fallback, normál esetben mindig legyen shipping address
  return {
    name: `${userData.firstName || ''} ${userData.lastName || ''}`.trim() || userData.displayName || userData.email,
    country: 'Magyarország',
    zipCode: userData.zipCode || '0000',
    city: userData.city || 'Budapest',
    address: userData.address || 'Nincs megadva',
    email: userData.email,
    taxPayer: '-1' // Lakossági (nincs magyar adószáma)
  };
}

function buildSellerData() {
  const seller = {};

  if (SELLER_CONFIG.bankName) {
    seller.bank = SELLER_CONFIG.bankName;
  }

  if (SELLER_CONFIG.bankAccountNumber) {
    seller.bankszamlaszam = SELLER_CONFIG.bankAccountNumber;
  }

  if (SELLER_CONFIG.emailReplyTo) {
    seller.emailReplyto = SELLER_CONFIG.emailReplyTo;
  }

  if (SELLER_CONFIG.emailSubject) {
    seller.emailTargy = SELLER_CONFIG.emailSubject;
  }

  if (SELLER_CONFIG.emailContent) {
    seller.emailSzoveg = SELLER_CONFIG.emailContent;
  }

  // Ha nincs kifejezett adat, akkor is visszaadunk egy üres objektumot, hogy az <elado> elem bekerüljön
  return seller;
}

/**
 * Számla tétel összeállítása
 */
function buildInvoiceItem(plan, grossAmount) {
  // ÁFA számítás (27% ÁFA)
  const vatRate = 27;
  const netPrice = Math.round((grossAmount / (1 + vatRate / 100)) * 100) / 100;
  const vatAmount = Math.round((grossAmount - netPrice) * 100) / 100;
  
  return {
    name: plan.name || '30 napos előfizetés - Prémium hozzáférés',
    quantity: 1,
    unit: 'db',
    netPrice: netPrice,
    vatRate: vatRate,
    vatAmount: vatAmount,
    grossAmount: grossAmount,
    id: plan.id || 'monthly_premium_prepaid',
    comment: plan.description || undefined
  };
}

/**
 * Dátum formázása YYYY-MM-DD formátumban
 */
function formatDate(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${year}-${month}-${day}`;
}

module.exports = {
  buildInvoiceData
};

