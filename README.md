# OBS Whisper Transcriber

Local Windows workflow for taking the newest OBS `.mkv` recording from the Desktop, extracting audio with `ffmpeg`, transcribing it with `faster-whisper`, and archiving both the source media and transcript outputs.
`run-latest-obs.bat` allows choosing 3 models to run the pipeline and provides ETA based on previous runs.

## Files

- `install.bat`: installs Python dependencies and checks `ffmpeg`
- `run-latest-obs.bat`: opens the interactive terminal workflow
- `process-latest-obs.ps1`: main workflow script
- `transcribe.py`: local `faster-whisper` transcription CLI
- `requirements.txt`: Python package requirements
- `run_history.csv`: created automatically after the first successful run

## Workflow

1. Record in OBS to `.mkv` on `E:\OneDrive\desktop`.
2. Run `run-latest-obs.bat`.
3. The script finds the newest `.mkv`.
4. It shows a model selector:
   - `large-v3`
   - `medium`
   - `small`
5. For each model it shows either:
   - a local ETA from prior runs
   - or a calibration message like `ETA calibrating (1/3 runs collected)`
6. It converts the `.mkv` to `.wav` with `ffmpeg`.
7. It transcribes the `.wav` locally with `faster-whisper`.
8. A terminal progress bar is shown during inference.
9. A folder named `transcribed_<source-name>` is created on the Desktop.
10. Transcript files go into that folder.
11. The source `.mkv` and generated `.wav` are moved into `transcribed_source` inside that folder.
12. Timing data is appended to `run_history.csv` for future ETA estimates.

## Install

Double-click `install.bat`, or run:

```powershell
.\install.bat
```

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

- The script currently extracts the first audio track from the OBS `.mkv`.
- The default device settings are `cuda` and `float16`.
- The standalone folder stores models under `models/faster-whisper/` and generic outputs under `outputs/audio/faster-whisper/` when you use `transcribe.py` directly.
