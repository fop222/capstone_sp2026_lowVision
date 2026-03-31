# my_low_vision_app

A Flutter app for low-vision users that combines Supabase-backed grocery list management, guided aisle/shelf scanning, VLM + OCR support, and voice-guided interaction.

---

## 🚀 How to Run (Simple)

### 1. Start Flask backend (profiles / lists)

```bash
cd backend2
python app.py
```

---

### 2. Start VLM server (MAGIC)

```bash
cd "VLM Testing"
python app_server_VLM.py
```

---

### 3. Run Flutter app (from root folder)

```bash
flutter clean
flutter pub get
flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010
```

---

## 📱 Running on Different Devices

| Where you run the app       | Command                                                                        |
| --------------------------- | ------------------------------------------------------------------------------ |
| Web (Chrome)                | `flutter run -d chrome --dart-define=OCR_BASE_URL=http://128.180.121.230:5010` |
| Android emulator            | `flutter run --dart-define=OCR_BASE_URL=http://10.0.2.2:5010`                  |
| Physical phone (same Wi-Fi) | `flutter run --dart-define=OCR_BASE_URL=http://YOUR_PC_LAN_IP:5010`            |

👉 You can override anytime:

```
--dart-define=OCR_BASE_URL=http://your-server-ip:5010
```

---

## ⚙️ Architecture Overview

* **Flutter frontend** → UI + camera + TTS/STT
* **Flask backend (backend2)** → users, grocery lists
* **VLM server (MAGIC)** → image understanding (Qwen3-VL)
* **EasyOCR (optional/local)** → text extraction

---

## ✨ Features

* **Supabase authentication** — login/signup
* **User profiles** — allergies + dietary preferences
* **Grocery lists** — create, manage, delete
* **Voice input (TTS + STT)** — guided item entry
* **Aisle scanner**

  * Detect aisle via OCR / VLM
  * Tell user what items are in that aisle
* **Shelf scanner**

  * Detect visible grocery items (YOLO or VLM)
* **Accessible UX**

  * Audio feedback
  * Simple interaction flow

---

## 🔌 Server Ports

| Service            | Port |
| ------------------ | ---- |
| Flask backend      | 5000 |
| VLM server (MAGIC) | 5010 |

---

## 📚 Project resources

* [Flutter documentation](https://docs.flutter.dev/)
* [Supabase documentation](https://supabase.com/docs)
* [EasyOCR GitHub](https://github.com/JaidedAI/EasyOCR)

