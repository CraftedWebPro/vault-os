import argparse
import json
import math
import os
import sys
import time
from datetime import datetime, timezone

os.environ.setdefault("TF_CPP_MIN_LOG_LEVEL", "3")

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python
from mediapipe.tasks.python import vision

LEFT_EYE_EAR = (33, 160, 158, 133, 153, 144)
RIGHT_EYE_EAR = (362, 385, 387, 263, 373, 380)
LEFT_EYE_CENTER = (33, 133)
RIGHT_EYE_CENTER = (362, 263)
FACE_WIDTH_POINTS = (234, 454)
NOSE_TIP = 1
CHIN = 152
MOUTH_POINTS = (61, 291)
FACE_OUTLINE = (
    10, 338, 297, 332, 284, 251, 389, 356, 454, 323, 361, 288, 397, 365, 379,
    378, 400, 377, 152, 148, 176, 149, 150, 136, 172, 58, 132, 93, 234, 127,
    162, 21, 54, 103, 67, 109,
)
LEFT_EYE_RING = (33, 160, 158, 133, 153, 144)
RIGHT_EYE_RING = (362, 385, 387, 263, 373, 380)
NOSE_BRIDGE = (6, 168, 197, 195, 5, 4, 1, 19, 94, 2)
MOUTH_RING = (61, 146, 91, 181, 84, 17, 314, 405, 321, 375, 291)

# full hand skeleton rig — all 21 joints connected
HAND_CONNECTIONS = (
    (0, 1), (0, 5), (9, 13), (13, 17), (5, 9), (0, 17),
    (1, 2), (2, 3), (3, 4),
    (5, 6), (6, 7), (7, 8),
    (9, 10), (10, 11), (11, 12),
    (13, 14), (14, 15), (15, 16),
    (17, 18), (18, 19), (19, 20),
)

WRIST_INDEX = 0
MIDDLE_MCP_INDEX = 9
GESTURE_HOLD_SECONDS = 2.0
VERIFY_GESTURE_HOLD_SECONDS = 1.2
# the landmarker looks for up to 2 hands; whether a profile needs
# one or both is a per-enrollment choice (--hands / hand_mode)
MAX_HANDS = 2
HAND_MODE_CHOICES = ("single", "double")
HAND_GESTURE_MATCH_THRESHOLD = 0.55
BLINK_WINDOW_SECONDS = 8.0
# a single frame under threshold isn't a blink — it's usually landmark
# jitter or a head tilt. require EAR to stay past threshold for a few
# consecutive frames before flipping state, both directions.
BLINK_CONSEC_FRAMES = 3
FACE_CAPTURE_TARGET = 30
FACE_MATCH_TOLERANCE = 0.14
FACE_MATCH_STABLE_FRAMES = 12
FACE_LOCK_HOLD_SECONDS = 1.5
FACE_STAGE_TIMEOUT_SECONDS = 15.0
ENROLLMENT_WINDOW = "Vault OS Enrollment"
VERIFICATION_WINDOW = "Vault OS Verification"

# ---------------------------------------------------------------------------
# HUD palette (BGR, as OpenCV expects) — scan-line / heads-up-display look
# ---------------------------------------------------------------------------
HUD_CYAN = (255, 246, 90)        # primary scan color
HUD_CYAN_DIM = (150, 140, 40)    # faint guide lines / idle reticle
HUD_WHITE = (255, 255, 255)      # landmark highlights
HUD_AMBER = (10, 190, 255)       # "in progress / aligning" state
HUD_RED = (70, 70, 255)          # not detected / mismatch
HUD_GREEN = (140, 235, 120)      # confirmed / matched
PANEL_BG = (28, 22, 15)          # dark HUD readout panel background


class CalibrationError(RuntimeError):
    pass


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def distance(a, b) -> float:
    return math.dist(a, b)


def midpoint(a, b):
    return ((a.x + b.x) / 2.0, (a.y + b.y) / 2.0, (a.z + b.z) / 2.0)


def normalized_face_metrics(landmarks) -> dict:
    left_eye = midpoint(landmarks[LEFT_EYE_CENTER[0]], landmarks[LEFT_EYE_CENTER[1]])
    right_eye = midpoint(landmarks[RIGHT_EYE_CENTER[0]], landmarks[RIGHT_EYE_CENTER[1]])
    face_width = distance(
        (landmarks[FACE_WIDTH_POINTS[0]].x, landmarks[FACE_WIDTH_POINTS[0]].y, landmarks[FACE_WIDTH_POINTS[0]].z),
        (landmarks[FACE_WIDTH_POINTS[1]].x, landmarks[FACE_WIDTH_POINTS[1]].y, landmarks[FACE_WIDTH_POINTS[1]].z),
    )
    if face_width == 0:
        raise CalibrationError("Face width collapsed to zero.")

    nose_to_chin = distance(
        (landmarks[NOSE_TIP].x, landmarks[NOSE_TIP].y, landmarks[NOSE_TIP].z),
        (landmarks[CHIN].x, landmarks[CHIN].y, landmarks[CHIN].z),
    )
    mouth_width = distance(
        (landmarks[MOUTH_POINTS[0]].x, landmarks[MOUTH_POINTS[0]].y, landmarks[MOUTH_POINTS[0]].z),
        (landmarks[MOUTH_POINTS[1]].x, landmarks[MOUTH_POINTS[1]].y, landmarks[MOUTH_POINTS[1]].z),
    )
    interpupillary = distance(left_eye, right_eye)
    return {
        "interpupillary_ratio": interpupillary / face_width,
        "nose_to_chin_ratio": nose_to_chin / face_width,
        "mouth_width_ratio": mouth_width / face_width,
    }


def compute_ear(landmarks, indices) -> float:
    p1 = landmarks[indices[0]]
    p2 = landmarks[indices[1]]
    p3 = landmarks[indices[2]]
    p4 = landmarks[indices[3]]
    p5 = landmarks[indices[4]]
    p6 = landmarks[indices[5]]
    horizontal = distance((p1.x, p1.y, p1.z), (p4.x, p4.y, p4.z))
    if horizontal == 0:
        return 0.0
    vertical = distance((p2.x, p2.y, p2.z), (p6.x, p6.y, p6.z)) + distance(
        (p3.x, p3.y, p3.z), (p5.x, p5.y, p5.z)
    )
    return vertical / (2.0 * horizontal)


def average_ear(landmarks) -> float:
    left = compute_ear(landmarks, LEFT_EYE_EAR)
    right = compute_ear(landmarks, RIGHT_EYE_EAR)
    return (left + right) / 2.0


