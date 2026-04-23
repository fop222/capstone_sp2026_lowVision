from flask import Flask, request, jsonify
from PIL import Image
from typing import List
import os
import io
import easyocr
import numpy as np
import torch
from pathlib import Path
from werkzeug.utils import secure_filename
import traceback

from transformers import AutoProcessor, Qwen3VLForConditionalGeneration
import threading

# Optional YOLO import (for /detect-yolo)
try:
    from ultralytics import YOLO
    _YOLO_AVAILABLE = True
except Exception:
    YOLO = None
    _YOLO_AVAILABLE = False

app = Flask(__name__)

# app_server_VLM.py is inside /VLM Testing, but Images_2026 is in repo root
SERVER_DIR = Path(__file__).resolve().parent
ROOT_DIR = SERVER_DIR.parent
UPLOAD_FOLDER = ROOT_DIR / "Images_2026"
UPLOAD_FOLDER.mkdir(parents=True, exist_ok=True)

VLM_MODEL_NAME = os.environ.get("VLM_MODEL_NAME", "Qwen/Qwen3-VL-2B-Instruct")
MAX_NEW_TOKENS = int(os.environ.get("MAX_NEW_TOKENS", "96"))
MAX_IMAGE_SIDE = int(os.environ.get("MAX_IMAGE_SIDE", "768"))
SERIALIZE_VLM = os.environ.get("SERIALIZE_VLM", "1") != "0"
OCR_GPU = os.environ.get("OCR_GPU", "1") == "1"
YOLO_MODEL_PATH = os.environ.get("YOLO_MODEL_PATH", "best.pt")

# If 1, include traceback in JSON errors (dev only)
RETURN_TRACEBACK = os.environ.get("RETURN_TRACEBACK", "0") == "1"

# Load EasyOCR once (default: CPU to preserve VRAM for VLM)
reader = easyocr.Reader(["en"], gpu=False)


def load_vlm_model_and_processor(model_name: str):
    dtype = torch.float16 if torch.cuda.is_available() else torch.float32
    extra_kwargs = {}
    # Optionally request a more memory-efficient attention impl if installed.
    attn_impl = os.environ.get("VLM_ATTN_IMPL", "").strip()
    if attn_impl:
        extra_kwargs["attn_implementation"] = attn_impl

    # transformers has used both `torch_dtype` and `dtype` across versions.
    # Prefer `dtype` (newer), fall back to `torch_dtype` (older).
    try:
        vlm_model = Qwen3VLForConditionalGeneration.from_pretrained(
            model_name,
            dtype=dtype,
            device_map="auto",
            **extra_kwargs,
        )
    except TypeError:
        vlm_model = Qwen3VLForConditionalGeneration.from_pretrained(
            model_name,
            torch_dtype=dtype,
            device_map="auto",
            **extra_kwargs,
        )
    vlm_model.eval()
    vlm_processor = AutoProcessor.from_pretrained(model_name)
    return vlm_model, vlm_processor

vlm_model, vlm_processor = load_vlm_model_and_processor(VLM_MODEL_NAME)
_vlm_lock = threading.Lock()

# Load YOLO once (if available)
yolo_model = None
if _YOLO_AVAILABLE:
    try:
        yolo_model = YOLO(YOLO_MODEL_PATH)
    except Exception as e:
        print(f"[WARN] YOLO failed to load from {YOLO_MODEL_PATH}: {e}")
        yolo_model = None


def _json_error(status_code: int, message: str, tb: str | None = None):
    payload = {"error": message}
    if RETURN_TRACEBACK and tb:
        payload["traceback"] = tb
    return jsonify(payload), status_code


