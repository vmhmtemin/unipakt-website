// Draws a QR code as an SVG string (event page: entry code after registering).
import QRCode from 'qrcode';

export async function qrSvg(text) {
  return QRCode.toString(String(text), { type: 'svg', margin: 1, errorCorrectionLevel: 'M', color: { dark: '#0C0C0D', light: '#FFFFFF' } });
}
