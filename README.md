# ProxyProof — BLE Attendance Engine 📱⚡

**ProxyProof** is an anti-proxy classroom attendance system powered by dynamic Bluetooth Low Energy (BLE) rotating tokens, hardware-bound device authentication, and RSSI signal proximity verification[cite: 1].

---

## 🎯 Core Features

* **Dynamic Rotating BLE Tokens:** The organiser's phone continuously broadcasts time-sensitive HMAC tokens via BLE without requiring device pairing[cite: 1].
* **Hardware-Locked Device Binding:** Each student is strictly bound to a single registered device hardware ID to prevent proxy check-ins on behalf of absent peers[cite: 1].
* **RSSI Signal Proximity Thresholding:** Server-side signal strength checks verify that student devices are physically inside the classroom rather than adjacent hallways[cite: 1].
* **Real-Time Organiser Live Dashboard:** View incoming check-ins instantaneously with session control and manual add/remove options[cite: 1].
* **Automated Data Export:** Download verified attendance reports in CSV format for record-keeping[cite: 1].

---

## 🛠️ Tech Stack

* **Mobile App:** Flutter (`flutter_blue_plus`, `flutter_ble_peripheral`, `device_info_plus`, `http`, `crypto`)
* **Backend Service:** FastAPI (Python), Uvicorn, Pydantic

---

## 🚀 Quick Start

### 1. Backend Setup (FastAPI)
```bash
cd backend
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
uvicorn main:app --reload --host 0.0.0.0 --port 8000
