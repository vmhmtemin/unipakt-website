import { defineConfig } from 'vite';

export default defineConfig({
  base: '/assets/matrix/',
  build: {
    outDir: 'assets/matrix',
    emptyOutDir: true,
    target: 'esnext',
    rollupOptions: {
      input: 'src/matrix-client.js',
      output: { entryFileNames: 'matrix-client.js' },
    },
  },
});
