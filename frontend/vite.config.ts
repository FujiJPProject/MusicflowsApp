import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

// localhostのVite開発サーバーとS3/CloudFrontは同じReactソースを使う。
export default defineConfig({
  plugins: [react()],
  base: "/",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsDir: "assets",
  },
});
