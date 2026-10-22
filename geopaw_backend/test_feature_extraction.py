










import math
import feature_extractor as fx
import config

PASS = "PASS"
FAIL = "FAIL"
results = []


def check(name, actual, expected, tol_abs=None, tol_rel=None, note=""):
    """Compares actual vs expected within an absolute or relative tolerance."""
    if tol_abs is not None:
        ok = abs(actual - expected) <= tol_abs
    elif tol_rel is not None:
        ok = abs(actual - expected) <= abs(expected) * tol_rel
    else:
        ok = actual == expected
    status = PASS if ok else FAIL
    results.append((name, status))
    print(f"[{status}] {name}")
    print(f"       expected = {expected}")
    print(f"       actual   = {actual}")
    if note:
        print(f"       note: {note}")
    print()


def make_point(lat, lng, speed, ts_ms):
    return {"latitude": lat, "longitude": lng, "speed": speed, "timestamp": ts_ms}











def test_total_distance():
    R = 6371000
    base_lat, lng = 6.9271, 79.8612
    step_deg = 0.001  
    n_steps = 5

    points = []
    ts = 0
    for i in range(n_steps + 1):
        lat = base_lat + i * step_deg
        points.append(make_point(lat, lng, 1.0, ts))
        ts += 15 * 60 * 1000  

    expected_per_step = R * math.radians(step_deg)
    expected_total = round(expected_per_step * n_steps, 2)

    actual = fx.total_daily_distance(points)
    check(
        "18.1 Total distance (5 x ~111m meridian steps)",
        actual, expected_total, tol_abs=0.05,
        note="Same-longitude points make haversine reduce to an exact "
             "R*dphi arc length, so this expected value is exact."
    )








def test_avg_and_peak_speed():
    speeds = [0.2, 0.5, 1.3, 2.7, 0.9, 1.1, 3.4, 0.0]
    points = [make_point(6.9271, 79.8612, s, i * 900000) for i, s in enumerate(speeds)]

    expected_avg = round(sum(speeds) / len(speeds), 4)
    expected_peak = round(max(speeds), 4)

    check("18.2a Average speed", fx.average_speed(points), expected_avg, tol_abs=1e-6)
    check("18.2b Peak speed", fx.peak_speed(points), expected_peak, tol_abs=1e-6)








def test_active_time_proportion():
    threshold = config.ACTIVE_SPEED_THRESHOLD
    below = [max(0.0, threshold - 0.2)] * 4       
    above = [threshold + 0.3] * 6                  
    speeds = below + above
    points = [make_point(6.9271, 79.8612, s, i * 900000) for i, s in enumerate(speeds)]

    expected = round(6 / 10, 4)
    actual = fx.active_time_proportion(points)
    check(
        f"18.3 Active time proportion (threshold={threshold} m/s)",
        actual, expected, tol_abs=1e-6
    )














def test_spatial_range_area():
    base_lat, base_lng = 6.9271, 79.8612
    lat_scale = 111139.0
    lng_scale = 111139.0 * math.cos(math.radians(base_lat))

    width_m, height_m = 200.0, 100.0  
    corners_m = [(0, 0), (width_m, 0), (width_m, height_m), (0, height_m)]

    points = []
    for i, (x, y) in enumerate(corners_m):
        lat = base_lat + (y / lat_scale)
        lng = base_lng + (x / lng_scale)
        points.append(make_point(lat, lng, 1.0, i * 900000))

    expected_area = width_m * height_m  
    actual = fx.spatial_range_area(points)
    check(
        "18.4 Convex hull area (200m x 100m rectangle)",
        actual, expected_area, tol_rel=0.01,
        note="Points are an exact rectangle in local metres, inverse-"
             "transformed with the extractor's own scale factors."
    )






def test_temporal_entropy():
    threshold = config.ACTIVE_SPEED_THRESHOLD
    active_speed = threshold + 0.5

    def ts_for_hour(hour, minute=0):
        
        from datetime import datetime
        dt = datetime(2026, 1, 1, hour, minute, 0)
        return int(dt.timestamp() * 1000)

    
    low_points = []
    for i in range(12):
        hour = 9 + (i % 2)
        low_points.append(make_point(6.9271, 79.8612, active_speed, ts_for_hour(hour, i)))

    
    high_points = [
        make_point(6.9271, 79.8612, active_speed, ts_for_hour(h))
        for h in range(24)
    ]

    low_entropy = fx.temporal_activity_pattern(low_points)
    high_entropy = fx.temporal_activity_pattern(high_points)
    expected_high = round(math.log2(24), 4)  

    status_a = PASS if low_entropy < high_entropy - 1.0 else FAIL
    results.append(("18.5a Low entropy materially below high entropy", status_a))
    print(f"[{status_a}] 18.5a Low entropy materially below high entropy")
    print(f"       low_entropy  = {low_entropy}")
    print(f"       high_entropy = {high_entropy}\n")

    check(
        "18.5b High-entropy (uniform 24h) matches log2(24) exactly",
        high_entropy, expected_high, tol_abs=1e-4
    )












def main():
    print("=" * 60)
    print("GeoPaw Feature Extractor — Synthetic Unit Tests (TC 18)")
    print("=" * 60 + "\n")

    test_total_distance()
    test_avg_and_peak_speed()
    test_active_time_proportion()
    test_spatial_range_area()
    test_temporal_entropy()

    print("=" * 60)
    passed = sum(1 for _, s in results if s == PASS)
    print(f"Result: {passed}/{len(results)} checks passed")
    print("=" * 60)
    print(
        "\nNOTE: TC 18.6 (mixed lat/lng vs latitude/longitude field names) "
        "is not covered by this script. feature_extractor.py's functions "
        "only read 'latitude'/'longitude' — the normalisation of hardware "
        "'lat'/'lng' fields must happen in firebase_client.get_gps_logs_for_date(). "
        "Share that function to add a real 18.6 test."
    )


if __name__ == "__main__":
    main()
