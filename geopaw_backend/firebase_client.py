




import firebase_admin
from firebase_admin import credentials, db
from datetime import datetime
import config

_initialized = False

def init_firebase():
    """Initialize Firebase Admin SDK. Call once at startup."""
    global _initialized
    if not _initialized:
        cred = credentials.Certificate(config.SERVICE_ACCOUNT_KEY)
        firebase_admin.initialize_app(cred, {
            'databaseURL': config.DATABASE_URL
        })
        _initialized = True
        print("[Firebase] Connected successfully")





def get_all_pets():
    """
    Returns a flat list of all pets across all users.
    Format: [{'petId': str, 'uid': str, 'name': str, 'species': str}, ...]
    """
    pets_ref = db.reference('pets')
    all_users = pets_ref.get()
    result = []
    if not all_users:
        return result
    for uid, user_pets in all_users.items():
        if isinstance(user_pets, dict):
            for pet_id, pet_data in user_pets.items():
                if isinstance(pet_data, dict):
                    result.append({
                        'petId': pet_id,
                        'uid': uid,
                        'name': pet_data.get('name', 'Unknown'),
                        'species': pet_data.get('species', 'Other'),
                    })
    return result





def get_gps_logs_for_date(pet_id: str, date_str: str):
    """
    Returns list of GPS log entries for a pet on a given date.
    date_str format: 'YYYY-MM-DD'
    Returns: [{'latitude': float, 'longitude': float,
                'speed': float, 'timestamp': int}, ...]
    """
    ref = db.reference(f'gps_logs/{pet_id}/{date_str}')
    data = ref.get()
    if not data or not isinstance(data, dict):
        return []
    entries = []
    for key, val in data.items():
        if isinstance(val, dict):
            entries.append({
                'latitude':  float(val.get('latitude',  0)),
                'longitude': float(val.get('longitude', 0)),
                'speed':     float(val.get('speed',     0)),
                'timestamp': int(val.get('timestamp',   0)),
            })
    
    entries.sort(key=lambda x: x['timestamp'])
    return entries

def write_gps_point(pet_id: str, date_str: str, point: dict):
    """
    Writes a single GPS point to Firebase.
    Used by the simulator.
    """
    ref = db.reference(f'gps_logs/{pet_id}/{date_str}')
    ref.push(point)
    
    db.reference(f'gps_logs/{pet_id}/latest').set(point)





def write_daily_behaviour(pet_id: str, date_str: str, features: dict):
    """
    Writes the extracted daily feature vector to Firebase.
    Path: behaviour/{petId}/{date}/
    """
    ref = db.reference(f'behaviour/{pet_id}/{date_str}')
    ref.set({**features, 'date': date_str})
    print(f"[Firebase] Wrote behaviour for pet={pet_id} date={date_str}")

def get_behaviour_history(pet_id: str, days: int = 30):
    """
    Returns up to [days] daily behaviour records for a pet.
    Returns: list of feature dicts sorted oldest first.
    """
    ref = db.reference(f'behaviour/{pet_id}')
    data = ref.get()
    if not data or not isinstance(data, dict):
        return []
    records = []
    for date_str, val in data.items():
        if isinstance(val, dict):
            records.append({**val, 'date': date_str})
    records.sort(key=lambda x: x['date'])
    return records[-days:]





def write_alert(pet_id: str, alert_type: str, title: str, description: str):
    """
    Writes an alert to Firebase.
    Path: alerts/{petId}/{alertId}
    alert_type: 'geofence' | 'anomaly'
    """
    ref = db.reference(f'alerts/{pet_id}')
    ref.push({
        'type': alert_type,
        'title': title,
        'description': description,
        'acknowledged': False,
        'timestamp': {'.sv': 'timestamp'},
    })
    print(f"[Firebase] Alert written: [{alert_type}] {title} for pet={pet_id}")





def get_geofences(pet_id: str):
    """
    Returns all active geofence zones for a pet.
    Returns: [{'id': str, 'latitude': float, 'longitude': float,
                'radiusM': float, 'name': str}, ...]
    """
    ref = db.reference(f'geofences/{pet_id}')
    data = ref.get()
    if not data or not isinstance(data, dict):
        return []
    zones = []
    for zone_id, val in data.items():
        if isinstance(val, dict) and val.get('active', False):
            zones.append({
                'id':        zone_id,
                'name':      val.get('name', 'Zone'),
                'latitude':  float(val.get('latitude',  0)),
                'longitude': float(val.get('longitude', 0)),
                'radiusM':   float(val.get('radiusM',   200)),
            })
    return zones