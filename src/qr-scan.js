// Reads QR codes from the camera (kontrol.html). Uses the browser's own
// BarcodeDetector where it exists (Chrome/Android) and ZXing elsewhere
// (Safari/iOS, Firefox). startScanner() resolves to a stop() function.
import { BrowserQRCodeReader } from '@zxing/browser';

export async function startScanner(video, onCode) {
  const stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: { ideal: 'environment' } }, audio: false });
  video.srcObject = stream;
  video.setAttribute('playsinline', '');
  video.muted = true;
  await video.play();
  let stopped = false;
  let last = '', lastAt = 0;
  const emit = (text) => {
    const now = Date.now();
    if (!text || (text === last && now - lastAt < 2500)) return;   // the same code stays in view
    last = text; lastAt = now;
    onCode(text);
  };
  const stopStream = () => { stream.getTracks().forEach((t) => t.stop()); video.srcObject = null; };

  if ('BarcodeDetector' in window) {
    try {
      const formats = await window.BarcodeDetector.getSupportedFormats();
      if (formats.includes('qr_code')) {
        const detector = new window.BarcodeDetector({ formats: ['qr_code'] });
        const loop = async () => {
          if (stopped) return;
          try { const found = await detector.detect(video); if (found[0]) emit(found[0].rawValue); } catch (_) {}
          setTimeout(loop, 180);
        };
        loop();
        return () => { stopped = true; stopStream(); };
      }
    } catch (_) {}
  }

  const reader = new BrowserQRCodeReader(undefined, { delayBetweenScanAttempts: 180 });
  const controls = await reader.decodeFromStream(stream, video, (result) => { if (result && !stopped) emit(result.getText()); });
  return () => { stopped = true; try { controls.stop(); } catch (_) {} stopStream(); };
}
