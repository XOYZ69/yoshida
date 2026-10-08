import { defineConfig } from 'vite';
import { svelte } from '@sveltejs/vite-plugin-svelte';

// base './' lets the built site run from any sub-path (static hosting) and
// from the yoshida server.
export default defineConfig({
  base: './',
  plugins: [svelte()],
  worker: { format: 'es' },
  server: {
    proxy: { '/api': 'http://localhost:8080' },
  },
});
