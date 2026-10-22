





import math
from datetime import datetime
from scipy.spatial import ConvexHull
import numpy as np
import firebase_client
import config






def haversine(lat1, lng1, lat2, lng2):
    """Returns distance in metres between two GPS coordinates."""
    R = 6371000
    phi1, phi2 = math.radians(lat1), math.radians(lat2)
    dphi = math.radians(lat2 - lat1)
    dlambda = math.radians(lng2 - lng1)
    a = (math.sin(dphi / 2) ** 2
         + math.cos(phi1) * math.cos(phi2) * math.sin(dlambda / 2) ** 2)
    return R * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a))






def total_daily_distance(points):
    """
    Sum of Haversine distances between consecutive GPS fixes.
    Unit: metres. Represents baseline activity level.
    """
    if len(points) < 2:
        return 0.0
    total = 0.0
    for i in range(len(points) - 1):
        total += haversine(
            points[i]['latitude'],  points[i]['longitude'],
            points[i+1]['latitude'], points[i+1]['longitude']
        )
    return round(total, 2)






def average_speed(points):
    """
    Mean speed across all GPS fixes.
    Unit: m/s. Represents intensity of locomotion.
    """
    if not points:
        return 0.0
    speeds = [p['speed'] for p in points if p['speed'] >= 0]
    return round(sum(speeds) / len(speeds), 4) if speeds else 0.0






def peak_speed(points, window_minutes=5, interval_minutes=15):
    """
    Maximum speed recorded in any time window.
    Unit: m/s. Captures burst activity episodes.
    """
    if not points:
        return 0.0
    speeds = [p['speed'] for p in points if p['speed'] >= 0]
    return round(max(speeds), 4) if speeds else 0.0






def gps_acceleration(points):
    """
    Mean absolute rate of speed change between consecutive fixes.
    Unit: m/s². Movement intensity without inertial sensor.
    """
    if len(points) < 2:
        return 0.0
    accels = []
    for i in range(len(points) - 1):
        dt_ms = points[i+1]['timestamp'] - points[i]['timestamp']
        if dt_ms <= 0:
            continue
        dt_s = dt_ms / 1000.0
        dv = abs(points[i+1]['speed'] - points[i]['speed'])
        accels.append(dv / dt_s)
    return round(sum(accels) / len(accels), 6) if accels else 0.0






def home_zone_dwell_time(points, geofences):
    """
    Total minutes the pet spent inside any active geofence zone.
    Unit: minutes. Represents spatial routine adherence.
    If no geofences are configured, uses a circle around
    the first GPS fix of the day as the 'home' zone.
    """
    if not points:
        return 0.0

    if not geofences:
        
        home_lat = points[0]['latitude']
        home_lng = points[0]['longitude']
        zones = [{'latitude': home_lat, 'longitude': home_lng,
                  'radiusM': config.HOME_ZONE_RADIUS_M}]
    else:
        zones = geofences

    
    
    interval_min = (24 * 60) / len(points) if points else 15
    minutes_inside = 0.0

    for p in points:
        for zone in zones:
            dist = haversine(
                p['latitude'], p['longitude'],
                zone['latitude'], zone['longitude']
            )
            if dist <= zone['radiusM']:
                minutes_inside += interval_min
                break  

    return round(minutes_inside, 2)






def active_time_proportion(points):
    """
    Fraction of GPS fixes where speed exceeds ACTIVE_SPEED_THRESHOLD.
    Range: 0.0 - 1.0. Represents active ratio vs rest.
    """
    if not points:
        return 0.0
    active = sum(
        1 for p in points
        if p['speed'] >= config.ACTIVE_SPEED_THRESHOLD
    )
    return round(active / len(points), 4)






def spatial_range_area(points):
    """
    Area of the convex hull of all GPS positions for the day.
    Unit: square metres (approximated via lat/lng to metres conversion).
    Represents roaming extent.
    """
    if len(points) < 3:
        return 0.0
    try:
        
        lats = [p['latitude']  for p in points]
        lngs = [p['longitude'] for p in points]
        clat = sum(lats) / len(lats)
        clng = sum(lngs) / len(lngs)

        
        
        lat_scale = 111139.0
        lng_scale = 111139.0 * math.cos(math.radians(clat))

        coords = np.array([
            [(p['latitude']  - clat) * lat_scale,
             (p['longitude'] - clng) * lng_scale]
            for p in points
        ])

        hull = ConvexHull(coords)
        return round(hull.volume, 2)  
    except Exception:
        return 0.0






def temporal_activity_pattern(points):
    """
    Shannon entropy of the hour-of-day distribution of active fixes.
    Higher entropy = more varied activity timing (normal).
    Lower entropy = very predictable or no activity (potential anomaly).
    Unit: bits.
    """
    if not points:
        return 0.0

    hour_counts = [0] * 24
    for p in points:
        if p['speed'] >= config.ACTIVE_SPEED_THRESHOLD:
            ts_sec = p['timestamp'] / 1000.0
            hour = datetime.fromtimestamp(ts_sec).hour
            hour_counts[hour] += 1

    total = sum(hour_counts)
    if total == 0:
        return 0.0

    entropy = 0.0
    for count in hour_counts:
        if count > 0:
            prob = count / total
            entropy -= prob * math.log2(prob)

    return round(entropy, 4)






def extract_features(pet_id: str, date_str: str):
    """
    Extracts all 8 features for a given pet and date.
    Reads GPS logs from Firebase, computes features, writes to Firebase.
    Returns the feature dict or None if not enough data.
    """
    print(f"[Extractor] Extracting features for pet={pet_id} date={date_str}")

    points = firebase_client.get_gps_logs_for_date(pet_id, date_str)

    if len(points) < 5:
        print(f"[Extractor] Not enough GPS points ({len(points)}) — skipping")
        return None

    geofences = firebase_client.get_geofences(pet_id)

    features = {
        'totalDistance':      total_daily_distance(points),
        'avgSpeed':           average_speed(points),
        'peakSpeed':          peak_speed(points),
        'gpsAcceleration':    gps_acceleration(points),
        'homeZoneDwellTime':  home_zone_dwell_time(points, geofences),
        'activeTimePct':      active_time_proportion(points) * 100,
        'spatialRangeArea':   spatial_range_area(points),
        'temporalEntropy':    temporal_activity_pattern(points),
    }

    print(f"[Extractor] Features: {features}")

    
    firebase_client.write_daily_behaviour(pet_id, date_str, features)

    return features


def extract_features_date_range(pet_id: str, dates: list):
    """
    Extracts features for multiple dates.
    Returns list of feature dicts with 'date' key added.
    """
    results = []
    for date_str in dates:
        feats = extract_features(pet_id, date_str)
        if feats:
            results.append({**feats, 'date': date_str})
    return results


if __name__ == '__main__':
    from datetime import timedelta
    firebase_client.init_firebase()

    pets = firebase_client.get_all_pets()
    if not pets:
        print("No pets found. Add a pet in the app first.")
    else:
        pet = pets[0]
        print(f"Extracting features for: {pet['name']}")

        
        today = datetime.now()
        dates = [
            (today - timedelta(days=i)).strftime('%Y-%m-%d')
            for i in range(29, -1, -1)
        ]
        results = extract_features_date_range(pet['petId'], dates)
        print(f"\nExtracted {len(results)} days of features.")