def infer_with_vlm(image_path: Path, question: str) -> str:
    if not image_path.exists():
        raise FileNotFoundError(f"Image not found: {image_path}")

    # Resize before passing to the VLM to reduce VRAM usage.
    resized_path = image_path
    try:
        img = Image.open(str(image_path)).convert("RGB")
        w, h = img.size
        max_side = max(w, h)
        if max_side > MAX_IMAGE_SIDE and MAX_IMAGE_SIDE > 0:
            scale = MAX_IMAGE_SIDE / float(max_side)
            new_w = max(1, int(w * scale))
            new_h = max(1, int(h * scale))
            img = img.resize((new_w, new_h))
            resized_path = image_path.with_name(
                f"{image_path.stem}_resized_{MAX_IMAGE_SIDE}{image_path.suffix or '.png'}"
            )
            img.save(str(resized_path))
    except Exception:
        # If resizing fails, fall back to original file.
        resized_path = image_path

    messages = [
        {
            "role": "user",
            "content": [
                {"type": "text", "text": question},
                {"type": "image", "image": str(resized_path.resolve())},
            ],
        }
    ]

    inputs = vlm_processor.apply_chat_template(
        messages,
        tokenize=True,
        add_generation_prompt=True, 
        return_dict=True,
        return_tensors="pt",
    )

    inputs = {
        k: v.to(vlm_model.device) if hasattr(v, "to") else v
        for k, v in inputs.items()
    }

    # Serialize VLM calls by default to avoid concurrent VRAM spikes.
    lock = _vlm_lock if SERIALIZE_VLM else None
    if lock:
        lock.acquire()
    try:
        with torch.inference_mode():
            if torch.cuda.is_available():
                with torch.autocast("cuda", dtype=torch.float16):
                    generated_ids = vlm_model.generate(
                        **inputs,
                        max_new_tokens=MAX_NEW_TOKENS,
                        do_sample=False
                    )
            else:
                generated_ids = vlm_model.generate(
                    **inputs,
                    max_new_tokens=MAX_NEW_TOKENS,
                    do_sample=False

                )
    finally:
        if lock:
            lock.release()
        if torch.cuda.is_available():
            # Best-effort cache cleanup to reduce OOM risk on subsequent requests.
            torch.cuda.empty_cache()

    generated_ids_trimmed = [
        out_ids[len(in_ids):]
        for in_ids, out_ids in zip(inputs["input_ids"], generated_ids)
    ]

    output_text = vlm_processor.batch_decode(
        generated_ids_trimmed,
        skip_special_tokens=True,
        clean_up_tokenization_spaces=False,
    )

    return (output_text[0] if output_text else "").strip()


def infer_with_yolo(image_path: Path):
    """
    Returns list of detections in app-compatible format:
    [
      {"label": "bottle", "confidence": 0.91},
      ...
    ]
    """
    if yolo_model is None:
        raise RuntimeError(
            "YOLO model is not loaded. Install ultralytics and set YOLO_MODEL_PATH."
        )

    results = yolo_model(str(image_path))
    detections = []

    for r in results:
        names = r.names
        boxes = r.boxes
        if boxes is None:
            continue

        cls_list = boxes.cls.tolist() if boxes.cls is not None else []
        conf_list = boxes.conf.tolist() if boxes.conf is not None else []

        for idx, conf in zip(cls_list, conf_list):
            label = names[int(idx)] if isinstance(names, dict) else names[int(idx)]
            detections.append({
                "label": str(label),
                "confidence": float(conf),
            })

    return detections


@app.after_request
def cors_headers(response):
    response.headers["Access-Control-Allow-Origin"] = "*"
    response.headers["Access-Control-Allow-Methods"] = "POST, OPTIONS, GET"
    response.headers["Access-Control-Allow-Headers"] = "Content-Type"
    return response


@app.route("/health", methods=["GET"])
def health():
    return jsonify({
        "status": "ok",
        "upload_folder": str(UPLOAD_FOLDER),
        "ocr": "easyocr",
        "vlm": VLM_MODEL_NAME,
        "yolo_loaded": yolo_model is not None,
        "return_traceback": RETURN_TRACEBACK,
    })


@app.route("/upload", methods=["POST"])
def upload_image():
    if "image" not in request.files:
        return _json_error(400, "No image provided")

    image_file = request.files["image"]
    filename = secure_filename(image_file.filename or "upload.png")
    filepath = UPLOAD_FOLDER / filename
    image_file.save(str(filepath))

    return jsonify({
        "message": "Image received",
        "image_path": str(filepath)
    })


