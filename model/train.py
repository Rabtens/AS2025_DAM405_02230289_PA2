"""
train.py
--------
Trains and persists a scikit-learn classifier for the DAM405 Assignment 2
prediction service.

Dataset: UCI Wine recognition dataset (bundled with scikit-learn, so the
pipeline is fully reproducible offline / in CI without external downloads).
Task: multi-class classification of wine cultivar (class_0, class_1, class_2)
from 13 physicochemical features.

Usage:
    python model/train.py
Outputs:
    model/model.joblib        -> trained sklearn Pipeline (scaler + classifier)
    model/metadata.json       -> feature schema, classes, metrics, version
"""
import json
import time
from pathlib import Path

import joblib
import numpy as np
from sklearn.datasets import load_wine
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import accuracy_score, classification_report, f1_score
from sklearn.model_selection import train_test_split
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler

MODEL_DIR = Path(__file__).parent
MODEL_PATH = MODEL_DIR / "model.joblib"
METADATA_PATH = MODEL_DIR / "metadata.json"
MODEL_VERSION = "1.0.0"
RANDOM_STATE = 42


def train_and_persist():
    data = load_wine()
    X, y = data.data, data.target
    feature_names = list(data.feature_names)
    class_names = [str(c) for c in data.target_names]

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=RANDOM_STATE, stratify=y
    )

    pipeline = Pipeline(
        steps=[
            ("scaler", StandardScaler()),
            (
                "clf",
                RandomForestClassifier(
                    n_estimators=200,
                    max_depth=6,
                    random_state=RANDOM_STATE,
                ),
            ),
        ]
    )

    pipeline.fit(X_train, y_train)

    y_pred = pipeline.predict(X_test)
    accuracy = accuracy_score(y_test, y_pred)
    f1_macro = f1_score(y_test, y_pred, average="macro")
    report = classification_report(y_test, y_pred, target_names=class_names, output_dict=True)

    joblib.dump(pipeline, MODEL_PATH)

    metadata = {
        "model_version": MODEL_VERSION,
        "trained_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "algorithm": "RandomForestClassifier",
        "dataset": "sklearn.datasets.load_wine",
        "feature_names": feature_names,
        "n_features": len(feature_names),
        "class_names": class_names,
        "test_accuracy": round(float(accuracy), 4),
        "test_f1_macro": round(float(f1_macro), 4),
        "classification_report": report,
        "feature_ranges": {
            name: [float(np.min(X[:, i])), float(np.max(X[:, i]))]
            for i, name in enumerate(feature_names)
        },
    }
    with open(METADATA_PATH, "w") as f:
        json.dump(metadata, f, indent=2)

    print(f"Saved model  -> {MODEL_PATH}")
    print(f"Saved metadata -> {METADATA_PATH}")
    print(f"Test accuracy: {accuracy:.4f}  |  Test F1 (macro): {f1_macro:.4f}")


if __name__ == "__main__":
    train_and_persist()
