/**
 * Szamlazz.hu Számla Agent API Client
 * 
 * Node.js implementáció a Szamlazz.hu számlázási API-hoz
 * API kulcs: w8fzve464z69jyni6iy2p5xydiif89hm8x79p9kn5t
 */

const FormData = require('form-data');
const { XMLBuilder } = require('fast-xml-parser');

const API_URL = 'https://www.szamlazz.hu/szamla/';
const API_KEY = 'w8fzve464z69jyni6iy2p5xydiif89hm8x79p9kn5t';

/**
 * Számla létrehozása Szamlazz.hu API-n keresztül
 * 
 * @param {Object} invoiceData - Számla adatok
 * @param {Object} invoiceData.header - Számla fejléc adatok
 * @param {Object} invoiceData.buyer - Vevő adatok
 * @param {Array} invoiceData.items - Számla tételek
 * @returns {Promise<Object>} - Válasz: { success, invoiceNumber, pdf, error }
 */
async function createInvoice(invoiceData) {
  let xmlContent = ''; // Definiáljuk itt, hogy a catch-ben is elérhető legyen
  try {
    // Logoljuk a bejövő buyer adatokat
    console.log('[szamlaAgent] createInvoice - buyer data:', {
      name: invoiceData.buyer?.name,
      taxPayer: invoiceData.buyer?.taxPayer,
      hasTaxNumber: !!invoiceData.buyer?.taxNumber,
      taxNumber: invoiceData.buyer?.taxNumber ? `${invoiceData.buyer.taxNumber.substring(0, 3)}***` : 'nincs'
    });
    
    // XML generálás
    xmlContent = buildInvoiceXml(invoiceData);
    console.log('[szamlaAgent] XML request (first 500 chars):', xmlContent.substring(0, 500));
    
    // RÉSZLETES LOGOLÁS: XML ellenőrzés
    const hasAdoszamInXml = xmlContent.includes('<adoszam>');
    const hasAdoalany1 = xmlContent.includes('<adoalany>1</adoalany>');
    const hasAdoalany6 = xmlContent.includes('<adoalany>6</adoalany>');
    
    console.log('[szamlaAgent] ===== XML ELLENŐRZÉS =====');
    const hasAdoalanyMinus1 = xmlContent.includes('<adoalany>-1</adoalany>');
    console.log('[szamlaAgent] XML contains <adoalany>-1</adoalany> (lakossági):', hasAdoalanyMinus1);
    console.log('[szamlaAgent] XML contains <adoalany>6</adoalany> (van adószám):', hasAdoalany6);
    console.log('[szamlaAgent] XML contains <adoszam>:', hasAdoszamInXml);
    
    if (hasAdoalanyMinus1 && hasAdoszamInXml) {
      const adoszamContent = xmlContent.match(/<adoszam>(.*?)<\/adoszam>/);
      if (adoszamContent && adoszamContent[1].trim() !== '') {
        console.error('[szamlaAgent] HIBA: adoalany: -1 (lakossági) de adoszam nem üres az XML-ben!');
      }
    }
    if (hasAdoalany6 && !hasAdoszamInXml) {
      console.error('[szamlaAgent] HIBA: adoalany: 6 (van adószám) de nincs adoszam mező az XML-ben!');
    }
    
    // Teljes XML logolása (debugging)
    console.log('[szamlaAgent] TELJES XML TARTALOM:');
    console.log(xmlContent);
    console.log('[szamlaAgent] ===========================');
    
    // Multipart form-data készítése
    const formData = new FormData();
    // Számla létrehozásához az "action-xmlagentxmlfile" mezőt kell használni
    formData.append('action-xmlagentxmlfile', Buffer.from(xmlContent, 'utf-8'), {
      filename: 'action-xmlagentxmlfile',
      contentType: 'text/xml; charset=utf-8'
    });

    // HTTP kérés küldése
    const fetch = (await import('node-fetch')).default;
    const response = await fetch(API_URL, {
      method: 'POST',
      body: formData,
      headers: formData.getHeaders()
    });

    const responseText = await response.text();
    
    // Log a válasz első 1000 karaktere (debugging)
    console.log('[szamlaAgent] API response (first 1000 chars):', responseText.substring(0, 1000));
    console.log('[szamlaAgent] Response status:', response.status, response.statusText);
    
    // HTTP fejlécek lekérése (a Szamlazz.hu API a fejlécekben küldi az információkat!)
    // node-fetch v2 esetén a headers egy Headers objektum, amit raw() metódussal lehet feldolgozni
    const headers = {};
    try {
      if (response.headers && typeof response.headers.raw === 'function') {
        // node-fetch v2 esetén
        const rawHeaders = response.headers.raw();
        Object.keys(rawHeaders).forEach(key => {
          const value = Array.isArray(rawHeaders[key]) ? rawHeaders[key][0] : rawHeaders[key];
          headers[key.toLowerCase()] = value;
        });
      } else if (response.headers && typeof response.headers.get === 'function') {
        // node-fetch v3 vagy más implementáció esetén
        // Próbáljuk meg az összes fejlécet lekérni
        const headerNames = [];
        if (response.headers.keys) {
          for (const key of response.headers.keys()) {
            headerNames.push(key);
          }
        }
        headerNames.forEach(key => {
          const value = response.headers.get(key);
          if (value) {
            headers[key.toLowerCase()] = value;
          }
        });
      } else {
        // Fallback: próbáljuk meg közvetlenül elérni
        const rawHeaders = response.headers || {};
        Object.keys(rawHeaders).forEach(key => {
          headers[key.toLowerCase()] = rawHeaders[key];
        });
      }
      console.log('[szamlaAgent] Response headers:', JSON.stringify(headers));
    } catch (headerError) {
      console.error('[szamlaAgent] Error reading headers:', headerError);
      // Folytatjuk fejlécek nélkül is
    }

    // Válasz feldolgozása (fejlécekkel együtt)
    const result = await parseInvoiceResponse(responseText, headers);
    
    // Ha hiba történt, csatoljuk az XML-t debug célokra
    if (!result.success) {
      result.xmlDebug = xmlContent.substring(0, 2000);
    }
    return result;
  } catch (error) {
    console.error('[szamlaAgent] createInvoice error:', error);
    return {
      success: false,
      error: error.message || 'Ismeretlen hiba történt a számla létrehozása során',
      xmlDebug: xmlContent ? xmlContent.substring(0, 2000) : 'XML generálás nem sikerült'
    };
  }
}