def normalize_hand_landmarks(landmarks):
    points = np.array([[lm.x, lm.y, lm.z] for lm in landmarks], dtype=np.float32)
    origin = points[WRIST_INDEX]
    translated = points - origin

    scale = np.linalg.norm(translated[MIDDLE_MCP_INDEX])
    if scale < 1e-6:
        raise CalibrationError("Hand landmarks are too small to normalize.")
    scaled = translated / scale

    # Rotate in-plane so wrist -> middle-finger-MCP always points the same
    # direction. Without this, holding the same gesture at a different wrist
    # angle shifts every landmark and fails the match even though the finger
    # shape is identical. Only x/y are rotated; z (depth) is left alone.
    ref_x, ref_y = scaled[MIDDLE_MCP_INDEX][0], scaled[MIDDLE_MCP_INDEX][1]
    angle = math.atan2(ref_y, ref_x)
    target_angle = -math.pi / 2  # canonical: middle finger points "up"
    rotation = target_angle - angle
    cos_a, sin_a = math.cos(rotation), math.sin(rotation)
    rotation_matrix = np.array([[cos_a, -sin_a], [sin_a, cos_a]], dtype=np.float32)
    scaled[:, :2] = scaled[:, :2] @ rotation_matrix.T

    return scaled.flatten().tolist()


def average_vectors(vectors):
    return np.mean(np.array(vectors, dtype=np.float32), axis=0).tolist()


def within_tolerance(actual: dict, expected: dict, tolerance: float) -> bool:
    return all(abs(actual[key] - expected[key]) <= tolerance for key in expected.keys())


def max_metric_delta(actual: dict, expected: dict) -> float:
    return max(abs(actual[key] - expected[key]) for key in expected.keys())


def gesture_distance(first, second) -> float:
    return float(np.linalg.norm(np.array(first, dtype=np.float32) - np.array(second, dtype=np.float32)))


# ---------------------------------------------------------------------------
# Face recognition via ONNX embedding model.
#
# normalized_face_metrics() is a coarse first-pass — just three ratios of
# face geometry, no texture or fine structure. Two people with similar face
# proportions can pass it. This section adds a real identity check on top:
# align the face, run it through an embedding model, compare by cosine
# similarity.
#
# Setup:
#   1. Get a 112x112-input ArcFace-style ONNX face embedding model
#      (512-d output is standard). CHECK ITS LICENSE before shipping in
#      a paid product — lots of pretrained face-recognition weights are
#      research/non-commercial only.
#   2. Drop it in models/ as face_embedding.onnx (or change the constant below).
#   3. pip install onnxruntime
#
# Profiles enrolled before this was added won't have a face_embedding, so
# verification falls back to the old ratio-based check — see
# _face_identity_match below.
# ---------------------------------------------------------------------------

FACE_EMBED_MODEL_NAME = "face_embedding.onnx"
FACE_EMBED_INPUT_SIZE = 112
FACE_EMBED_MATCH_THRESHOLD = 0.45  # cosine similarity — tune against your chosen model

# Standard 112x112 ArcFace alignment template: left eye, right eye, nose
# tip, left mouth corner, right mouth corner.
_ARC_FACE_TEMPLATE = np.array(
    [
        [38.2946, 51.6963],
        [73.5318, 51.5014],
        [56.0252, 71.7366],
        [41.5493, 92.3655],
        [70.7299, 92.2041],
    ],
    dtype=np.float32,
)

_face_embedder = None


def _get_face_embedder():
    global _face_embedder
    if _face_embedder is None:
        import onnxruntime  # lazy import so the rest works without it

        _face_embedder = onnxruntime.InferenceSession(
            resolve_model_path(FACE_EMBED_MODEL_NAME),
            providers=["CPUExecutionProvider"],
        )
    return _face_embedder


def face_embedder_available() -> bool:
    """Check if the face embedding model is loadable. Called once up front
    so enroll()/verify() can decide whether to run real identity matching
    or fall back to ratio-only geometry check."""
    try:
        _get_face_embedder()
        return True
    except Exception:
        return False


def _face_landmark_pixels(frame, landmarks):
    height, width = frame.shape[:2]
    left_eye = midpoint(landmarks[LEFT_EYE_CENTER[0]], landmarks[LEFT_EYE_CENTER[1]])
    right_eye = midpoint(landmarks[RIGHT_EYE_CENTER[0]], landmarks[RIGHT_EYE_CENTER[1]])
    nose = landmarks[NOSE_TIP]
    mouth_left = landmarks[MOUTH_POINTS[0]]
    mouth_right = landmarks[MOUTH_POINTS[1]]
    return np.array(
        [
            [left_eye[0] * width, left_eye[1] * height],
            [right_eye[0] * width, right_eye[1] * height],
            [nose.x * width, nose.y * height],
            [mouth_left.x * width, mouth_left.y * height],
            [mouth_right.x * width, mouth_right.y * height],
        ],
        dtype=np.float32,
    )


def align_face(frame, landmarks):
    """Warp face into canonical 112x112 crop using 5-point similarity
    transform — the alignment ArcFace-style models expect."""
    src = _face_landmark_pixels(frame, landmarks)
    matrix, _ = cv2.estimateAffinePartial2D(src, _ARC_FACE_TEMPLATE, method=cv2.LMEDS)
    if matrix is None:
        raise CalibrationError("Could not align face for recognition.")
    return cv2.warpAffine(frame, matrix, (FACE_EMBED_INPUT_SIZE, FACE_EMBED_INPUT_SIZE), borderValue=0.0)


def compute_face_embedding(frame, landmarks):
    aligned = align_face(frame, landmarks)
    blob = aligned.astype(np.float32)
    blob = (blob - 127.5) / 128.0
    blob = np.transpose(blob, (2, 0, 1))[np.newaxis, ...]  # HWC -> NCHW

    session = _get_face_embedder()
    input_name = session.get_inputs()[0].name
    output = session.run(None, {input_name: blob})[0]
    embedding = np.asarray(output, dtype=np.float32).flatten()

    norm = np.linalg.norm(embedding)
    if norm < 1e-6:
        raise CalibrationError("Face embedding collapsed to zero.")
    return (embedding / norm).tolist()


def cosine_similarity(a, b) -> float:
    a = np.array(a, dtype=np.float32)
    b = np.array(b, dtype=np.float32)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-8))


