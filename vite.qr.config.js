import { defineConfig } from 'vite';

// QR helpers loaded with import(): qr-make (event page) and qr-scan (kontrol.html).
export default defineConfig({
  base: '/assets/qr/',
  build: {
    outDir: 'assets/qr',
    emptyOutDir: true,
    target: 'es2019',
    lib: {
      entry: { 'qr-make': 'src/qr-make.js', 'qr-scan': 'src/qr-scan.js' },
      formats: ['es'],
      fileName: (_format, name) => `${name}.js`,
    },
  },
});