/**
 * XML generálás számla adatokból
 */
function buildInvoiceXml(invoiceData) {
  const builder = new XMLBuilder({
    ignoreAttributes: false,
    attributeNamePrefix: '@_',
    format: true,
    suppressEmptyNode: false,
    indentBy: '  '
  });

  const xmlObj = {
    xmlszamla: {
      '@_xmlns': 'http://www.szamlazz.hu/xmlszamla',
      '@_xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
      '@_xsi:schemaLocation': 'http://www.szamlazz.hu/xmlszamla http://www.szamlazz.hu/szamla/docs/xsds/agent/xmlszamla.xsd',
      beallitasok: {
        felhasznalo: API_KEY,
        jelszo: '',
        szamlaagentkulcs: API_KEY,
        eszamla: 'true',
        szamlaLetoltes: 'true',
        valaszVerzio: '2',
        aggregator: ''
      },
      fejlec: {
        keltDatum: invoiceData.header.issueDate,
        teljesitesDatum: invoiceData.header.fulfillmentDate,
        fizetesiHataridoDatum: invoiceData.header.paymentDueDate,
        fizmod: invoiceData.header.paymentMethod || 'bankkartya',
        penznem: invoiceData.header.currency || 'HUF',
        szamlaNyelve: invoiceData.header.language || 'hu',
        megjegyzes: invoiceData.header.comment || '',
        rendelesSzam: invoiceData.header.orderRef || '',
        fizetve: invoiceData.header.paid !== undefined ? invoiceData.header.paid : true,
        szamlaSablon: invoiceData.header.template || 'SzlaMost'
      },
      elado: invoiceData.seller || {},
      vevo: (() => {
        // Adószám és adóalany kezelése ELŐRE
        // FONTOS: Ha nincs taxNumber az invoiceData.buyer-ben, akkor undefined legyen, ne üres string
        const taxNumber = invoiceData.buyer.taxNumber && invoiceData.buyer.taxNumber.trim() !== '' 
          ? invoiceData.buyer.taxNumber.trim() 
          : undefined;
        const hasTaxNumber = taxNumber !== undefined && taxNumber !== '';
        const requestedTaxPayer = invoiceData.buyer.taxPayer || '-1'; // Alapértelmezett: lakossági (nincs adószám)
        
        // BIZTONSÁGI ELLENŐRZÉS: Ha nincs taxNumber az invoiceData.buyer-ben, akkor biztosan ne legyen
        console.log('[szamlaAgent] invoiceData.buyer.taxNumber értéke:', invoiceData.buyer.taxNumber);
        console.log('[szamlaAgent] invoiceData.buyer.taxNumber jelen van:', 'taxNumber' in invoiceData.buyer);
        
        // Logoljuk a bejövő adatokat
        console.log('[szamlaAgent] Buyer tax data:', {
          requestedTaxPayer,
          hasTaxNumber,
          taxNumber: taxNumber ? `${taxNumber.substring(0, 3)}***` : 'nincs'
        });
        
        // Számlázz.hu logika: ha adoalany: '6', akkor KÖTELEZŐ az adoszam mező
        // Ha nincs adószám, akkor adoalany: '-1' kell legyen (lakossági, nincs magyar adószáma)
        let adoalanyValue;
        let adoszamValue;
        
        if (hasTaxNumber) {
          // Van adószám -> adoalany: '6', adoszam: érték
          adoalanyValue = '6';
          adoszamValue = taxNumber;
        } else {
          // Nincs adószám -> adoalany: '-1' (lakossági, nincs magyar adószáma)
          adoalanyValue = '-1';
          adoszamValue = undefined; // NEM adjuk hozzá az adoszam mezőt, ha nincs érték
        }
        
        // VÉGLEGES BIZTONSÁGI ELLENŐRZÉS: ha adoalany: '6', akkor KÖTELEZŐ az adoszam
        if (adoalanyValue === '6' && !adoszamValue) {
          console.error('[szamlaAgent] HIBA: adoalany: 6 de nincs adoszam! Lakosságiként kezeljük.');
          adoalanyValue = '-1';
          adoszamValue = undefined; // Biztos, hogy nincs adoszam mező
        }
        
        // Vevő objektum összeállítása - SORREND FONTOS!
        // A dokumentáció szerint: nev -> orszag -> irsz -> telepules -> cim -> email -> sendEmail -> adoalany -> adoszam -> telefonszam
        // FONTOS: Az adoszam mezőt MINDIG küldeni kell, még akkor is, ha üres
        // Ha adoalany: '-1' (lakossági, nincs magyar adószáma), akkor üres stringet küldünk
        const vevoObj = {
          nev: invoiceData.buyer.name,
          orszag: invoiceData.buyer.country || 'Magyarország',
          irsz: invoiceData.buyer.zipCode,
          telepules: invoiceData.buyer.city,
          cim: invoiceData.buyer.address,
          email: invoiceData.buyer.email || '',
          sendEmail: true, // Szamlazz.hu küldi az emailt
          adoalany: adoalanyValue
        };
        
        // Számlázz.hu API követelmény: az adoszam mezőt MINDIG küldeni kell, még akkor is, ha üres
        // Ha adoalany: '-1' (lakossági, nincs magyar adószáma), akkor üres stringet küldünk
        // Ha adoalany: '6' (van adószám), akkor az adószámot küldjük
        if (adoszamValue !== undefined && adoszamValue !== null && adoszamValue.toString().trim() !== '') {
          vevoObj.adoszam = adoszamValue;
          console.log('[szamlaAgent] adoszam mező HOZZÁADVA az objektumhoz:', adoszamValue);
        } else {
          // Lakossági vásárló esetén üres stringet küldünk (API követelmény)
          vevoObj.adoszam = '';
          console.log('[szamlaAgent] adoszam mező ÜRES STRINGGEL hozzáadva (lakossági vásárló, adoalany: -1)');
        }
        
        // telefonszam opcionális
        if (invoiceData.buyer.phone) {
          vevoObj.telefonszam = invoiceData.buyer.phone;
        }
        
        // RÉSZLETES LOGOLÁS: vevo objektum teljes tartalma
        console.log('[szamlaAgent] ===== VEVO OBJEKTUM TELJES TARTALMA =====');
        console.log('[szamlaAgent] vevoObj (JSON):', JSON.stringify(vevoObj, null, 2));
        console.log('[szamlaAgent] adoalany értéke:', vevoObj.adoalany);
        console.log('[szamlaAgent] adoszam mező jelen van az objektumban:', 'adoszam' in vevoObj);
        console.log('[szamlaAgent] adoszam értéke:', vevoObj.adoszam !== undefined ? vevoObj.adoszam : 'UNDEFINED (nem kerül az XML-be)');
        console.log('[szamlaAgent] vevo objektum kulcsai:', Object.keys(vevoObj));
        console.log('[szamlaAgent] vevo objektum értékei:', Object.values(vevoObj));
        
        // VÉGLEGES ELLENŐRZÉS: Ha adoalany: '-1', akkor üres adoszam mező lehet
        if (vevoObj.adoalany === '-1' && vevoObj.adoszam !== '') {
          console.warn('[szamlaAgent] Figyelmeztetés: adoalany: -1 de adoszam nem üres! Üresre állítjuk.');
          vevoObj.adoszam = '';
        }
        
        console.log('[szamlaAgent] ===========================================');
        
        return vevoObj;
      })(),
      tetelek: {}
    }
  };

  // Tételek hozzáadása - item0, item1 stb. kulcsokkal (ahogy a PHP könyvtár)
  // A fast-xml-parser automatikusan <tetel> elemeket generál belőlük
  // Sorrend: megnevezes -> mennyiseg -> mennyisegiEgyseg -> nettoEgysegar -> afakulcs -> 
  //         nettoErtek -> afaErtek -> bruttoErtek -> megjegyzes/tetelFokonyv/torloKod
  // Az azonosito mezőt eltávolítottuk, mert a terméknév már tartalmazza az információt
  xmlObj.xmlszamla.tetelek = {};
  invoiceData.items.forEach((item, index) => {
    const itemObj = {
      megnevezes: item.name,
      mennyiseg: item.quantity.toString(),
      mennyisegiEgyseg: item.unit || 'db',
      nettoEgysegar: item.netPrice.toString(),
      afakulcs: item.vatRate.toString(),
      nettoErtek: item.netPrice.toString(),
      afaErtek: item.vatAmount.toString(),
      bruttoErtek: item.grossAmount.toString()
    };

    // megjegyzes csak a bruttoErtek után lehet (XML séma követelmény)
    const comment = item.comment;
        
    if (comment) {
      itemObj.megjegyzes = comment;
    }

    xmlObj.xmlszamla.tetelek[`item${index}`] = itemObj;
  });

  // RÉSZLETES LOGOLÁS: XML objektum a generálás előtt
  console.log('[szamlaAgent] ===== XML OBJEKTUM GENERÁLÁS ELŐTT =====');
  console.log('[szamlaAgent] xmlObj.xmlszamla.vevo (JSON):', JSON.stringify(xmlObj.xmlszamla.vevo, null, 2));
  console.log('[szamlaAgent] xmlObj.xmlszamla.vevo kulcsai:', Object.keys(xmlObj.xmlszamla.vevo));
  console.log('[szamlaAgent] xmlObj.xmlszamla.vevo.adoalany:', xmlObj.xmlszamla.vevo.adoalany);
  console.log('[szamlaAgent] xmlObj.xmlszamla.vevo.adoszam jelen van:', 'adoszam' in xmlObj.xmlszamla.vevo);
  console.log('[szamlaAgent] =========================================');
  
  let xmlContent = builder.build(xmlObj);
  
  // RÉSZLETES LOGOLÁS: XML tartalom a replace előtt
  console.log('[szamlaAgent] ===== XML TARTALOM REPLACE ELŐTT =====');
  const vevoStartBefore = xmlContent.indexOf('<vevo>');
  const vevoEndBefore = xmlContent.indexOf('</vevo>');
  if (vevoStartBefore !== -1 && vevoEndBefore !== -1) {
    const vevoXmlBefore = xmlContent.substring(vevoStartBefore, vevoEndBefore + 7);
    console.log('[szamlaAgent] vevo XML (replace előtt):', vevoXmlBefore);
    console.log('[szamlaAgent] vevo XML contains <adoszam> (replace előtt):', vevoXmlBefore.includes('<adoszam>'));
  }
  console.log('[szamlaAgent] =========================================');
  
  // A PHP könyvtár item0, item1 stb. kulcsokat használ, de XML-ben tetel elemeket generál
  // A fast-xml-parser nem csinál ilyen átnevezést, ezért manuálisan cseréljük
  // FONTOS: Minden itemX elemet tetel-re kell cserélni
  const beforeReplace = xmlContent;
  xmlContent = xmlContent.replace(/<item\d+>/g, '<tetel>');
  xmlContent = xmlContent.replace(/<\/item\d+>/g, '</tetel>');
  
  // RÉSZLETES LOGOLÁS: vevo rész az XML-ből
  const vevoStart = xmlContent.indexOf('<vevo>');
  const vevoEnd = xmlContent.indexOf('</vevo>');
  if (vevoStart !== -1 && vevoEnd !== -1) {
    const vevoXml = xmlContent.substring(vevoStart, vevoEnd + 7);
    console.log('[szamlaAgent] ===== VEVO XML RÉSZ =====');
    console.log('[szamlaAgent] Generated vevo XML:', vevoXml);
    console.log('[szamlaAgent] vevo XML contains <adoalany>:', vevoXml.includes('<adoalany>'));
    console.log('[szamlaAgent] vevo XML contains <adoszam>:', vevoXml.includes('<adoszam>'));
    
    // Adoalany érték kinyerése
    const adoalanyMatch = vevoXml.match(/<adoalany>(\d+)<\/adoalany>/);
    if (adoalanyMatch) {
      console.log('[szamlaAgent] adoalany értéke az XML-ben:', adoalanyMatch[1]);
    } else {
      console.log('[szamlaAgent] adoalany NEM található az XML-ben!');
    }
    
    // Adoszam érték kinyerése
    const adoszamMatch = vevoXml.match(/<adoszam>(.*?)<\/adoszam>/);
    if (adoszamMatch) {
      console.log('[szamlaAgent] adoszam értéke az XML-ben:', adoszamMatch[1] || '(üres)');
    } else {
      console.log('[szamlaAgent] adoszam NEM található az XML-ben (ez jó, ha lakossági vásárló)');
    }
    console.log('[szamlaAgent] ===========================');
  }
  
  // Debug: logoljuk, ha még mindig van item0
  if (xmlContent.includes('<item')) {
    console.error('[szamlaAgent] WARNING: itemX elemek még mindig jelen vannak az XML-ben!');
    console.error('[szamlaAgent] XML részlet:', xmlContent.substring(xmlContent.indexOf('<tetelek>'), xmlContent.indexOf('</tetelek>') + 10));
  }
  
  // XML deklaráció hozzáadása (fast-xml-parser nem adja hozzá automatikusan)
  return '<?xml version="1.0" encoding="UTF-8"?>\n' + xmlContent;
}

