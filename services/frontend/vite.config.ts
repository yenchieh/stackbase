import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

// host: true → listen on 0.0.0.0 so Vite's HMR works inside the pod.
// proxy: lets standalone `npm run dev` reach the API; under Traefik the
// IngressRoute strips /api instead (same browser-facing path either way).
export default defineConfig({
  plugins: [vue()],
  server: {
    host: true,
    proxy: {
      '/api': {
        target: 'http://localhost:8080',
        changeOrigin: true,
        rewrite: (p) => p.replace(/^\/api/, ''),
      },
    },
  },
})
