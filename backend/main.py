import hmac
import hashlib
import time
import uuid
from typing import List, Dict
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

app = FastAPI(title="ProxyProof API", version="1.0.0")

# In-memory Database (Replace with PostgreSQL / Supabase for production)
sessions_db: Dict[str, dict] = {}
students_db: Dict[str, dict] = {
    "STU123": {"device_id": "HW-999-XYZ", "name": "Student One"}
}
attendance_db: List[dict] = []

class StartSessionReq(BaseModel):
    duration_minutes: int = 5

class MarkAttendanceReq(BaseModel):
    student_id: str
    session_id: str
    token: str
    device_id: str
    rssi: int

def generate_token(secret: str, timestamp: float) -> str:
    """Generates a 6-character HMAC token rotating every 10 seconds."""
    time_window = int(timestamp / 10)
    h = hmac.new(secret.encode(), str(time_window).encode(), hashlib.sha256)
    return h.hexdigest()[:6]

@app.post("/api/sessions/start")
def start_session(req: StartSessionReq):
    session_id = str(uuid.uuid4())[:8]
    secret_key = str(uuid.uuid4())
    
    sessions_db[session_id] = {
        "secret_key": secret_key,
        "expires_at": time.time() + (req.duration_minutes * 60)
    }
    return {"session_id": session_id, "secret_key": secret_key}

@app.post("/api/attendance/mark")
def mark_attendance(req: MarkAttendanceReq):
    session = sessions_db.get(req.session_id)
    if not session:
        raise HTTPException(status_code=404, detail="Session not found")
        
    if time.time() > session["expires_at"]:
        raise HTTPException(status_code=400, detail="Session has closed")

    # Anti-Proxy Rule 1: Hardware Binding Check
    student = students_db.get(req.student_id)
    if not student:
        # Auto-bind first device during initial check-in
        students_db[req.student_id] = {"device_id": req.device_id, "name": req.student_id}
        student = students_db[req.student_id]
    elif student["device_id"] != req.device_id:
        raise HTTPException(status_code=403, detail="Device mismatch - Proxy attempt blocked")

    # Anti-Proxy Rule 2: RSSI Signal Proximity Verification
    if req.rssi < -75:
        raise HTTPException(status_code=400, detail="Signal too weak. You must be physically inside the room.")

    # Anti-Proxy Rule 3: Dynamic Rotating Token Validation
    current_time = time.time()
    valid_tokens = [
        generate_token(session["secret_key"], current_time),
        generate_token(session["secret_key"], current_time - 10),
        generate_token(session["secret_key"], current_time + 10)
    ]
    
    if req.token not in valid_tokens:
        raise HTTPException(status_code=401, detail="Invalid or expired BLE token")
        
    # Prevent Duplicate Attendance
    if any(a["student_id"] == req.student_id and a["session_id"] == req.session_id for a in attendance_db):
        return {"status": "Already marked", "message": "Attendance already recorded for this session."}

    attendance_record = {
        "student_id": req.student_id,
        "session_id": req.session_id,
        "timestamp": time.time(),
        "rssi": req.rssi
    }
    attendance_db.append(attendance_record)
    return {"status": "Success", "message": "Attendance verified and marked"}

@app.get("/api/sessions/{session_id}/attendance")
def get_session_attendance(session_id: str):
    records = [a for a in attendance_db if a["session_id"] == session_id]
    return {"session_id": session_id, "count": len(records), "records": records}
