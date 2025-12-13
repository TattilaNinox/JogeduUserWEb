// emailTemplates.js - helper to build branded HTML emails for Lomedu

const path = require('path');

const LOGO_CID = 'lomedu-logo@cid';
const LOGO_PATH = path.join(__dirname, 'assets', 'logo.png');

/**
 * Builds the HTML body of the email, embedding the logo via cid.
 * @param {string} bodyHtml - Inner HTML content (already sanitized/escaped).
 * @returns {string} Full HTML ready for nodemailer.
 */
function buildTemplate(bodyHtml) {
  const year = new Date().getFullYear();
  return `<!DOCTYPE html>
  <html lang="hu">
    <head>
      <meta charset="utf-8" />
      <meta name="viewport" content="width=device-width,initial-scale=1" />
      <title>Lomedu</title>
    </head>
    <body style="margin:0;padding:0;background:#f7f7f7;font-family:'Inter',Arial,sans-serif;color:#212529;">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="padding:24px 0;">
        <tr>
          <td align="center">
            <table role="presentation" width="600" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;max-width:600px;width:100%;">
              <tr>
                <td style="background:#0d6efd;padding:24px;text-align:center;">
                  <img src="cid:${LOGO_CID}" alt="Lomedu" style="width:140px;max-width:100%;" />
                </td>
              </tr>
              <tr>
                <td style="padding:32px;font-size:16px;line-height:1.5;">
                  ${bodyHtml}
                </td>
              </tr>
              <tr>
                <td style="padding:16px;background:#f1f3f5;text-align:center;font-size:12px;color:#6c757d;">
                  © ${year} Lomedu – Minden jog fenntartva.
                </td>
              </tr>
            </table>
          </td>
        </tr>
      </table>
    </body>
  </html>`;
}

/**
 * Returns the logo attachment descriptor for nodemailer.
 */
function logoAttachment() {
  return {
    filename: 'logo.png',
    path: LOGO_PATH,
    cid: LOGO_CID,
  };
}

module.exports = {
  buildTemplate,
  logoAttachment,
};
