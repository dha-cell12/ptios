import { defineConfig } from 'vite';

export default defineConfig({
  server: {
    host: '0.0.0.0',
    port: 8000,
    allowedHosts: [
      'app.hoadev.online'
    ]
  },
  optimizeDeps: {
    exclude: ['@yume-chan/scrcpy']
  },
});
