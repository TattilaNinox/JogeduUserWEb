// Egységes eszköz-ujjlenyomat webre: böngésző + platform + képernyő + nyelv
export function getWebDeviceFingerprint(): string {
  if (typeof window === 'undefined') return 'server';
  const nav = window.navigator as any;
  const ua = nav.userAgent || '';
  const platform = nav.platform || '';
  const lang = nav.language || '';
  const screenInfo = window.screen ? `${screen.width}x${screen.height}x${screen.colorDepth}` : 'noscreen';
  const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone || '';
  const hardware = `${nav.hardwareConcurrency || 'hc?'}_${(nav.deviceMemory || 'dm?')}`;
  // Androidos formátum mintájára végződés
  const suffix = '_web';
  const raw = `${ua}|${platform}|${lang}|${screenInfo}|${timezone}|${hardware}`;
  // Egyszerű hash
  let hash = 0;
  for (let i = 0; i < raw.length; i++) {
    hash = (hash << 5) - hash + raw.charCodeAt(i);
    hash |= 0;
  }
  return `${Math.abs(hash)}${suffix}`;
}


