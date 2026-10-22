















import anomaly_detector
import firebase_client
import config
from firebase_admin import db

PASS = "PASS"
FAIL = "FAIL"
results = []



PET_ID = "-Ovxz1709_bxtXYsGC9-"
TARGET_DATE = "2026-07-24"

captured_alerts = []


def fake_write_alert(**kwargs):
    captured_alerts.append(kwargs)


def fake_write_daily_behaviour(pet_id, date_str, data):
    pass  


def check(name, ok, note=""):
    status = PASS if ok else FAIL
    results.append((name, status))
    print(f"[{status}] {name}")
    if note:
        print(f"       {note}")
    print()


def get_target_record():
    
    
    
    
    ref = db.reference(f'behaviour/{PET_ID}/{TARGET_DATE}')
    data = ref.get()

    if data:
        record = dict(data)
        record["date"] = TARGET_DATE
        return record

    
    all_data = db.reference(f'behaviour/{PET_ID}').get() or {}
    available_dates = sorted(all_data.keys()) if isinstance(all_data, dict) else []
    raise RuntimeError(
        f"No behaviour record found at behaviour/{PET_ID}/{TARGET_DATE}.\n"
        f"Dates that ARE present for this pet ({len(available_dates)} total): "
        f"{available_dates}\n"
        f"Edit PET_ID/TARGET_DATE at the top of this script to match one of these."
    )


def run_at_threshold(threshold, record, known_score, expect_alert):
    """
    Tests score_and_write()'s threshold-comparison logic using the REAL,
    already-recorded anomaly score for this day (from when it was first
    computed) rather than recomputing it live.

    Why: the model is retrained on a ROLLING 30-day window relative to
    datetime.now(). Since real time has moved on since this day was first
    scored, re-running score_day() now can (and did) produce a different
    score, because the training window itself has shifted — this is a
    separate, real characteristic of rolling-window models, not a bug in
    the threshold logic under test here. Using the stored score keeps this
    test focused purely on "does score_and_write() correctly compare
    against config.ANOMALY_THRESHOLD", independent of that drift.
    """
    captured_alerts.clear()
    original_threshold = config.ANOMALY_THRESHOLD
    original_score_day = anomaly_detector.score_day
    config.ANOMALY_THRESHOLD = threshold
    anomaly_detector.score_day = lambda *a, **kw: known_score
    try:
        score = anomaly_detector.score_and_write(
            PET_ID, TARGET_DATE, record, None, None
        )
    finally:
        config.ANOMALY_THRESHOLD = original_threshold
        anomaly_detector.score_day = original_score_day

    fired = len(captured_alerts) > 0
    ok = fired == expect_alert
    label = "fires" if expect_alert else "does NOT fire"
    check(
        f"Threshold={threshold}: alert {label} (score={score:.4f})",
        ok,
        note=f"expected_alert={expect_alert}, actual_alert_fired={fired}"
    )
    return score


def main():
    print("=" * 60)
    print("GeoPaw Threshold Regression Test (TC 20.5 - 20.6)")
    print("=" * 60 + "\n")

    
    firebase_client.init_firebase()

    
    firebase_client.write_alert = fake_write_alert
    firebase_client.write_daily_behaviour = fake_write_daily_behaviour

    record = get_target_record()
    print(f"Loaded real behaviour record for {TARGET_DATE}: {record}\n")

    known_score = record.get("anomalyScore")
    if known_score is None:
        print(f"Record for {TARGET_DATE} has no stored anomalyScore yet — "
              f"run `python main.py --full` for this pet first so it gets scored.")
        return
    print(f"Using the REAL recorded anomaly score for this day: {known_score:.4f}\n")

    
    score_a = run_at_threshold(0.7, record, known_score, expect_alert=False)

    
    score_b = run_at_threshold(0.45, record, known_score, expect_alert=True)

    print("=" * 60)
    passed = sum(1 for _, s in results if s == PASS)
    print(f"Result: {passed}/{len(results)} checks passed")
    print("=" * 60)
    print(
        f"\nBoth runs scored the same day ({score_a:.4f} vs {score_b:.4f} — "
        f"should be identical since only the threshold changed, not the "
        f"model or data). This is the concrete evidence that threshold=0.7 "
        f"would have missed this real anomaly, justifying the revision to 0.45."
    )


if __name__ == "__main__":
    main()