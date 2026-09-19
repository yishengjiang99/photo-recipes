import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import tailwindcss from '@tailwindcss/vite'

export default defineConfig({
  plugins: [
    react(),
    tailwindcss(),
    {
      name: 'strip-module-crossorigin',
      transformIndexHtml(html) {
        // Older iOS Safari can be picky about module scripts / stylesheets with crossorigin.
        // Keep fonts.gstatic preconnect crossorigin intact.
        return html
          .replace(
            /<script\b([^>]*)\scrossorigin(?:="[^"]*")?([^>]*)>/g,
            '<script$1$2>',
          )
          .replace(
            /<link\b([^>]*\brel=["']stylesheet["'][^>]*)\scrossorigin(?:="[^"]*")?([^>]*)>/g,
            '<link$1$2>',
          )
          .replace(
            /<link\b([^>]*)\scrossorigin(?:="[^"]*")?([^>]*\brel=["']stylesheet["'][^>]*)>/g,
            '<link$1$2>',
          )
      },
    },
  ],
  build: {
    // iOS 15+ / Safari 15 — avoid overly modern syntax that older WebKit rejects.
    target: ['es2020', 'safari15'],
  },
  server: {
    proxy: {
      '/api': {
        target: 'http://127.0.0.1:8787',
        changeOrigin: true,
      },
    },
  },
})
