#!/bin/bash
set -euo pipefail

MODEL_DIR="VirtualTrainer/Models"
mkdir -p "$MODEL_DIR"

POSE_URL="https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_full/float16/latest/pose_landmarker_full.task"
HAND_URL="https://storage.googleapis.com/mediapipe-models/hand_landmarker/hand_landmarker/float16/latest/hand_landmarker.task"
GESTURE_URL="https://storage.googleapis.com/mediapipe-models/gesture_recognizer/gesture_recognizer/float16/latest/gesture_recognizer.task"
FACE_URL="https://storage.googleapis.com/mediapipe-models/face_landmarker/face_landmarker/float16/latest/face_landmarker.task"

echo "Downloading pose_landmarker_full.task…"
curl -L -o "$MODEL_DIR/pose_landmarker_full.task" "$POSE_URL"

echo "Downloading hand_landmarker.task…"
curl -L -o "$MODEL_DIR/hand_landmarker.task" "$HAND_URL"

echo "Downloading gesture_recognizer.task…"
curl -L -o "$MODEL_DIR/gesture_recognizer.task" "$GESTURE_URL"

echo "Downloading face_landmarker.task…"
curl -L -o "$MODEL_DIR/face_landmarker.task" "$FACE_URL"

echo "Done. Models saved to $MODEL_DIR/"
ls -lh "$MODEL_DIR"/*.task
