














import os
import time
import random
from datetime import datetime, timedelta

import anomaly_detector
import firebase_client  
import config

PASS = "PASS"
FAIL = "FAIL"
results = []


def check(name, ok, note=""):
    status = PASS if ok else FAIL
    results.append((name, status))
    print(f"[{status}] {name}")
    if note:
        print(f"       {note}")
    print()


def generate_synthetic_records(n_days):
    """
    Builds n_days of plausible behaviour feature records using the SAME
    FEATURE_COLUMNS the real detector trains on, so this can never drift
    out of sync with production. Values are randomised but reproducible.
    """
    rng = random.Random(42)
    today = datetime.now()
    records = []
    for i in range(n_days):
        date_str = (today - timedelta(days=(n_days - i))).strftime("%Y-%m-%d")
        rec = {col: round(rng.uniform(0, 100), 4) for col in anomaly_detector.FEATURE_COLUMNS}
        rec["date"] = date_str
        records.append(rec)
    return records


def cleanup(pet_id):
    for p in (anomaly_detector.model_path(pet_id), anomaly_detector.scaler_path(pet_id)):
        if os.path.exists(p):
            os.remove(p)


def with_fake_history(records):
    """Monkeypatches firebase_client.get_behaviour_history for the duration
    of a single train_model() call, regardless of the pet_id/days args passed."""
    def fake_get_behaviour_history(pet_id, days=None):
        return records
    firebase_client.get_behaviour_history = fake_get_behaviour_history






def test_minimum_required():
    n = config.MIN_TRAINING_DAYS
    pet_id = "TEST_PET_MIN"
    cleanup(pet_id)

    with_fake_history(generate_synthetic_records(n))
    model, scaler = anomaly_detector.train_model(pet_id)

    ok = (
        model is not None and scaler is not None
        and os.path.exists(anomaly_detector.model_path(pet_id))
        and os.path.exists(anomaly_detector.scaler_path(pet_id))
    )
    check(
        f"19.1 Training with exactly {n} days (config.MIN_TRAINING_DAYS)",
        ok,
        note=f"model_path exists: {os.path.exists(anomaly_detector.model_path(pet_id))}, "
             f"scaler_path exists: {os.path.exists(anomaly_detector.scaler_path(pet_id))}"
    )
    cleanup(pet_id)






def test_insufficient_data():
    pet_id = "TEST_PET_INSUFFICIENT"
    cleanup(pet_id)

    
    with_fake_history(generate_synthetic_records(10))
    model, scaler = anomaly_detector.train_model(pet_id)
    ok_10 = model is None and scaler is None
    check(
        "19.2a Training with 10 days (below minimum) declines to fit, no exception",
        ok_10
    )
    cleanup(pet_id)

    
    n = config.MIN_TRAINING_DAYS - 1
    with_fake_history(generate_synthetic_records(n))
    model, scaler = anomaly_detector.train_model(pet_id)
    ok_boundary = model is None and scaler is None
    check(
        f"19.2b Training with {n} days (MIN_TRAINING_DAYS - 1) also declines",
        ok_boundary
    )
    cleanup(pet_id)






def test_full_window():
    pet_id = "TEST_PET_FULL"
    cleanup(pet_id)

    with_fake_history(generate_synthetic_records(30))
    model, scaler = anomaly_detector.train_model(pet_id)

    ok = model is not None and scaler is not None
    check("19.3 Training with a full 30-day window fits without error", ok)
    cleanup(pet_id)






def test_retrain_overwrites():
    pet_id = "TEST_PET_RETRAIN"
    cleanup(pet_id)
    n = config.MIN_TRAINING_DAYS

    with_fake_history(generate_synthetic_records(n))
    anomaly_detector.train_model(pet_id)
    mtime_1 = os.path.getmtime(anomaly_detector.model_path(pet_id))

    time.sleep(1.1)  

    with_fake_history(generate_synthetic_records(n))  
    anomaly_detector.train_model(pet_id)
    mtime_2 = os.path.getmtime(anomaly_detector.model_path(pet_id))

    ok = mtime_2 > mtime_1
    check(
        "19.4 Retraining overwrites the previous .pkl file",
        ok,
        note=f"first save mtime={mtime_1}, second save mtime={mtime_2}"
    )
    cleanup(pet_id)


def main():
    print("=" * 60)
    print("GeoPaw Model Training — Tests (TC 19.1 - 19.4)")
    print("=" * 60 + "\n")

    print(f"config.MIN_TRAINING_DAYS = {config.MIN_TRAINING_DAYS}")
    print(f"config.TRAINING_WINDOW_DAYS = {getattr(config, 'TRAINING_WINDOW_DAYS', 'N/A')}\n")

    test_minimum_required()
    test_insufficient_data()
    test_full_window()
    test_retrain_overwrites()

    print("=" * 60)
    passed = sum(1 for _, s in results if s == PASS)
    print(f"Result: {passed}/{len(results)} checks passed")
    print("=" * 60)


if __name__ == "__main__":
    main()
