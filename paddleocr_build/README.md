# Paddle OCR bundle for "Scan with Paddle OCR"

`web/paddleocr/lumio_paddle.js` is built from PaddleOCR's browser SDK
(`paddleocr-js`, PaddleOCR repository `main`, SDK 0.4.2, Apache-2.0) plus
`src/lumio_paddle.js` here. Models in `web/paddleocr/models/` are PaddleOCR's
official PP-OCRv5 mobile det/rec ONNX archives, served from our own site
because the official host took over a minute per download.

To rebuild:

1. Copy this folder to `paddleocr-js/apps/lumio` inside the PaddleOCR repo.
2. In `paddleocr-js`: `npm ci`, `npm run build:sdk`, `npm install`.
3. In `apps/lumio`: `npx vite build`.
4. Copy `dist/lumio_paddle.js` to `web/paddleocr/` (not `dist/assets`:
   the worker is unused and ONNX Runtime's wasm loads from jsDelivr).
