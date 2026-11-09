import { defineConfig } from 'vite';

export default defineConfig({
  base: '/assets/matrix/',
  build: {
    outDir: 'assets/matrix',
    emptyOutDir: true,
    target: 'esnext',
    // This file is loaded with `import()` from panel.html, so its named exports
    // must remain available in the generated bundle. Vite app mode strips entry
    // exports; library mode preserves `connect`, `listRooms`, and the other API.
    lib: {
      entry: 'src/matrix-client.js',
      formats: ['es'],
      fileName: () => 'matrix-client.js',
    },
  },
});