def _face_identity_match(frame, face, profile) -> bool:
    embedding = profile.get("face_embedding")
    if embedding:
        try:
            live_embedding = compute_face_embedding(frame, face)
        except Exception:
            return False
        return cosine_similarity(live_embedding, embedding) >= FACE_EMBED_MATCH_THRESHOLD

    # Fallback for profiles enrolled before the embedding upgrade.
    return within_tolerance(normalized_face_metrics(face), profile["face_signature"], FACE_MATCH_TOLERANCE)


# ---------------------------------------------------------------------------
# HUD drawing primitives
# ---------------------------------------------------------------------------

def _pt(landmark, width, height):
    return int(landmark.x * width), int(landmark.y * height)


def landmarks_bbox(frame, landmarks, indices=None, pad=0.18):
    height, width = frame.shape[:2]
    points = landmarks if indices is None else [landmarks[i] for i in indices]
    xs = [p.x for p in points]
    ys = [p.y for p in points]
    x1, x2 = min(xs), max(xs)
    y1, y2 = min(ys), max(ys)
    pad_x = (x2 - x1) * pad
    pad_y = (y2 - y1) * pad
    x1 = max(0.0, x1 - pad_x)
    x2 = min(1.0, x2 + pad_x)
    y1 = max(0.0, y1 - pad_y)
    y2 = min(1.0, y2 + pad_y)
    return int(x1 * width), int(y1 * height), int(x2 * width), int(y2 * height)


def draw_hud_panel(frame, lines, color=HUD_CYAN, title="VAULT OS \u25c8 LIVE SCAN"):
    """Semi-transparent readout panel with status text and accent rule."""
    height, width = frame.shape[:2]
    scale = max(0.55, min(1.0, height / 480.0))
    title_size = round(0.55 * scale, 2)
    line_size = round(0.52 * scale, 2)
    line_gap = max(14, int(24 * scale))
    panel_h = int(34 * scale) + line_gap * len(lines)
    panel_w = min(width - 24, int(460 * scale))

    overlay = frame.copy()
    cv2.rectangle(overlay, (12, 12), (12 + panel_w, 12 + panel_h), PANEL_BG, -1)
    cv2.rectangle(overlay, (12, 12), (12 + panel_w, int(12 + 4 * scale)), color, -1)
    frame[:] = cv2.addWeighted(overlay, 0.62, frame, 0.38, 0)

    cv2.putText(frame, title, (24, int(34 * scale)), cv2.FONT_HERSHEY_DUPLEX, title_size, HUD_CYAN_DIM, 1, cv2.LINE_AA)
    cv2.line(frame, (24, int(42 * scale)), (12 + panel_w - 12, int(42 * scale)), color, 1, cv2.LINE_AA)
    cv2.line(frame, (18, panel_h + 8), (84, panel_h + 8), color, 1, cv2.LINE_AA)
    cv2.line(frame, (12 + panel_w - 84, panel_h + 8), (12 + panel_w - 18, panel_h + 8), color, 1, cv2.LINE_AA)

    y = int(66 * scale)
    for line in lines:
        cv2.putText(frame, line, (24, y), cv2.FONT_HERSHEY_SIMPLEX, line_size, color, 1, cv2.LINE_AA)
        y += line_gap


def draw_frame_reticle(frame, color=HUD_CYAN_DIM, size=22):
    """Fixed viewfinder corner brackets on the whole frame."""
    height, width = frame.shape[:2]
    margin = 10
    draw_corner_brackets(frame, (margin, margin, width - margin, height - margin), color, size=size, thickness=1)
    cx = width // 2
    cy = height // 2
    cv2.line(frame, (cx - 12, cy), (cx + 12, cy), color, 1, cv2.LINE_AA)
    cv2.line(frame, (cx, cy - 12), (cx, cy + 12), color, 1, cv2.LINE_AA)


def draw_corner_brackets(frame, bbox, color, size=18, thickness=2):
    x1, y1, x2, y2 = bbox
    for (cx, cy, dx, dy) in ((x1, y1, 1, 1), (x2, y1, -1, 1), (x1, y2, 1, -1), (x2, y2, -1, -1)):
        cv2.line(frame, (cx, cy), (cx + dx * size, cy), color, thickness, cv2.LINE_AA)
        cv2.line(frame, (cx, cy), (cx, cy + dy * size), color, thickness, cv2.LINE_AA)


def draw_scan_sweep(frame, bbox, color=HUD_CYAN, period=1.6):
    """Horizontal scan line that ping-pongs across the bounding box."""
    x1, y1, x2, y2 = bbox
    if y2 <= y1:
        return
    t = time.time() % period
    ratio = t / period
    progress = 1 - abs(2 * ratio - 1)  # triangle wave 0 -> 1 -> 0
    scan_y = int(y1 + progress * (y2 - y1))

    overlay = frame.copy()
    cv2.rectangle(overlay, (x1, y1), (x2, scan_y), color, -1)
    frame[:] = cv2.addWeighted(overlay, 0.05, frame, 0.95, 0)

    for offset, alpha in ((0, 1.0), (3, 0.5), (-3, 0.5)):
        line_overlay = frame.copy()
        cv2.line(line_overlay, (x1, scan_y + offset), (x2, scan_y + offset), color, 1, cv2.LINE_AA)
        frame[:] = cv2.addWeighted(line_overlay, alpha, frame, 1 - alpha, 0)


def draw_pulse_ring(frame, center, base_radius=14, amplitude=4, speed=4.0, color=HUD_CYAN, thickness=1):
    radius = int(base_radius + amplitude * (0.5 + 0.5 * math.sin(time.time() * speed)))
    cv2.circle(frame, center, radius, color, thickness, cv2.LINE_AA)
    cv2.circle(frame, center, 2, color, -1, cv2.LINE_AA)


def draw_progress_arc(frame, center, radius, progress, color, thickness=2):
    progress = max(0.0, min(1.0, progress))
    if progress <= 0.0:
        return
    start_angle = -90
    end_angle = int(start_angle + 360 * progress)
    cv2.ellipse(frame, center, (radius, radius), 0, start_angle, end_angle, color, thickness, cv2.LINE_AA)


def draw_orbit_marker(frame, center, rx, ry, color, speed=1.2):
    angle = time.time() * speed
    x = int(center[0] + math.cos(angle) * rx)
    y = int(center[1] + math.sin(angle) * ry)
    cv2.circle(frame, (x, y), 3, color, -1, cv2.LINE_AA)
    cv2.circle(frame, (x, y), 7, color, 1, cv2.LINE_AA)


