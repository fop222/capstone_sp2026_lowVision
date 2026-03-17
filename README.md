# my_low_vision_app

A Flutter app for low-vision users that combines Supabase-backed grocery list management, guided aisle/shelf OCR shopping mode, voice-guided item entry (TTS + STT), and EasyOCR text extraction from the camera.

## Getting Started

### Prerequisites

- [Flutter](https://docs.flutter.dev/get-started/install) installed
- Python 3 with required packages (see steps below)
- A Supabase project (already configured — credentials are in `lib/main.dart`)
- Chrome browser for web

---

## How to Run the Program

You need **three terminals** running at the same time.

---

### Terminal 1 — Flask backend (user profiles API)

```bash
cd capstone_sp2026_lowVision\backend2
$env:FLASK_ENV="development"
.\.venv\Scripts\python app.py
```

> First time only — set up the virtual environment:
> ```bash
> python -m venv .venv
> .\.venv\Scripts\activate
> pip install -r requirements.txt
> ```

You should see the server running on `http://127.0.0.1:5000`.

---

### Terminal 2 — OCR server (EasyOCR)

```bash
cd capstone_sp2026_lowVision
python ocr_server.py
```

> First time only — install dependencies:
> ```bash
> pip install easyocr flask pillow numpy
> ```

You should see the server running on `http://0.0.0.0:5001`.  
*(Note: EasyOCR downloads its AI models on first run — this takes a few minutes.)*

---

### Terminal 3 — Flutter app

```bash
cd capstone_sp2026_lowVision
flutter pub get
flutter run -d chrome
```

Open Chrome and the app will launch automatically.

---

## Quick checklist

| Step | Terminal | Command |
|------|----------|---------|
| 1. Install Flutter deps | Terminal 3 | `flutter pub get` |
| 2. Start Flask backend | Terminal 1 | `cd backend2` → `$env:FLASK_ENV="development"` → `.\.venv\Scripts\python app.py` |
| 3. Start OCR server | Terminal 2 | `python ocr_server.py` |
| 4. Run app in Chrome | Terminal 3 | `flutter run -d chrome` |

---

## Features

- **Supabase authentication** — email/password signup and login
- **User profile** — set dietary preferences and allergies on signup; edit any time via the person icon
- **Grocery lists** — create, view, and delete lists per user
- **Grocery items** — add items manually or via voice (TTS guides you, STT captures your answer)
- **Aisle scanner shopping mode** — tap the cart icon on a list to start shopping:
  1. Point camera at the **aisle sign** → OCR detects which list items are in that aisle (read aloud via TTS)
  2. Point camera at the **shelf** → OCR detects items visible on the shelf
  3. Check off items, then move to the next aisle — list stays sorted in the order you walk the aisles
  4. Audio can be muted/unmuted at any time with the volume button
- **OCR camera** — point at any text and extract it with EasyOCR (camera icon on grocery lists screen)

---

## Server ports

| Server | Port |
|--------|------|
| Flask backend (user profiles) | 5000 |
| EasyOCR server | 5001 |
| Flutter web app (auto-assigned) | ~52161 |

---

## Project resources

- [Flutter documentation](https://docs.flutter.dev/)
- [Supabase documentation](https://supabase.com/docs)
- [EasyOCR GitHub](https://github.com/JaidedAI/EasyOCR)