@app.route("/extract-text", methods=["OPTIONS"])
def extract_text_options():
    return "", 204


@app.route("/extract-text", methods=["POST"])
def extract_text():
    print("HIT /extract-text")
    print("content_type:", request.content_type)
    print("files:", list(request.files.keys()))

    if "image" not in request.files:
        return _json_error(400, "No image file provided")

    file_storage = request.files["image"]
    image_bytes = file_storage.read()

    try:
        image = Image.open(io.BytesIO(image_bytes)).convert("RGB")
    except Exception:
        return _json_error(400, "Could not read image")

    image_np = np.array(image)
    results: List[str] = reader.readtext(image_np, detail=0)
    full_text = "\n".join(results).strip() or "No text found"

    return jsonify({
        "full_text": full_text,
        "lines": results
    })


# ---------- VLM endpoint ----------
@app.route("/predict", methods=["OPTIONS"])
def predict_options():
    return "", 204


@app.route("/predict", methods=["POST"])
def predict():
    if "image" not in request.files:
        return _json_error(400, "No image file provided")

    file = request.files["image"]
    question = request.form.get(
            "question",
            """Identify every item on the shelf. For each item, provide a list entry exactly like this:
    - Brand: [Brand Name], Product: [Product Name], Location: [Shelf Position]
    
    Rules:
    1. One item per line.
    2. Be specific about location (e.g., 'middle shelf, second from left').
    3. Output ONLY the list. No introductory or closing text."""
    )

    system_message = (
        "You are a very strict inventory assistant. "
        "Your job is to describe every item on the shelf in a structured format exactly as instructed. "
        "Do NOT add commentary, explanations, or prices. "
        "Do NOT make assumptions about items you cannot clearly see. "
        "Always include the following fields for each item:\n"
        "- brand\n"
        "- product_name\n"
        "- location (use top/middle/bottom and left/center/right)\n"
        "Output exactly one item per line, in the format:\n"
        "brand: <brand>, product_name: <product>, location: <location>\n"
        "Do NOT output JSON unless explicitly requested. "
        "Follow this format strictly."
    )

    filename = secure_filename(file.filename or "vlm.png")
    filepath = UPLOAD_FOLDER / filename
    file.save(str(filepath))

    try:
        answer = infer_with_vlm(filepath, question)
        if not answer:
            return jsonify({
                "image_path": str(filepath),
                "question": question,
                "answer": "",
                "warning": "VLM returned empty answer"
            })
        return jsonify({
            "image_path": str(filepath),
            "question": question,
            "answer": answer
        })
    except Exception as e:
        tb = traceback.format_exc()
        # This print is what you were missing in terminal output.
        print("\n=== /predict ERROR TRACEBACK ===\n" + tb + "\n=== END TRACEBACK ===\n")
        return _json_error(500, str(e), tb)


# ---------- YOLO endpoint ----------
@app.route("/detect-yolo", methods=["OPTIONS"])
def detect_yolo_options():
    return "", 204


@app.route("/detect-yolo", methods=["POST"])
def detect_yolo():
    if "image" not in request.files:
        return _json_error(400, "No image file provided")

    file = request.files["image"]
    filename = secure_filename(file.filename or "yolo.png")
    filepath = UPLOAD_FOLDER / filename
    file.save(str(filepath))

    try:
        detections = infer_with_yolo(filepath)
        return jsonify(detections)
    except Exception as e:
        tb = traceback.format_exc()
        print("\n=== /detect-yolo ERROR TRACEBACK ===\n" + tb + "\n=== END TRACEBACK ===\n")
        return _json_error(500, str(e), tb)


if __name__ == "__main__":
    # Turning off the reloader makes logs easier to read.
    app.run(host="0.0.0.0", port=5010, debug=True, use_reloader=False)


@app.route("/ping-post", methods=["POST"])
def ping_post():
    return jsonify({
        "status": "ok",
        "content_type": request.content_type,
        "content_length": request.content_length,
        "files": list(request.files.keys()),
        "form": list(request.form.keys()),
    })