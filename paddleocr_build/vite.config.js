import { resolve } from "node:path";
import { defineConfig } from "vite";

// ORT's wasm binaries are fetched from wasmPaths at run time, so the base64
// copies Vite inlines are dropped (as the SDK's own build does).
function stripOrtWasm() {
  const pattern = /data:application\/wasm;base64,[A-Za-z0-9+/=]+/g;
  return {
    name: "strip-ort-wasm",
    apply: "build",
    generateBundle(_, bundle) {
      for (const item of Object.values(bundle)) {
        if (item.type === "chunk") item.code = item.code.replace(pattern, "data:application/wasm;base64,");
        else if (typeof item.source === "string") item.source = item.source.replace(pattern, "data:application/wasm;base64,");
      }
    }
  };
}

export default defineConfig({
  base: "./",
  plugins: [stripOrtWasm()],
  build: {
    outDir: "dist",
    emptyOutDir: true,
    assetsInlineLimit: 0,
    modulePreload: false,
    rollupOptions: {
      input: resolve(__dirname, 'src/lumio_paddle.js'),
      preserveEntrySignatures: 'strict',
      output: { entryFileNames: 'lumio_paddle.js', inlineDynamicImports: true }
    }
  }
});
