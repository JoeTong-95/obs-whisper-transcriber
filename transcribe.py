from __future__ import annotations

import argparse
import json
from pathlib import Path
from typing import Any

from faster_whisper import WhisperModel


REPO_ROOT = Path(__file__).resolve().parents[3]
DEFAULT_MODEL_DIR = REPO_ROOT / "models" / "faster-whisper"
DEFAULT_OUTPUT_DIR = REPO_ROOT / "outputs" / "audio" / "faster-whisper"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Transcribe an audio file locally with faster-whisper."
    )
    parser.add_argument("audio_path", type=Path, help="Path to an input audio file.")
    parser.add_argument(
        "--model",
        default="large-v3",
        help="Whisper model size or local model path. Default: large-v3",
    )
    parser.add_argument(
        "--model-dir",
        type=Path,
        default=DEFAULT_MODEL_DIR,
        help=f"Directory for downloaded Whisper models. Default: {DEFAULT_MODEL_DIR}",
    )
    parser.add_argument(
        "--output-dir",
        type=Path,
        default=DEFAULT_OUTPUT_DIR,
        help=f"Directory for transcript outputs. Default: {DEFAULT_OUTPUT_DIR}",
    )
    parser.add_argument(
        "--device",
        default="auto",
        choices=["auto", "cpu", "cuda"],
        help="Inference device. Default: auto",
    )
    parser.add_argument(
        "--compute-type",
        default="auto",
        help="Computation type passed to faster-whisper. Examples: auto, float16, int8_float16, int8.",
    )
    parser.add_argument(
        "--language",
        default=None,
        help="Optional language code like en. Leave unset for auto-detection.",
    )
    parser.add_argument(
        "--task",
        default="transcribe",
        choices=["transcribe", "translate"],
        help="Whether to transcribe or translate to English. Default: transcribe",
    )
    parser.add_argument(
        "--beam-size",
        type=int,
        default=5,
        help="Beam size for decoding. Default: 5",
    )
    parser.add_argument(
        "--vad-filter",
        action="store_true",
        help="Enable voice activity detection to trim silence.",
    )
    return parser.parse_args()


def format_timestamp(seconds: float) -> str:
    total_ms = int(round(seconds * 1000))
    hours, remainder = divmod(total_ms, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, ms = divmod(remainder, 1000)
    return f"{hours:02}:{minutes:02}:{secs:02},{ms:03}"


def format_vtt_timestamp(seconds: float) -> str:
    return format_timestamp(seconds).replace(",", ".")


def write_text(segments: list[dict[str, Any]], output_path: Path) -> None:
    output_path.write_text(
        "\n".join(segment["text"].strip() for segment in segments).strip() + "\n",
        encoding="utf-8",
    )


def write_json(
    segments: list[dict[str, Any]], info: dict[str, Any], output_path: Path
) -> None:
    payload = {
        "info": info,
        "segments": segments,
        "text": " ".join(segment["text"].strip() for segment in segments).strip(),
    }
    output_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")


def write_srt(segments: list[dict[str, Any]], output_path: Path) -> None:
    lines: list[str] = []
    for index, segment in enumerate(segments, start=1):
        lines.extend(
            [
                str(index),
                f"{format_timestamp(segment['start'])} --> {format_timestamp(segment['end'])}",
                segment["text"].strip(),
                "",
            ]
        )
    output_path.write_text("\n".join(lines), encoding="utf-8")


def write_vtt(segments: list[dict[str, Any]], output_path: Path) -> None:
    lines = ["WEBVTT", ""]
    for segment in segments:
        lines.extend(
            [
                f"{format_vtt_timestamp(segment['start'])} --> {format_vtt_timestamp(segment['end'])}",
                segment["text"].strip(),
                "",
            ]
        )
    output_path.write_text("\n".join(lines), encoding="utf-8")


def main() -> None:
    args = parse_args()
    audio_path = args.audio_path.expanduser().resolve()
    if not audio_path.exists():
        raise FileNotFoundError(f"Audio file not found: {audio_path}")

    args.model_dir.mkdir(parents=True, exist_ok=True)
    args.output_dir.mkdir(parents=True, exist_ok=True)

    model = WhisperModel(
        args.model,
        device=args.device,
        compute_type=args.compute_type,
        download_root=str(args.model_dir),
    )

    segments_iter, info = model.transcribe(
        str(audio_path),
        beam_size=args.beam_size,
        language=args.language,
        task=args.task,
        vad_filter=args.vad_filter,
    )

    segments = [
        {
            "id": segment.id,
            "start": segment.start,
            "end": segment.end,
            "text": segment.text,
        }
        for segment in segments_iter
    ]

    info_payload = {
        "language": info.language,
        "language_probability": info.language_probability,
        "duration": info.duration,
        "duration_after_vad": info.duration_after_vad,
        "transcription_options": {
            "model": args.model,
            "device": args.device,
            "compute_type": args.compute_type,
            "task": args.task,
            "beam_size": args.beam_size,
            "vad_filter": args.vad_filter,
        },
        "source_audio": str(audio_path),
    }

    stem = audio_path.stem
    json_path = args.output_dir / f"{stem}.json"
    text_path = args.output_dir / f"{stem}.txt"
    srt_path = args.output_dir / f"{stem}.srt"
    vtt_path = args.output_dir / f"{stem}.vtt"

    write_json(segments, info_payload, json_path)
    write_text(segments, text_path)
    write_srt(segments, srt_path)
    write_vtt(segments, vtt_path)

    print(f"Transcribed: {audio_path}")
    print(f"Detected language: {info.language} ({info.language_probability:.2%})")
    print("Outputs:")
    print(f"  TXT  {text_path}")
    print(f"  JSON {json_path}")
    print(f"  SRT  {srt_path}")
    print(f"  VTT  {vtt_path}")


if __name__ == "__main__":
    main()