/**
 * Válasz feldolgozása
 * A Szamlazz.hu API a HTTP fejlécekben küldi az információkat!
 */
function parseInvoiceResponse(responseText, headers = {}) {
  try {
    console.log('[szamlaAgent] parseInvoiceResponse - response length:', responseText.length);
    console.log('[szamlaAgent] parseInvoiceResponse - first 200 chars:', responseText.substring(0, 200));
    console.log('[szamlaAgent] parseInvoiceResponse - headers:', JSON.stringify(headers));
    
    // Először ellenőrizzük a fejléceket (ez a fő információforrás!)
    const lowerHeaders = {};
    Object.keys(headers).forEach(key => {
      lowerHeaders[key.toLowerCase()] = headers[key];
    });
    
    // Hiba ellenőrzése fejlécekben
    if (lowerHeaders['szlahu_error'] || lowerHeaders['szlahu_error_code']) {
      const errorMsg = lowerHeaders['szlahu_error'] ? decodeURIComponent(lowerHeaders['szlahu_error']) : 'Ismeretlen hiba';
      const errorCode = lowerHeaders['szlahu_error_code'] || null;
      console.error('[szamlaAgent] Error in headers:', { errorMsg, errorCode });
      return {
        success: false,
        error: errorMsg,
        errorCode: errorCode
      };
    }
    
    // Sikeres válasz - számlaszám a fejlécekben
    if (lowerHeaders['szlahu_szamlaszam']) {
      const invoiceNumber = lowerHeaders['szlahu_szamlaszam'];
      const vevoifiokurl = lowerHeaders['szlahu_vevoifiokurl'] ? decodeURIComponent(lowerHeaders['szlahu_vevoifiokurl']) : null;
      
      console.log('[szamlaAgent] Success - invoice number from headers:', invoiceNumber);
      
      // PDF ellenőrzése
      let pdfBase64 = null;
      let pdf = null;
      
      // Ha PDF válasz érkezett (binary)
      if (responseText.startsWith('%PDF')) {
        console.log('[szamlaAgent] PDF response detected in body');
        pdf = responseText;
        pdfBase64 = Buffer.from(responseText, 'binary').toString('base64');
      } else if (responseText.length > 0) {
        // Base64 encoded PDF lehet a body-ban
        try {
          const decoded = Buffer.from(responseText, 'base64').toString('binary');
          if (decoded.startsWith('%PDF')) {
            console.log('[szamlaAgent] Base64 PDF detected in body');
            pdf = decoded;
            pdfBase64 = responseText;
          }
        } catch (e) {
          // Nem base64, lehet szöveges válasz
        }
      }
      
      return {
        success: true,
        invoiceNumber: invoiceNumber,
        vevoifiokurl: vevoifiokurl,
        pdf: pdf,
        pdfBase64: pdfBase64
      };
    }
    
    // Ha PDF válasz érkezett (binary) de nincs számlaszám a fejlécekben
    if (responseText.startsWith('%PDF')) {
      console.log('[szamlaAgent] PDF response detected but no invoice number in headers');
      return {
        success: true,
        pdf: responseText,
        pdfBase64: Buffer.from(responseText, 'binary').toString('base64'),
        invoiceNumber: null // PDF-ből nem lehet kinyerni, query kell
      };
    }

    // XML válasz feldolgozása
    const { XMLParser } = require('fast-xml-parser');
    const parser = new XMLParser({
      ignoreAttributes: false,
      attributeNamePrefix: '@_',
      parseAttributeValue: true,
      trimValues: true,
      parseTrueNumberOnly: false
    });

    let result;
    try {
      result = parser.parse(responseText);
      console.log('[szamlaAgent] Parsed XML result:', JSON.stringify(result, null, 2).substring(0, 1000));
    } catch (parseError) {
      console.error('[szamlaAgent] XML parse error:', parseError);
      // Próbáljuk meg szöveges válaszként kezelni
      if (responseText.includes('szamlaszam') || responseText.includes('sikeres')) {
        const match = responseText.match(/szamlaszam[:\s]+([A-Z0-9-]+)/i);
        return {
          success: true,
          invoiceNumber: match ? match[1] : null,
          pdf: null
        };
      }
      throw parseError;
    }

    // Sikeres válasz - különböző formátumok kezelése
    if (result.sikeres) {
      console.log('[szamlaAgent] Success response found');
      return {
        success: true,
        invoiceNumber: result.sikeres.szamlaszam || result.sikeres.számlaszám || null,
        vevoifiokurl: result.sikeres.vevoifiokurl || result.sikeres.véveőifiokurl || null,
        pdf: result.sikeres.pdf ? Buffer.from(result.sikeres.pdf, 'base64').toString('binary') : null,
        pdfBase64: result.sikeres.pdf || null
      };
    }

    // Hiba válasz - különböző formátumok kezelése
    if (result.hibauzenet || result.hibauzenet) {
      const hiba = result.hibauzenet || result.hibauzenet;
      console.error('[szamlaAgent] Error response found:', hiba);
      return {
        success: false,
        error: hiba.hibaszoveg || hiba.hibaszöveg || hiba.hibakod || hiba.hibakód || 'Ismeretlen hiba',
        errorCode: hiba.hibakod || hiba.hibakód || null
      };
    }

    // XML válasz más struktúrával
    if (result.xmlszamlavalasz) {
      const valasz = result.xmlszamlavalasz;
      if (valasz.sikeres) {
        return {
          success: true,
          invoiceNumber: valasz.sikeres.szamlaszam || valasz.sikeres.számlaszám || null,
          vevoifiokurl: valasz.sikeres.vevoifiokurl || null,
          pdf: valasz.sikeres.pdf ? Buffer.from(valasz.sikeres.pdf, 'base64').toString('binary') : null,
          pdfBase64: valasz.sikeres.pdf || null
        };
      }
      if (valasz.hibauzenet || valasz.hibauzenet) {
        const hiba = valasz.hibauzenet || valasz.hibauzenet;
        return {
          success: false,
          error: hiba.hibaszoveg || hiba.hibaszöveg || hiba.hibakod || 'Ismeretlen hiba',
          errorCode: hiba.hibakod || hiba.hibakód || null
        };
      }
    }

    // Szöveges válasz (sikeres)
    if (responseText.includes('szamlaszam') || responseText.includes('számlaszám')) {
      const match = responseText.match(/sz[áa]mlasz[áa]m[:\s]+([A-Z0-9-]+)/i);
      console.log('[szamlaAgent] Text response with invoice number:', match ? match[1] : 'not found');
      return {
        success: true,
        invoiceNumber: match ? match[1] : null,
        pdf: responseText.includes('PDF') ? responseText : null
      };
    }

    // Ha nem találtunk semmit, logoljuk a teljes választ
    console.error('[szamlaAgent] Unknown response format. Full response:', responseText);
    return {
      success: false,
      error: 'Ismeretlen válasz formátum',
      rawResponse: responseText.substring(0, 1000)
    };
  } catch (error) {
    console.error('[szamlaAgent] parseInvoiceResponse error:', error);
    console.error('[szamlaAgent] Error stack:', error.stack);
    return {
      success: false,
      error: `Válasz feldolgozási hiba: ${error.message}`,
      rawResponse: responseText.substring(0, 1000)
    };
  }
}

