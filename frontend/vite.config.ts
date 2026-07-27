import react from "@vitejs/plugin-react";
import { defineConfig } from "vite";

export default defineConfig({
  plugins: [react()],
  server: {
    // ローカル開発時: backend を `uvicorn app.main:app --port 8080` で起動しておく
    proxy: {
      "/api": "http://localhost:8080",
    },
  },
});