def draw_segmented_ticks(frame, bbox, color):
    x1, y1, x2, y2 = bbox
    mid_x = (x1 + x2) // 2
    mid_y = (y1 + y2) // 2
    for offset in (-22, 0, 22):
        cv2.line(frame, (x1 - 12, mid_y + offset), (x1 - 3, mid_y + offset), color, 1, cv2.LINE_AA)
        cv2.line(frame, (x2 + 3, mid_y + offset), (x2 + 12, mid_y + offset), color, 1, cv2.LINE_AA)
    for offset in (-28, 0, 28):
        cv2.line(frame, (mid_x + offset, y1 - 12), (mid_x + offset, y1 - 3), color, 1, cv2.LINE_AA)
        cv2.line(frame, (mid_x + offset, y2 + 3), (mid_x + offset, y2 + 12), color, 1, cv2.LINE_AA)


def draw_landmarks(frame, landmarks, color, radius=1):
    height, width = frame.shape[:2]
    for point in landmarks:
        cv2.circle(frame, _pt(point, width, height), radius, color, -1, cv2.LINE_AA)


def _catmull_rom(points, samples_per_segment=6):
    """Smooth curve through sparse points so the face oval looks round
    instead of faceted."""
    pts = np.array(points, dtype=np.float32)
    n = len(pts)
    if n < 4:
        return pts
    result = []
    for i in range(n):
        p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
        for t in np.linspace(0.0, 1.0, samples_per_segment, endpoint=False):
            t2, t3 = t * t, t * t * t
            point = 0.5 * (
                (2 * p1)
                + (-p0 + p2) * t
                + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2
                + (-p0 + 3 * p1 - 3 * p2 + p3) * t3
            )
            result.append(point)
    return np.array(result, dtype=np.float32)


def draw_polyline(frame, landmarks, indices, color, closed=False, thickness=1, smooth=None):
    height, width = frame.shape[:2]
    raw_points = [[landmarks[index].x * width, landmarks[index].y * height] for index in indices]
    if smooth is None:
        smooth = closed  # smooth closed loops (face oval, eye/mouth rings) by default
    points = _catmull_rom(raw_points) if smooth else np.array(raw_points, dtype=np.float32)
    points = points.astype(np.int32)
    if len(points) >= 2:
        cv2.polylines(frame, [points], closed, color, thickness, cv2.LINE_AA)


def draw_hand_skeleton(frame, landmarks, color=HUD_CYAN):
    """Draw connected hand skeleton with joint dots."""
    height, width = frame.shape[:2]
    points = [_pt(lm, width, height) for lm in landmarks]
    for a, b in HAND_CONNECTIONS:
        cv2.line(frame, points[a], points[b], color, 1, cv2.LINE_AA)
    for point in points:
        cv2.circle(frame, point, 4, PANEL_BG, -1, cv2.LINE_AA)
        cv2.circle(frame, point, 4, color, 1, cv2.LINE_AA)
    cv2.circle(frame, points[MIDDLE_MCP_INDEX], 2, HUD_WHITE, -1, cv2.LINE_AA)


def draw_face_mesh_background(frame, landmarks, color=HUD_CYAN_DIM):
    """Faint scatter of the full landmark set plus fine feature contours
    (eyes, nose bridge, mouth) drawn under the bright foreground outline."""
    height, width = frame.shape[:2]
    overlay = frame.copy()
    for index in range(0, len(landmarks), 8):  # sparse hint, not a visible face mask
        p = landmarks[index]
        cv2.circle(overlay, (int(p.x * width), int(p.y * height)), 1, color, -1, cv2.LINE_AA)
    frame[:] = cv2.addWeighted(overlay, 0.16, frame, 0.84, 0)

    draw_polyline(frame, landmarks, LEFT_EYE_RING, color, closed=True, thickness=1)
    draw_polyline(frame, landmarks, RIGHT_EYE_RING, color, closed=True, thickness=1)
    draw_polyline(frame, landmarks, NOSE_BRIDGE, color, closed=False, thickness=1, smooth=False)


def draw_eye_state(frame, landmarks, ear, threshold, width, height):
    """Trace eye contours and react to blink state: green while open,
    amber plus a line across the lid when EAR drops under threshold."""
    is_closed = ear < threshold
    color = HUD_AMBER if is_closed else HUD_GREEN
    for indices in (LEFT_EYE_RING, RIGHT_EYE_RING):
        points = np.array([_pt(landmarks[i], width, height) for i in indices], dtype=np.int32)
        cv2.polylines(frame, [points], True, color, 2, cv2.LINE_AA)
        y_mid = int(np.mean(points[:, 1]))
        x_min, x_max = int(points[:, 0].min()), int(points[:, 0].max())
        cv2.line(frame, (x_min - 6, y_mid), (x_min - 1, y_mid), color, 1, cv2.LINE_AA)
        cv2.line(frame, (x_max + 1, y_mid), (x_max + 6, y_mid), color, 1, cv2.LINE_AA)
        if is_closed:
            cv2.line(frame, (x_min, y_mid), (x_max, y_mid), color, 2, cv2.LINE_AA)


