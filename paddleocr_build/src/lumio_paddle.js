// Paddle OCR for Lumio's "Scan with Paddle OCR" (dining). Runs PP-OCRv5 in
// the browser with ONNX Runtime Web; no image leaves the device.
import { PaddleOCR } from "@paddleocr/paddleocr-js";

const ORT_VERSION = "1.24.3";
const here = new URL(".", import.meta.url).href;
let engine = null;

function getEngine() {
  engine ??= PaddleOCR.create({
    worker: false,
    textDetectionModelName: "PP-OCRv5_mobile_det",
    textDetectionModelAsset: { url: here + "models/PP-OCRv5_mobile_det_onnx_infer.tar" },
    textRecognitionModelName: "PP-OCRv5_mobile_rec",
    textRecognitionModelAsset: { url: here + "models/PP-OCRv5_mobile_rec_onnx_infer.tar" },
    ortOptions: {
      backend: "wasm",
      wasmPaths: `https://cdn.jsdelivr.net/npm/onnxruntime-web@${ORT_VERSION}/dist/`,
      numThreads: 1
    }
  }).catch((error) => {
    engine = null;
    throw error;
  });
  return engine;
}

/** Loads the models ahead of the first photo. */
export async function warmUp() {
  await getEngine();
  return true;
}

/** Reads the text in an image (encoded bytes). Resolves to JSON:
 * {"width":w,"height":h,"lines":[{"text","score","box":[x0,y0,x1,y1]}]} */
export async function readText(bytes) {
  const ocr = await getEngine();
  const [result] = await ocr.predict(new Blob([bytes]));
  const lines = result.items.map((item) => {
    const xs = item.poly.map((p) => p[0]);
    const ys = item.poly.map((p) => p[1]);
    return {
      text: item.text,
      score: item.score,
      box: [Math.min(...xs), Math.min(...ys), Math.max(...xs), Math.max(...ys)]
    };
  });
  return JSON.stringify({ width: result.image.width, height: result.image.height, lines });
}
