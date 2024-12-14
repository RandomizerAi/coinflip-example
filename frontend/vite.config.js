import { defineConfig } from "vite";
import { svelte } from "@sveltejs/vite-plugin-svelte";
import { VitePWA } from "vite-plugin-pwa";

export default defineConfig({
  plugins: [
    svelte(),
    VitePWA({
      registerType: "autoUpdate",
      workbox: {
        globPatterns: ["**/*.{js,css,html,ico,png,svg}"],
      },
    }),
  ],
  server: {
    watch: {
      usePolling: true,
    },
  },
  build: {
    // Enable chunk splitting
    rollupOptions: {
      output: {
        manualChunks: {
          ethers: ["ethers"],
          web3modal: ["web3modal"],
          walletconnect: ["@walletconnect/web3-provider"],
          vendor: ["socket.io-client"],
        },
      },
    },
    // Enable chunk size warnings
    chunkSizeWarningLimit: 1000,
    // Enable minification
    minify: "terser",
    terserOptions: {
      compress: {
        drop_console: true,
        drop_debugger: true,
      },
    },
  },
});
