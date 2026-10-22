












import sys
import time
import argparse
from datetime import datetime, timedelta
import firebase_client
import feature_extractor
import anomaly_detector
import config


def get_date_str(days_ago=0):
    d = datetime.now() - timedelta(days=days_ago)
    return d.strftime('%Y-%m-%d')







def run_daily_pipeline(pet_id: str, pet_name: str, date_str: str):
    print(f"\n[Pipeline] Daily run for {pet_name} on {date_str}")

    
    print(f"[Pipeline] Step 1: Extracting features...")
    features = feature_extractor.extract_features(pet_id, date_str)

    if features is None:
        print(f"[Pipeline] No GPS data for {date_str} — skipping")
        return

    
    print(f"[Pipeline] Step 2: Loading model...")
    model, scaler = anomaly_detector.load_model(pet_id)

    if model is None:
        print(f"[Pipeline] No model found — attempting to train...")
        model, scaler = anomaly_detector.train_model(pet_id)

    if model is None:
        print(f"[Pipeline] Not enough data to train yet. "
              f"Need {config.MIN_TRAINING_DAYS} days minimum.")
        print(f"[Pipeline] Features saved. Will train once enough data accumulates.")
        return

    
    print(f"[Pipeline] Step 3: Scoring today's behaviour...")
    score = anomaly_detector.score_and_write(
        pet_id, date_str, features, model, scaler
    )

    if score is not None:
        status = '⚠️  ANOMALY DETECTED' if score >= config.ANOMALY_THRESHOLD else '✅ Normal'
        print(f"[Pipeline] Result: {score:.4f} — {status}")







def run_weekly_retrain(pet_id: str, pet_name: str):
    print(f"\n[Pipeline] Weekly retrain for {pet_name}")
    model, scaler = anomaly_detector.train_model(pet_id)
    if model:
        print(f"[Pipeline] Retrain complete for {pet_name}")
    else:
        print(f"[Pipeline] Retrain skipped — not enough data")







def run_full_history(pet_id: str, pet_name: str):
    print(f"\n[Pipeline] Full history run for {pet_name}")

    
    
    print(f"[Pipeline] Extracting features for last {config.TRAINING_WINDOW_DAYS} days...")
    today = datetime.now()
    dates = [
        (today - timedelta(days=i)).strftime('%Y-%m-%d')
        for i in range(config.TRAINING_WINDOW_DAYS - 1, -1, -1)
    ]

    extracted = 0
    for date_str in dates:
        existing = firebase_client.get_behaviour_history(pet_id, days=1)
        existing_dates = [r.get('date') for r in existing]
        if date_str not in existing_dates:
            result = feature_extractor.extract_features(pet_id, date_str)
            if result:
                extracted += 1

    print(f"[Pipeline] Extracted {extracted} new feature records")

    
    model, scaler = anomaly_detector.train_model(pet_id)
    if model is None:
        print(f"[Pipeline] Not enough data to train")
        return

    
    anomaly_detector.score_all_history(pet_id)







def run_scheduled():
    print("[Pipeline] Scheduled mode started. Press Ctrl+C to stop.")
    print(f"[Pipeline] Will run daily at midnight, retrain on Sundays.")

    firebase_client.init_firebase()
    last_run_date = None

    while True:
        now = datetime.now()
        today_str = now.strftime('%Y-%m-%d')

        
        if today_str != last_run_date:
            print(f"\n[Pipeline] {'='*50}")
            print(f"[Pipeline] Scheduled run at {now.strftime('%Y-%m-%d %H:%M:%S')}")

            pets = firebase_client.get_all_pets()
            if not pets:
                print("[Pipeline] No pets found")
            else:
                for pet in pets:
                    
                    yesterday = get_date_str(days_ago=1)
                    run_daily_pipeline(pet['petId'], pet['name'], yesterday)

                    
                    if now.weekday() == 6:
                        run_weekly_retrain(pet['petId'], pet['name'])

            last_run_date = today_str
            print(f"[Pipeline] Next run tomorrow at midnight")

        
        time.sleep(60)






def main():
    parser = argparse.ArgumentParser(description='GeoPaw ML Pipeline')
    parser.add_argument('--schedule', action='store_true',
                        help='Run on a daily schedule (continuous)')
    parser.add_argument('--full', action='store_true',
                        help='Run full history extraction and scoring')
    parser.add_argument('--date', type=str, default=None,
                        help='Run for specific date (YYYY-MM-DD)')
    parser.add_argument('--retrain', action='store_true',
                        help='Force retrain models for all pets')
    args = parser.parse_args()

    firebase_client.init_firebase()
    pets = firebase_client.get_all_pets()

    if not pets:
        print("[Pipeline] No pets found. Add a pet in the app first.")
        return

    print(f"[Pipeline] Found {len(pets)} pet(s): "
          f"{', '.join(p['name'] for p in pets)}")

    if args.schedule:
        run_scheduled()
        return

    for pet in pets:
        pet_id = pet['petId']
        pet_name = pet['name']

        print(f"\n{'='*50}")
        print(f"Pet: {pet_name} (ID: {pet_id})")
        print(f"{'='*50}")

        if args.full:
            run_full_history(pet_id, pet_name)

        elif args.retrain:
            run_weekly_retrain(pet_id, pet_name)

        elif args.date:
            run_daily_pipeline(pet_id, pet_name, args.date)

        else:
            
            yesterday = get_date_str(days_ago=1)
            print(f"[Pipeline] Running for yesterday: {yesterday}")
            run_daily_pipeline(pet_id, pet_name, yesterday)

            
            model, _ = anomaly_detector.load_model(pet_id)
            if model is None:
                print(f"\n[Pipeline] No model found — running full history first")
                run_full_history(pet_id, pet_name)

    print(f"\n[Pipeline] Done.")


if __name__ == '__main__':
    main()