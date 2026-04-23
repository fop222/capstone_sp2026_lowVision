# 🛒 my_low_vision_app

A Flutter app designed for low-vision users, combining **grocery list management**, **aisle/shelf scanning**, and **voice-guided interaction** powered by VLM + OCR.

---

## 🚀 Quick Start

## 👉 Choose how you want to run the app:

### 🟢 Option A: Run Locally

* Runs everything on your machine
* Best for development

👉 Go to **Steps 1, 2, 4 (Local Setup)**

---

### 🔵 Option B: Use Deployed App (Vercel)

* Uses hosted frontend on Vercel
* Requires ngrok to connect MAGIC backend

👉 Follow **Steps 2 → 3**

---

## 1️⃣ Start Flask Backend (Profiles & Lists)

```bash
cd backend2
$env:FLASK_ENV = "development"
.venv\Scripts\python app.py
```

---

## 2️⃣ Set up and Start VLM Server (MAGIC)

### Terminal 1

```bash
cd "VLM Testing"

conda create -n magic-vlm python=3.10 -y
conda activate magic-vlm

pip install flask easyocr ultralytics
pip install transformers accelerate pillow

python app_server_VLM.py
```

---

## 🌐 3️⃣ Start ngrok (ONLY if using Vercel)

### Terminal 2

```bash
./ngrok http 5010
```

You will see:

```
Forwarding https://abc123.ngrok-free.dev -> http://localhost:5010
```

👉 Copy the HTTPS URL

---

### 🔧 Update Vercel Environment Variable (only if URL differs from https://stardust-citable-trout.ngrok-free.dev)

Set:

```
OCR_PROXY_TARGET=https://abc123.ngrok-free.dev
```

Then redeploy your Vercel app

👉 Skip this if running locally

---

## 🌐 Vercel App

👉 Open:
[https://capstone-sp2026-low-vision.vercel.app/](https://capstone-sp2026-low-vision.vercel.app/)

---

## 💻 4️⃣ Local Setup (Run Everything Locally)

```bash
flutter clean
flutter pub get
flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010
```

---

## 📱 Running on Different Devices

| Device             | Command                                                                        |
| ------------------ | ------------------------------------------------------------------------------ |
| Web (Chrome)       | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010` |
| Android emulator   | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5010`                  |
| Phone (same Wi-Fi) | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5010`            |

---

## ⚠️ Important Notes

* ngrok must stay running:

```bash
./ngrok http 5010
```

* If ngrok stops → deployed app breaks
* Free ngrok URLs change each restart → update Vercel

---

## ✨ Features

* Supabase authentication
* Grocery lists
* Voice interaction (TTS/STT)
* Aisle scanning (OCR)
* Shelf scanning (VLM)
* Accessible UI

---

## 📚 Resources

* [https://docs.flutter.dev/](https://docs.flutter.dev/)
* [https://supabase.com/docs](https://supabase.com/docs)
* [https://github.com/JaidedAI/EasyOCR](https://github.com/JaidedAI/EasyOCR)
