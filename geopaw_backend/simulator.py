






import math
import random
import time
from datetime import datetime, timedelta
import firebase_client
import config

def haversine_distance(lat1, lng1, lat2, lng2):
    """Returns distance in metres between two GPS coordinates."""
    R = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = math.sin(dphi/2)**2 + math.cos(phi1)*math.cos(phi2)*math.sin(dlambda/2)**2
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1-a))

def generate_daily_path(base_lat, base_lng, is_anomaly=False):
    """
    Generates a realistic list of GPS points for one day.
    Normal day: pet goes for walks, comes home, rests.
    Anomaly day: pet barely moves (simulates illness/distress).
    Returns list of (lat, lng, speed_ms) tuples.
    """
    points = []
    lat, lng = base_lat, base_lng

    if is_anomaly:
        
        for i in range(config.SIM_POINTS_PER_DAY):
            
            lat += random.gauss(0, 0.00001)
            lng += random.gauss(0, 0.00001)
            speed = random.uniform(0, 0.1)  
            points.append((lat, lng, speed))
    else:
        
        
        
        
        
        
        

        walk_angle = random.uniform(0, 2 * math.pi)

        for i in range(config.SIM_POINTS_PER_DAY):
            if 8 <= i < 20:
                
                step = random.gauss(0.0003, 0.0001)
                lat += step * math.cos(walk_angle) + random.gauss(0, 0.00005)
                lng += step * math.sin(walk_angle) + random.gauss(0, 0.00005)
                speed = random.uniform(0.8, 1.8)

            elif 20 <= i < 40:
                
                dlat = (base_lat - lat) * 0.15
                dlng = (base_lng - lng) * 0.15
                lat += dlat + random.gauss(0, 0.00003)
                lng += dlng + random.gauss(0, 0.00003)
                speed = random.uniform(0.2, 0.8) if i < 30 else random.uniform(0, 0.2)

            elif 40 <= i < 55:
                
                angle2 = walk_angle + math.pi * 0.7
                step = random.gauss(0.0002, 0.0001)
                lat += step * math.cos(angle2) + random.gauss(0, 0.00005)
                lng += step * math.sin(angle2) + random.gauss(0, 0.00005)
                speed = random.uniform(0.6, 1.4)

            elif 55 <= i < 80:
                
                dlat = (base_lat - lat) * 0.2
                dlng = (base_lng - lng) * 0.2
                lat += dlat + random.gauss(0, 0.00002)
                lng += dlng + random.gauss(0, 0.00002)
                speed = random.uniform(0, 0.3)

            elif 80 <= i < 90:
                
                angle3 = walk_angle + math.pi * 1.3
                step = random.gauss(0.0001, 0.00005)
                lat += step * math.cos(angle3)
                lng += step * math.sin(angle3)
                speed = random.uniform(0.5, 1.2)

            else:
                
                lat = base_lat + random.gauss(0, 0.00002)
                lng = base_lng + random.gauss(0, 0.00002)
                speed = random.uniform(0, 0.1)

            points.append((lat, lng, max(0, speed)))

    return points

def simulate_historical_data(pet_id, days=30, anomaly_days=None):
    """
    Writes [days] days of simulated GPS history to Firebase.
    anomaly_days: list of day indices (0=oldest) that should be anomalous.
    If None, randomly picks 2 anomaly days after day 14 (after baseline period).
    """
    if anomaly_days is None:
        
        anomaly_days = random.sample(range(14, days), 2)

    print(f"[Simulator] Generating {days} days of GPS history for pet: {pet_id}")
    print(f"[Simulator] Anomaly days (0-indexed): {anomaly_days}")

    now = datetime.now()

    for day_idx in range(days):
        date = now - timedelta(days=(days - 1 - day_idx))
        date_str = date.strftime('%Y-%m-%d')
        is_anomaly = day_idx in anomaly_days

        points = generate_daily_path(
            config.SIM_BASE_LAT,
            config.SIM_BASE_LNG,
            is_anomaly=is_anomaly
        )

        
        
        day_start_ts = int(datetime(date.year, date.month, date.day, 0, 0, 0).timestamp() * 1000)
        interval_ms = (24 * 60 * 60 * 1000) // config.SIM_POINTS_PER_DAY

        for i, (lat, lng, speed) in enumerate(points):
            ts = day_start_ts + i * interval_ms
            firebase_client.write_gps_point(pet_id, date_str, {
                'latitude': round(lat, 6),
                'longitude': round(lng, 6),
                'speed': round(speed, 3),
                'timestamp': ts,
            })

        status = "⚠️  ANOMALY" if is_anomaly else "✅ normal"
        print(f"[Simulator] Day {day_idx+1}/{days} ({date_str}) — {status} — {len(points)} points written")

    print(f"[Simulator] Done. Historical data written for pet: {pet_id}")

def simulate_live(pet_id, interval_sec=15):
    """
    Continuously writes live GPS points to Firebase,
    simulating the real hardware updating every [interval_sec] seconds.
    Press Ctrl+C to stop.
    """
    print(f"[Simulator] Live simulation started for pet: {pet_id}")
    print(f"[Simulator] Updating every {interval_sec} seconds. Press Ctrl+C to stop.")

    lat = config.SIM_BASE_LAT
    lng = config.SIM_BASE_LNG
    angle = random.uniform(0, 2 * math.pi)

    try:
        while True:
            
            step = random.gauss(0.0001, 0.00005)
            angle += random.gauss(0, 0.3)
            lat += step * math.cos(angle)
            lng += step * math.sin(angle)

            
            dist = haversine_distance(lat, lng, config.SIM_BASE_LAT, config.SIM_BASE_LNG)
            if dist > 500:
                
                lat += (config.SIM_BASE_LAT - lat) * 0.1
                lng += (config.SIM_BASE_LNG - lng) * 0.1
                angle += math.pi  

            speed = abs(random.gauss(0.8, 0.3))
            ts = int(time.time() * 1000)
            date_str = datetime.now().strftime('%Y-%m-%d')

            point = {
                'latitude': round(lat, 6),
                'longitude': round(lng, 6),
                'speed': round(speed, 3),
                'timestamp': ts,
            }

            firebase_client.write_gps_point(pet_id, date_str, point)
            print(f"[Live] lat={lat:.6f} lng={lng:.6f} speed={speed:.2f} m/s")

            time.sleep(interval_sec)

    except KeyboardInterrupt:
        print("\n[Simulator] Live simulation stopped.")

if __name__ == '__main__':
    firebase_client.init_firebase()
    pets = firebase_client.get_all_pets()

    if not pets:
        print("[Simulator] No pets found in Firebase.")
        print("Please add a pet in the GeoPaw app first, then run this again.")
    else:
        print(f"[Simulator] Found {len(pets)} pet(s):")
        for i, p in enumerate(pets):
            print(f"  {i+1}. {p['name']} ({p['species']}) — ID: {p['petId']}")

        
        
        pet = None
        while pet is None:
            choice = input(f"\nSelect a pet (1-{len(pets)}): ").strip()
            if choice.isdigit() and 1 <= int(choice) <= len(pets):
                pet = pets[int(choice) - 1]
            else:
                print(f"Please enter a number between 1 and {len(pets)}.")

        print(f"\n[Simulator] Using: {pet['name']}")
        print("\nWhat would you like to do?")
        print("  1. Generate 30 days of historical data (for ML training)")
        print("  2. Start live GPS simulation")
        action = input("Enter 1 or 2: ").strip()

        if action == '1':
            simulate_historical_data(pet['petId'], days=30)
        elif action == '2':
            simulate_live(pet['petId'])
        else:
            print("Invalid choice.")