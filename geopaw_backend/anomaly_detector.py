





import os
import pickle
import numpy as np
from sklearn.ensemble import IsolationForest
from sklearn.preprocessing import StandardScaler
import firebase_client
import config


MODEL_DIR = "models"
os.makedirs(MODEL_DIR, exist_ok=True)


FEATURE_COLUMNS = [
    'totalDistance',
    'avgSpeed',
    'peakSpeed',
    'gpsAcceleration',
    'homeZoneDwellTime',
    'activeTimePct',
    'spatialRangeArea',
    'temporalEntropy',
]






def model_path(pet_id: str):
    return os.path.join(MODEL_DIR, f"{pet_id}_model.pkl")

def scaler_path(pet_id: str):
    return os.path.join(MODEL_DIR, f"{pet_id}_scaler.pkl")

def save_model(pet_id: str, model, scaler):
    with open(model_path(pet_id), 'wb') as f:
        pickle.dump(model, f)
    with open(scaler_path(pet_id), 'wb') as f:
        pickle.dump(scaler, f)
    print(f"[Detector] Model saved for pet: {pet_id}")

def load_model(pet_id: str):
    mp = model_path(pet_id)
    sp = scaler_path(pet_id)
    if not os.path.exists(mp) or not os.path.exists(sp):
        return None, None
    with open(mp, 'rb') as f:
        model = pickle.load(f)
    with open(sp, 'rb') as f:
        scaler = pickle.load(f)
    print(f"[Detector] Model loaded for pet: {pet_id}")
    return model, scaler






def build_feature_matrix(records: list):
    """
    Converts a list of daily behaviour dicts into a numpy matrix.
    Missing features default to 0.
    Returns (X, dates) where X is shape (n_days, 8).
    """
    X = []
    dates = []
    for rec in records:
        row = [float(rec.get(col, 0)) for col in FEATURE_COLUMNS]
        X.append(row)
        dates.append(rec.get('date', ''))
    return np.array(X), dates






def train_model(pet_id: str):
    """
    Trains an Isolation Forest model on all available behaviour history.
    Requires at least MIN_TRAINING_DAYS records.
    Saves model to disk and returns (model, scaler).
    """
    print(f"[Detector] Loading behaviour history for pet: {pet_id}")
    records = firebase_client.get_behaviour_history(
        pet_id, days=config.TRAINING_WINDOW_DAYS
    )

    if len(records) < config.MIN_TRAINING_DAYS:
        print(f"[Detector] Not enough data to train: {len(records)} days "
              f"(need {config.MIN_TRAINING_DAYS})")
        return None, None

    X, dates = build_feature_matrix(records)
    print(f"[Detector] Training on {len(X)} days of data")
    print(f"[Detector] Feature matrix shape: {X.shape}")



    scaler = StandardScaler()
    X_scaled = scaler.fit_transform(X)





    model = IsolationForest(
        n_estimators=100,
        contamination=0.05,
        random_state=42,
        max_samples='auto',
    )
    model.fit(X_scaled)

    save_model(pet_id, model, scaler)

    print(f"[Detector] Training complete for pet: {pet_id}")
    return model, scaler






def score_day(pet_id: str, features: dict, model=None, scaler=None):
    """
    Scores a single day's feature vector.
    Returns anomaly_score (0.0 - 1.0) where higher = more anomalous.
    Scores above ANOMALY_THRESHOLD should trigger an alert.

    Isolation Forest returns:
    - decision_function: negative = more anomalous
    - predict: -1 = anomaly, 1 = normal

    We convert decision_function to a 0-1 score for display.
    """
    if model is None or scaler is None:
        model, scaler = load_model(pet_id)
        if model is None:
            print(f"[Detector] No model found for pet: {pet_id} — training now")
            model, scaler = train_model(pet_id)
            if model is None:
                return None


    x = np.array([[float(features.get(col, 0)) for col in FEATURE_COLUMNS]])
    x_scaled = scaler.transform(x)


    raw_score = model.decision_function(x_scaled)[0]




    anomaly_score = float(np.clip(0.5 - raw_score, 0.0, 1.0))









    is_anomaly = anomaly_score >= config.ANOMALY_THRESHOLD

    print(f"[Detector] Score for {pet_id}: {anomaly_score:.4f} "
          f"({'ANOMALY' if is_anomaly else 'normal'})")

    return anomaly_score






def score_and_write(pet_id: str, date_str: str, features: dict,
                    model=None, scaler=None):
    """
    Scores a day, writes the anomaly score to Firebase behaviour node,
    and creates an alert if the score exceeds the threshold.
    """
    anomaly_score = score_day(pet_id, features, model, scaler)
    if anomaly_score is None:
        return


    firebase_client.write_daily_behaviour(pet_id, date_str, {
        **features,
        'anomalyScore': round(anomaly_score, 4),
    })


    if anomaly_score >= config.ANOMALY_THRESHOLD:
        firebase_client.write_alert(
            pet_id=pet_id,
            alert_type='anomaly',
            title='Unusual behaviour detected',
            description=(
                f"Anomaly score {anomaly_score:.2f} on {date_str}. "
                f"Activity ({features.get('activeTimePct', 0):.1f}%) and "
                f"distance ({features.get('totalDistance', 0):.0f}m) are "
                f"significantly outside your pet's normal baseline."
            )
        )

    return anomaly_score






def score_all_history(pet_id: str):
    """
    Scores all days in behaviour history and writes anomaly scores.
    Useful for initial setup after training.
    """
    model, scaler = load_model(pet_id)
    if model is None:
        model, scaler = train_model(pet_id)
        if model is None:
            print("[Detector] Cannot score — not enough training data")
            return

    records = firebase_client.get_behaviour_history(
        pet_id, days=config.TRAINING_WINDOW_DAYS
    )

    print(f"[Detector] Scoring {len(records)} days for pet: {pet_id}")
    anomaly_count = 0

    for rec in records:
        date_str = rec.get('date', '')
        score = score_and_write(pet_id, date_str, rec, model, scaler)
        if score and score >= config.ANOMALY_THRESHOLD:
            anomaly_count += 1

    print(f"[Detector] Done. Found {anomaly_count} anomalous days "
          f"out of {len(records)} total.")






if __name__ == '__main__':
    firebase_client.init_firebase()
    pets = firebase_client.get_all_pets()

    if not pets:
        print("No pets found. Add a pet in the app first.")
    else:
        for pet in pets:
            print(f"\n{'='*50}")
            print(f"Processing pet: {pet['name']} ({pet['petId']})")
            print(f"{'='*50}")


            model, scaler = train_model(pet['petId'])

            if model is not None:

                score_all_history(pet['petId'])
            else:
                print(f"Skipping {pet['name']} — not enough data")

        print("\n[Detector] All pets processed.")