/**
 * Számla PDF lekérése számlaszám alapján
 */
async function getInvoicePdf(invoiceNumber) {
  try {
    const builder = new XMLBuilder({
      ignoreAttributes: false,
      attributeNamePrefix: '@_',
      format: true
    });

    const xmlObj = {
      '?xml': {
        '@_version': '1.0',
        '@_encoding': 'UTF-8'
      },
      xmlszamlapdf: {
        '@_xmlns': 'http://www.szamlazz.hu/xmlszamlapdf',
        '@_xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        '@_xsi:schemaLocation': 'http://www.szamlazz.hu/xmlszamlapdf http://www.szamlazz.hu/szamla/docs/xsds/agentpdf/xmlszamlapdf.xsd',
        beallitasok: {
          felhasznalo: API_KEY,
          jelszo: '',
          szamlaagentkulcs: API_KEY,
          szamlaszam: invoiceNumber
        }
      }
    };

    const xmlContent = builder.build(xmlObj);
    const formData = new FormData();
    formData.append('action-szamla_agent_pdf', Buffer.from(xmlContent, 'utf-8'), {
      filename: 'action-szamla_agent_pdf',
      contentType: 'text/xml; charset=utf-8'
    });

    const fetch = (await import('node-fetch')).default;
    const response = await fetch(API_URL, {
      method: 'POST',
      body: formData,
      headers: formData.getHeaders()
    });

    const responseText = await response.text();
    
    if (responseText.startsWith('%PDF')) {
      return {
        success: true,
        pdf: responseText,
        pdfBase64: Buffer.from(responseText, 'binary').toString('base64')
      };
    }

    return {
      success: false,
      error: 'PDF nem érkezett meg',
      rawResponse: responseText.substring(0, 500)
    };
  } catch (error) {
    console.error('[szamlaAgent] getInvoicePdf error:', error);
    return {
      success: false,
      error: error.message || 'PDF letöltési hiba'
    };
  }
}

