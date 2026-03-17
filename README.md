# OBS Whisper Transcriber

Small local Windows project for turning the newest OBS `.mkv` recording on your Desktop into a Whisper transcript.

## Workflow

1. Record in OBS to `.mkv`.
2. Run `run-latest-obs.bat`.
3. The script finds the newest `.mkv` in `E:\OneDrive\desktop`.
4. `ffmpeg` extracts the first audio track to `.wav`.
5. `faster-whisper` transcribes the `.wav` locally.
6. A folder named `transcribed_<source-name>` is created on the Desktop.
7. Transcript files are written into that folder.
8. The original `.mkv` and generated `.wav` are moved into `transcribed_source` inside that folder.

## Files

- `install.bat`: installs Python requirements and checks `ffmpeg`
- `run-latest-obs.bat`: launches the pipeline in a terminal window
- `process-latest-obs.ps1`: main workflow script
- `transcribe.py`: local `faster-whisper` transcription CLI
- `requirements.txt`: Python package requirements

## Requirements

- Windows
- Python 3.10+
- `ffmpeg` available in PATH
- NVIDIA GPU recommended for best performance

## Install

Double-click `install.bat`, or run:

```powershell
.\install.bat
```

The first real transcription run will download the Whisper model automatically.

## Run

Double-click `run-latest-obs.bat`, or run:

```powershell
.\run-latest-obs.bat
```

## Output Layout

Example output folder:

```text
E:\OneDrive\desktop\transcribed_2026-03-17 11-59-19\
```

Files created there:

- `2026-03-17 11-59-19.txt`
- `2026-03-17 11-59-19.json`
- `2026-03-17 11-59-19.srt`
- `2026-03-17 11-59-19.vtt`
- `transcribed_source\2026-03-17 11-59-19.mkv`
- `transcribed_source\2026-03-17 11-59-19.wav`

## Notes

- The current script extracts the first audio track from the OBS `.mkv`.
- The default transcription model is `large-v3` on `cuda` with `float16`.
- If a transcript folder with the same name already exists, the script creates a unique timestamped folder instead.
