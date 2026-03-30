#!/bin/bash
set -euo pipefail

MODEL_DIR="VirtualTrainer/Models"
mkdir -p "$MODEL_DIR"

POSE_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"
HAND_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"

echo "Downloading pose_landmarker_full.task…"
curl -L -o "$MODEL_DIR/pose_landmarker_full.task" "$POSE_URL"

echo "Downloading hand_landmarker.task…"
curl -L -o "$MODEL_DIR/hand_landmarker.task" "$HAND_URL"

echo "Done. Models saved to $MODEL_DIR/"
ls -lh "$MODEL_DIR"/*.task