/**
 * Számla ellenőrzése külső azonosító alapján
 */
async function checkInvoiceByExternalId(externalId) {
  try {
    const builder = new XMLBuilder({
      ignoreAttributes: false,
      attributeNamePrefix: '@_',
      format: true
    });

    const xmlObj = {
      '?xml': {
        '@_version': '1.0',
        '@_encoding': 'UTF-8'
      },
      xmlszamlaxml: {
        '@_xmlns': 'http://www.szamlazz.hu/xmlszamlaxml',
        '@_xmlns:xsi': 'http://www.w3.org/2001/XMLSchema-instance',
        '@_xsi:schemaLocation': 'http://www.szamlazz.hu/xmlszamlaxml http://www.szamlazz.hu/szamla/docs/xsds/agentxml/xmlszamlaxml.xsd',
        beallitasok: {
          felhasznalo: API_KEY,
          jelszo: '',
          szamlaagentkulcs: API_KEY,
          szamlaKulsoAzon: externalId
        }
      }
    };

    const xmlContent = builder.build(xmlObj);
    const formData = new FormData();
    formData.append('action-szamla_agent_xml', Buffer.from(xmlContent, 'utf-8'), {
      filename: 'action-szamla_agent_xml',
      contentType: 'text/xml; charset=utf-8'
    });

    const fetch = (await import('node-fetch')).default;
    const response = await fetch(API_URL, {
      method: 'POST',
      body: formData,
      headers: formData.getHeaders()
    });

    const responseText = await response.text();
    
    const { XMLParser } = require('fast-xml-parser');
    const parser = new XMLParser({
      ignoreAttributes: false,
      attributeNamePrefix: '@_',
      parseAttributeValue: true
    });

    const result = parser.parse(responseText);
    
    if (result.szamla) {
      return {
        success: true,
        invoice: result.szamla
      };
    }

    return {
      success: false,
      error: 'Számla nem található',
      rawResponse: responseText.substring(0, 500)
    };
  } catch (error) {
    console.error('[szamlaAgent] checkInvoiceByExternalId error:', error);
    return {
      success: false,
      error: error.message || 'Számla ellenőrzési hiba'
    };
  }
}

module.exports = {
  createInvoice,
  getInvoicePdf,
  checkInvoiceByExternalId,
  // Exportáljuk teszteléshez és debughoz
  buildInvoiceXml
};