def draw_face_overlay(frame, landmarks, phase="scanning", ear=None, threshold=None, progress=0.0):
    """phase: 'scanning' (capturing/matching) or 'locked' (matched, reading eyes).

    Layering: dim full mesh underneath, bright outer contour + corner
    brackets on top. Dense tracking below, clean readout above.
    """
    color = HUD_CYAN if phase == "scanning" else HUD_GREEN
    height, width = frame.shape[:2]

    draw_face_mesh_background(frame, landmarks)
    bbox = landmarks_bbox(frame, landmarks, FACE_OUTLINE, pad=0.15)
    x1, y1, x2, y2 = bbox
    cx = (x1 + x2) // 2
    cy = (y1 + y2) // 2
    rx = max(26, (x2 - x1) // 2)
    ry = max(34, (y2 - y1) // 2)

    draw_corner_brackets(frame, bbox, color, size=22, thickness=2)
    draw_segmented_ticks(frame, bbox, color)
    cv2.ellipse(frame, (cx, cy), (rx, ry), 0, 205, 335, color, 2, cv2.LINE_AA)
    cv2.ellipse(frame, (cx, cy), (rx, ry), 0, 25, 155, color, 2, cv2.LINE_AA)
    cv2.line(frame, (cx, y1 - 10), (cx, y1 + 12), color, 1, cv2.LINE_AA)
    cv2.line(frame, (x1 - 10, cy), (x1 + 10, cy), color, 1, cv2.LINE_AA)
    cv2.line(frame, (x2 - 10, cy), (x2 + 10, cy), color, 1, cv2.LINE_AA)
    draw_orbit_marker(frame, (cx, cy), rx + 8, ry + 8, color, speed=1.35)

    left_center = _pt(landmarks[LEFT_EYE_CENTER[0]], width, height)
    right_center = _pt(landmarks[RIGHT_EYE_CENTER[0]], width, height)
    left_center = ((left_center[0] + _pt(landmarks[LEFT_EYE_CENTER[1]], width, height)[0]) // 2, left_center[1])
    right_center = ((right_center[0] + _pt(landmarks[RIGHT_EYE_CENTER[1]], width, height)[0]) // 2, right_center[1])
    cv2.line(frame, (left_center[0], left_center[1]), (right_center[0], right_center[1]), color, 1, cv2.LINE_AA)

    if phase == "scanning":
        draw_scan_sweep(frame, bbox, color=color)
        draw_progress_arc(frame, (cx, cy), max(rx, ry) + 12, progress, color, thickness=2)
    elif phase == "locking":
        draw_progress_arc(frame, (cx, cy), max(rx, ry) + 12, progress, HUD_GREEN, thickness=2)
    elif ear is not None and threshold is not None:
        beam_y = int((left_center[1] + right_center[1]) / 2)
        beam_overlay = frame.copy()
        cv2.rectangle(beam_overlay, (x1 + 10, beam_y - 8), (x2 - 10, beam_y + 8), HUD_GREEN, -1)
        frame[:] = cv2.addWeighted(beam_overlay, 0.08, frame, 0.92, 0)
        cv2.line(frame, (x1 + 8, beam_y), (x2 - 8, beam_y), HUD_GREEN, 1, cv2.LINE_AA)
        draw_pulse_ring(frame, left_center, base_radius=12, amplitude=2, speed=3.2, color=HUD_GREEN)
        draw_pulse_ring(frame, right_center, base_radius=12, amplitude=2, speed=3.2, color=HUD_GREEN)
        draw_eye_state(frame, landmarks, ear, threshold, width, height)
    else:
        draw_pulse_ring(frame, left_center, base_radius=12, amplitude=2, speed=3.2, color=HUD_GREEN)
        draw_pulse_ring(frame, right_center, base_radius=12, amplitude=2, speed=3.2, color=HUD_GREEN)


def ensure_window_open(window_name: str):
    try:
        visible = cv2.getWindowProperty(window_name, cv2.WND_PROP_VISIBLE)
        if visible < 1:
            raise CalibrationError("Camera window closed.")
    except cv2.error:
        raise CalibrationError("Camera window closed.")


def open_camera_window(window_name: str):
    cv2.namedWindow(window_name, cv2.WINDOW_NORMAL)
    cv2.waitKey(100)


def require_camera():
    capture = cv2.VideoCapture(0)
    if not capture.isOpened():
        raise CalibrationError("Could not open the default webcam.")
    return capture


def resolve_model_path(name: str) -> str:
    base = os.path.dirname(os.path.abspath(__file__))
    model_path = os.path.join(base, "models", name)
    if not os.path.exists(model_path):
        raise CalibrationError(f"Required MediaPipe model is missing: {model_path}")
    return model_path


def frame_to_mp_image(frame):
    rgb = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
    return mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb)


class _LandmarkerSession:
    def __enter__(self):
        self._capture = require_camera()

        face_options = vision.FaceLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=resolve_model_path("face_landmarker.task")),
            running_mode=vision.RunningMode.VIDEO,
            num_faces=1,
            min_face_detection_confidence=0.6,
            min_face_presence_confidence=0.6,
            min_tracking_confidence=0.6,
        )
        hand_options = vision.HandLandmarkerOptions(
            base_options=python.BaseOptions(model_asset_path=resolve_model_path("hand_landmarker.task")),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=MAX_HANDS,
            min_hand_detection_confidence=0.6,
            min_hand_presence_confidence=0.6,
            min_tracking_confidence=0.6,
        )

        self._face = vision.FaceLandmarker.create_from_options(face_options)
        self._hand = vision.HandLandmarker.create_from_options(hand_options)
        return self._capture, self._face, self._hand

    def __exit__(self, exc_type, exc, tb):
        self._face.close()
        self._hand.close()
        self._capture.release()
        cv2.destroyAllWindows()


def detect_face(face_landmarker, frame, timestamp_ms):
    result = face_landmarker.detect_for_video(frame_to_mp_image(frame), timestamp_ms)
    if result.face_landmarks:
        return result.face_landmarks[0]
    return None


def detect_hands(hand_landmarker, frame, timestamp_ms, max_hands=MAX_HANDS):
    """Returns up to max_hands detected, ordered by wrist x-position
    (left-to-right as shown on screen). The ordering lets a two-hand
    gesture be compared position-by-position against the enrolled
    template without relying on MediaPipe's Left/Right handedness label."""
    result = hand_landmarker.detect_for_video(frame_to_mp_image(frame), timestamp_ms)
    hands = list(result.hand_landmarks) if result.hand_landmarks else []
    hands.sort(key=lambda landmarks: landmarks[WRIST_INDEX].x)
    return hands[:max_hands]


def detect_hand(hand_landmarker, frame, timestamp_ms):
    """Single-hand convenience wrapper."""
    hands = detect_hands(hand_landmarker, frame, timestamp_ms, max_hands=1)
    return hands[0] if hands else None


def timeout_remaining(started_at: float, limit_seconds: float) -> float:
    return max(0.0, limit_seconds - (time.time() - started_at))


def capture_face_and_blink(capture, face_landmarker, use_embedding: bool):
    open_camera_window(ENROLLMENT_WINDOW)
    face_samples = []
    ear_samples = []
    embedding_samples = []
    stage_started_at = time.time()
    face_lock_started = None
    blink_phase_started = False
    blink_events = 0
    blink_state = "open"
    closed_started = None
    blink_durations = []
    baseline_ear = None
    closed_frames = 0
    open_frames = 0

    while True:
        ensure_window_open(ENROLLMENT_WINDOW)
        ok, frame = capture.read()
        if not ok:
            raise CalibrationError("Webcam frame could not be read.")

        frame = cv2.flip(frame, 1)
        timestamp_ms = int(time.time() * 1000)
        face = detect_face(face_landmarker, frame, timestamp_ms)
        draw_frame_reticle(frame)
        lines = ["Step 1/2: Align your face with the webcam"]
        color = HUD_CYAN
        remaining = timeout_remaining(stage_started_at, FACE_STAGE_TIMEOUT_SECONDS)

        if face:
            metrics = normalized_face_metrics(face)
            ear = average_ear(face)

            if len(face_samples) < FACE_CAPTURE_TARGET:
                scan_progress = len(face_samples) / float(FACE_CAPTURE_TARGET)
                draw_face_overlay(frame, face, phase="scanning", progress=scan_progress)
                face_samples.append(metrics)
                ear_samples.append(ear)
                if use_embedding:
                    try:
                        embedding_samples.append(compute_face_embedding(frame, face))
                    except Exception:
                        # a single bad frame or ONNX error shouldn't abort enrollment
                        pass
                lines.append(f"Scanning face {len(face_samples)}/{FACE_CAPTURE_TARGET}")
                lines.append("Hold still while the face scan settles.")
            else:
                if baseline_ear is None:
                    # use 85th percentile rather than plain mean — if you
                    # blinked during capture, low-EAR frames drag the
                    # baseline down and make threshold too sensitive
                    baseline_ear = float(np.percentile(ear_samples, 85))
                threshold = baseline_ear * 0.82
                now = time.time()
                if not blink_phase_started:
                    if face_lock_started is None:
                        face_lock_started = now
                    lock_progress = min(1.0, (now - face_lock_started) / FACE_LOCK_HOLD_SECONDS)
                    draw_face_overlay(frame, face, phase="locking", progress=lock_progress)
                    color = HUD_GREEN
                    lines = ["Face matched. Holding lock..."]
                    lines.append(f"Stabilizing scan {lock_progress * 100:.0f}%")
                    lines.append("Keep your eyes open and stay centered.")
                    if lock_progress >= 1.0:
                        stage_started_at = time.time()
                        blink_phase_started = True
                        blink_state = "open"
                        blink_events = 0
                        closed_frames = 0
                        open_frames = 0
                else:
                    draw_face_overlay(frame, face, phase="locked", ear=ear, threshold=threshold)
                    color = HUD_GREEN
                    lines = ["Eye scan ready. Blink twice to continue."]
                    lines.append(f"Double blink count: {blink_events}/2")
                    lines.append("Stay in frame. The app will wait for your double blink.")
                    is_closed = ear < threshold

                    if is_closed:
                        closed_frames += 1
                        open_frames = 0
                    else:
                        open_frames += 1
                        closed_frames = 0

                    if blink_state == "open" and closed_frames >= BLINK_CONSEC_FRAMES:
                        blink_state = "closed"
                        closed_started = now
                    elif blink_state == "closed" and open_frames >= BLINK_CONSEC_FRAMES:
                        blink_state = "open"
                        blink_events += 1
                        if closed_started is not None:
                            blink_durations.append(now - closed_started)
                            closed_started = None

                    if blink_events >= 2:
                        averaged_face = {
                            key: sum(sample[key] for sample in face_samples) / len(face_samples)
                            for key in face_samples[0].keys()
                        }
                        averaged_embedding = None
                        if embedding_samples:
                            # average the unit embeddings then re-normalize
                            mean_vec = np.mean(np.array(embedding_samples, dtype=np.float32), axis=0)
                            norm = np.linalg.norm(mean_vec)
                            if norm > 1e-6:
                                averaged_embedding = (mean_vec / norm).tolist()
                        return averaged_face, {
                            "resting_ear": baseline_ear,
                            "double_blink_window_seconds": BLINK_WINDOW_SECONDS,
                            "average_blink_duration": (
                                sum(blink_durations) / len(blink_durations) if blink_durations else 0.0
                            ),
                        }, averaged_embedding
        else:
            color = HUD_RED
            face_lock_started = None
            blink_phase_started = False
            lines.append("No face detected. Move into frame and look forward.")

        remaining_label = int(math.ceil(remaining))
        if blink_phase_started:
            lines.append(f"Eye scan timeout: {remaining_label}s")
        else:
            lines.append(f"Face scan timeout: {remaining_label}s")
        if remaining <= 0.0:
            raise CalibrationError("Face scan timed out. Camera closed.")

        draw_hud_panel(frame, lines, color=color)
        cv2.imshow(ENROLLMENT_WINDOW, frame)
        if cv2.waitKey(1) & 0xFF == 27:
            raise CalibrationError("Enrollment cancelled from the camera window.")


def capture_gesture(capture, hand_landmarker, hand_mode="single"):
    """hand_mode: 'single' enrolls one hand, 'double' requires both hands
    in frame and enrolls them as one combined template."""
    required_hands = 2 if hand_mode == "double" else 1
    stable_samples = []
    hold_started = None
    hand_word = "both hands" if required_hands == 2 else "your chosen hand gesture"

    while True:
        ensure_window_open(ENROLLMENT_WINDOW)
        ok, frame = capture.read()
        if not ok:
            raise CalibrationError("Webcam frame could not be read.")

        frame = cv2.flip(frame, 1)
        timestamp_ms = int(time.time() * 1000)
        detected_hands = detect_hands(hand_landmarker, frame, timestamp_ms)
        draw_frame_reticle(frame)
        lines = [f"Hold {hand_word} steady for {GESTURE_HOLD_SECONDS:.0f} seconds"]
        color = HUD_CYAN

        for i, hand in enumerate(detected_hands[:required_hands]):
            draw_hand_skeleton(frame, hand, color=HUD_CYAN)
            bbox = landmarks_bbox(frame, hand, pad=0.25)
            draw_corner_brackets(frame, bbox, HUD_CYAN, size=18, thickness=2)
            if required_hands > 1:
                label_pt = _pt(hand[WRIST_INDEX], frame.shape[1], frame.shape[0])
                cv2.putText(
                    frame, f"HAND {i + 1}", (label_pt[0] - 20, label_pt[1] + 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, HUD_CYAN, 1, cv2.LINE_AA,
                )

        if len(detected_hands) >= required_hands:
            hands = detected_hands[:required_hands]
            if required_hands == 1 and len(detected_hands) > 1:
                lines.append("Both hands visible. Tracking your dominant hand.")
            elif required_hands == 2:
                for i, hand in enumerate(hands):
                    label_pt = _pt(hand[WRIST_INDEX], frame.shape[1], frame.shape[0])
                    cv2.putText(
                        frame, f"HAND {i + 1}", (label_pt[0] - 20, label_pt[1] + 24),
                        cv2.FONT_HERSHEY_SIMPLEX, 0.45, HUD_CYAN, 1, cv2.LINE_AA,
                    )

            signature = [normalize_hand_landmarks(hand) for hand in hands]

            if stable_samples:
                drift = max(
                    gesture_distance(signature[i], stable_samples[-1][i]) for i in range(required_hands)
                )
                if drift > 0.35:
                    stable_samples = []
                    hold_started = None
                    lines.append("Gesture moved too much. Hold it steady.")
                else:
                    stable_samples.append(signature)
            else:
                stable_samples.append(signature)

            if hold_started is None and stable_samples:
                hold_started = time.time()

            elapsed = 0.0 if hold_started is None else time.time() - hold_started
            lines.append(f"Hold progress: {elapsed:.1f}s / {GESTURE_HOLD_SECONDS:.1f}s")
            if elapsed >= GESTURE_HOLD_SECONDS and len(stable_samples) >= 10:
                return {
                    "hand_mode": hand_mode,
                    "hold_seconds": GESTURE_HOLD_SECONDS,
                    "hands": [
                        average_vectors([sample[i] for sample in stable_samples])
                        for i in range(required_hands)
                    ],
                    "stability_samples": len(stable_samples),
                }
        else:
            color = HUD_RED
            stable_samples = []
            hold_started = None
            if required_hands == 2:
                lines.append(f"Only {len(detected_hands)}/2 hands detected. Raise both hands into frame.")
            else:
                lines.append("No hand detected. Raise your hand into frame.")

        draw_hud_panel(frame, lines, color=color)
        cv2.imshow(ENROLLMENT_WINDOW, frame)
        if cv2.waitKey(1) & 0xFF == 27:
            raise CalibrationError("Enrollment cancelled from the camera window.")


def enroll(gesture: str, bio_key: str, hand_mode: str = "single") -> dict:
    if hand_mode not in HAND_MODE_CHOICES:
        raise ValueError(f"hand_mode must be one of {HAND_MODE_CHOICES}")
    use_embedding = face_embedder_available()

    with _LandmarkerSession() as (capture, face_landmarker, hand_landmarker):
        face_signature, blink_profile, face_embedding = capture_face_and_blink(
            capture, face_landmarker, use_embedding
        )
        hand_profile = capture_gesture(capture, hand_landmarker, hand_mode=hand_mode)

    profile = {
        "created_at": now_iso(),
        "mode": "live",
        "gesture_label": gesture,
        "bio_key": bio_key,
        "face_signature": face_signature,
        "blink_profile": blink_profile,
        "hand_profile": hand_profile,
    }

    if face_embedding is not None:
        profile["face_embedding"] = face_embedding
        security_level = "face_embedding"
        message = "Enrollment profile created from live webcam calibration (face embedding matching enabled)."
    else:
        # No embedding model available (missing onnxruntime or
        # models/face_embedding.onnx) or alignment failed. Enrollment
        # still succeeds but on the weaker ratio-only check.
        security_level = "basic_geometry"
        message = (
            "Enrollment profile created from live webcam calibration. "
            "No face embedding model was available, so this profile uses basic "
            "geometry matching only (eye spacing / face proportions) — weaker "
            "than face-embedding identity matching. Install a face embedding "
            "model to upgrade it."
        )

    profile["security_level"] = security_level

    return {
        "ok": True,
        "message": message,
        "mode": profile["mode"],
        "security_level": security_level,
        "profile": profile,
    }


def verify_face_and_blink(capture, face_landmarker, profile):
    open_camera_window(VERIFICATION_WINDOW)
    # NOTE: no distance readout or corrective hints here — status text is
    # the same regardless of how close the current frame is from a match.
    # Adaptive feedback would let anyone iteratively converge on your profile.
    baseline_ear = profile["blink_profile"]["resting_ear"]
    threshold = baseline_ear * 0.82
    stage_started_at = time.time()
    face_match_frames = 0
    face_lock_started = None
    blink_phase_started = False
    blink_events = 0
    blink_state = "open"
    closed_frames = 0
    open_frames = 0

    while True:
        ensure_window_open(VERIFICATION_WINDOW)
        ok, frame = capture.read()
        if not ok:
            raise CalibrationError("Webcam frame could not be read.")

        frame = cv2.flip(frame, 1)
        timestamp_ms = int(time.time() * 1000)
        face = detect_face(face_landmarker, frame, timestamp_ms)
        draw_frame_reticle(frame)
        lines = ["Verification: align face and blink twice"]
        color = HUD_CYAN
        remaining = timeout_remaining(stage_started_at, FACE_STAGE_TIMEOUT_SECONDS)

        if face:
            identity_match = _face_identity_match(frame, face, profile)
            if not blink_phase_started:
                if identity_match:
                    face_match_frames += 1
                    scan_progress = min(1.0, face_match_frames / float(FACE_MATCH_STABLE_FRAMES))
                    draw_face_overlay(frame, face, phase="scanning", progress=scan_progress)
                    lines = ["Step 1/2: Confirming face match"]
                    lines.append("Keep your face centered and still.")
                    if face_match_frames >= FACE_MATCH_STABLE_FRAMES:
                        now = time.time()
                        if face_lock_started is None:
                            face_lock_started = now
                        lock_progress = min(1.0, (now - face_lock_started) / FACE_LOCK_HOLD_SECONDS)
                        draw_face_overlay(frame, face, phase="locking", progress=lock_progress)
                        lines = ["Face matched. Holding lock..."]
                        lines.append(f"Stabilizing scan {lock_progress * 100:.0f}%")
                        lines.append("Stay steady. Eye scan starts next.")
                        color = HUD_GREEN
                        if lock_progress >= 1.0:
                            stage_started_at = time.time()
                            blink_phase_started = True
                            blink_state = "open"
                            blink_events = 0
                            closed_frames = 0
                            open_frames = 0
                else:
                    face_match_frames = 0
                    face_lock_started = None
                    draw_face_overlay(frame, face, phase="scanning", progress=0.0)
                    lines = ["Step 1/2: Align your face to the frame"]
                    color = HUD_AMBER
            else:
                if not identity_match:
                    face_match_frames = 0
                    face_lock_started = None
                    blink_phase_started = False
                    draw_face_overlay(frame, face, phase="scanning", progress=0.0)
                    lines = ["Step 1/2: Align your face to the frame"]
                    color = HUD_AMBER
                else:
                    ear = average_ear(face)
                    draw_face_overlay(frame, face, phase="locked", ear=ear, threshold=threshold)
                    color = HUD_GREEN
                    lines = ["Step 2/2: Blink twice to continue"]
                    lines.append(f"Double blink count: {blink_events}/2")
                    lines.append("Eye scan is live. Blink naturally.")
                    is_closed = ear < threshold

                    if is_closed:
                        closed_frames += 1
                        open_frames = 0
                    else:
                        open_frames += 1
                        closed_frames = 0

                    if blink_state == "open" and closed_frames >= BLINK_CONSEC_FRAMES:
                        blink_state = "closed"
                    elif blink_state == "closed" and open_frames >= BLINK_CONSEC_FRAMES:
                        blink_state = "open"
                        blink_events += 1
                    if blink_events >= 2:
                        return
        else:
            face_match_frames = 0
            face_lock_started = None
            blink_phase_started = False
            color = HUD_RED
            lines.append("No face detected.")

        remaining_label = int(math.ceil(remaining))
        if blink_phase_started:
            lines.append(f"Eye scan timeout: {remaining_label}s")
        else:
            lines.append(f"Face scan timeout: {remaining_label}s")
        if remaining <= 0.0:
            raise CalibrationError("Face verification timed out. Camera closed.")

        draw_hud_panel(frame, lines, color=color)
        cv2.imshow(VERIFICATION_WINDOW, frame)
        if cv2.waitKey(1) & 0xFF == 27:
            raise CalibrationError("Verification cancelled from the camera window.")


def verify_gesture(capture, hand_landmarker, profile):
    hand_profile = profile["hand_profile"]
    expected_hands = hand_profile.get("hands") or [hand_profile["landmarks"]]
    required_hands = len(expected_hands)
    hold_started = None

    while True:
        ensure_window_open(VERIFICATION_WINDOW)
        ok, frame = capture.read()
        if not ok:
            raise CalibrationError("Webcam frame could not be read.")

        frame = cv2.flip(frame, 1)
        timestamp_ms = int(time.time() * 1000)
        detected_hands = detect_hands(hand_landmarker, frame, timestamp_ms)
        draw_frame_reticle(frame)
        lines = ["Verification: hold your enrolled gesture"]
        color = HUD_CYAN

        matched_hands = []
        if required_hands == 1:
            if len(detected_hands) == 1:
                normalized = normalize_hand_landmarks(detected_hands[0])
                diff = gesture_distance(normalized, expected_hands[0])
                matched = diff <= HAND_GESTURE_MATCH_THRESHOLD
                matched_hands = [detected_hands[0]] if matched else []
            else:
                matched = False
        elif len(detected_hands) >= required_hands:
            hands = detected_hands[:required_hands]
            diffs = [
                gesture_distance(normalize_hand_landmarks(hands[i]), expected_hands[i])
                for i in range(required_hands)
            ]
            matched = all(diff <= HAND_GESTURE_MATCH_THRESHOLD for diff in diffs)
            matched_hands = hands if matched else []
        else:
            matched = False

        for i, hand in enumerate(detected_hands):
            hand_color = HUD_GREEN if hand in matched_hands else HUD_CYAN
            draw_hand_skeleton(frame, hand, color=hand_color)
            bbox = landmarks_bbox(frame, hand, pad=0.25)
            draw_corner_brackets(frame, bbox, hand_color, size=18, thickness=2)
            if len(detected_hands) > 1:
                label_pt = _pt(hand[WRIST_INDEX], frame.shape[1], frame.shape[0])
                cv2.putText(
                    frame, f"HAND {i + 1}", (label_pt[0] - 20, label_pt[1] + 24),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.45, hand_color, 1, cv2.LINE_AA,
                )

        if required_hands == 1:
            if len(detected_hands) == 0:
                hold_started = None
                color = HUD_RED
                lines.append("No hand detected.")
            elif len(detected_hands) > 1:
                hold_started = None
                color = HUD_RED
                lines.append("Reading gesture...")
            elif matched:
                color = HUD_GREEN
                if hold_started is None:
                    hold_started = time.time()
                elapsed = time.time() - hold_started
                lines.append(f"Hold progress: {elapsed:.1f}s / {VERIFY_GESTURE_HOLD_SECONDS:.1f}s")
                if elapsed >= VERIFY_GESTURE_HOLD_SECONDS:
                    return
            else:
                hold_started = None
                lines.append("Reading gesture...")
        else:
            if len(detected_hands) >= required_hands:
                if matched:
                    color = HUD_GREEN
                    if hold_started is None:
                        hold_started = time.time()
                    elapsed = time.time() - hold_started
                    lines.append(f"Hold progress: {elapsed:.1f}s / {VERIFY_GESTURE_HOLD_SECONDS:.1f}s")
                    if elapsed >= VERIFY_GESTURE_HOLD_SECONDS:
                        return
                else:
                    hold_started = None
                    lines.append("Reading gesture...")
            else:
                hold_started = None
                color = HUD_RED
                lines.append("No hand detected.")

        draw_hud_panel(frame, lines, color=color)
        cv2.imshow(VERIFICATION_WINDOW, frame)
        if cv2.waitKey(1) & 0xFF == 27:
            raise CalibrationError("Verification cancelled from the camera window.")


def verify(profile_path: str, gesture: str) -> dict:
    if not os.path.exists(profile_path):
        return {
            "ok": False,
            "message": "Biometric profile is missing.",
        }

    with open(profile_path, "r", encoding="utf-8") as handle:
        profile = json.load(handle)

    if profile.get("gesture_label") != gesture:
        return {
            "ok": False,
            "message": "Gesture profile mismatch.",
        }

    with _LandmarkerSession() as (capture, face_landmarker, hand_landmarker):
        verify_face_and_blink(capture, face_landmarker, profile)
        verify_gesture(capture, hand_landmarker, profile)

    return {
        "ok": True,
        "mode": profile.get("mode", "live"),
        "verified_at": now_iso(),
        "bio_key": profile["bio_key"],
        "security_level": profile.get("security_level", "basic_geometry" if "face_embedding" not in profile else "face_embedding"),
        "message": "Verification completed.",
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--mode", choices=("enroll", "verify"), required=True)
    parser.add_argument("--profile")
    parser.add_argument("--gesture", required=True)
    parser.add_argument("--bio-key")
    parser.add_argument(
        "--hands", choices=HAND_MODE_CHOICES, default="single",
        help="Enroll a one-hand gesture (default) or require both hands together.",
    )
    args = parser.parse_args()

    try:
        if args.mode == "enroll":
            if not args.bio_key:
                raise ValueError("--bio-key is required for enroll mode.")
            response = enroll(args.gesture, args.bio_key, hand_mode=args.hands)
        else:
            if not args.profile:
                raise ValueError("--profile is required for verify mode.")
            response = verify(args.profile, args.gesture)
        print(json.dumps(response))
        return 0 if response.get("ok") else 1
    except CalibrationError as exc:
        print(json.dumps({"ok": False, "message": str(exc)}))
        return 1
    except Exception as exc:
        print(str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
