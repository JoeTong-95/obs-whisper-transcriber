param(
    [string]$SourceDir = 'E:\OneDrive\desktop',
    [string]$Pattern = '*.mkv',
    [string]$Model = 'prompt',
    [string]$Device = 'cuda',
    [string]$ComputeType = 'float16'
)

$ErrorActionPreference = 'Stop'
$CalibrationRunsRequired = 3

Add-Type -AssemblyName System.Windows.Forms

function Write-Step {
    param(
        [string]$Message,
        [ConsoleColor]$Color = [ConsoleColor]::Cyan
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    Write-Host "[$timestamp] $Message" -ForegroundColor $Color
}

function Show-Notification {
    param(
        [string]$Title,
        [string]$Message,
        [System.Windows.Forms.MessageBoxIcon]$Icon = [System.Windows.Forms.MessageBoxIcon]::Information
    )

    [void][System.Windows.Forms.MessageBox]::Show(
        $Message,
        $Title,
        [System.Windows.Forms.MessageBoxButtons]::OK,
        $Icon
    )
}

function Get-UniqueRunFolder {
    param(
        [string]$ParentDir,
        [string]$BaseName
    )

    $candidate = Join-Path $ParentDir $BaseName
    if (-not (Test-Path $candidate)) {
        return $candidate
    }

    $suffix = Get-Date -Format 'yyyy-MM-dd_HH-mm-ss'
    return Join-Path $ParentDir ($BaseName + '_' + $suffix)
}

function Format-Duration {
    param([double]$Seconds)

    if ($Seconds -lt 0) {
        $Seconds = 0
    }

    $span = [TimeSpan]::FromSeconds([math]::Round($Seconds))
    if ($span.TotalHours -ge 1) {
        return ('{0:00}:{1:00}:{2:00}' -f [int]$span.TotalHours, $span.Minutes, $span.Seconds)
    }

    return ('{0:00}:{1:00}' -f $span.Minutes, $span.Seconds)
}

function Get-MediaDurationSeconds {
    param([string]$Path)

    $durationText = & ffprobe -v error -show_entries format=duration -of default=noprint_wrappers=1:nokey=1 $Path 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($durationText)) {
        return 0.0
    }

    return [double]::Parse($durationText.Trim(), [System.Globalization.CultureInfo]::InvariantCulture)
}

function Ensure-RunHistoryFile {
    param([string]$HistoryPath)

    if (-not (Test-Path $HistoryPath)) {
        "timestamp,source_file,audio_seconds,model,device,compute_type,ffmpeg_seconds,transcription_seconds,total_seconds" | Set-Content $HistoryPath
    }
}

function Get-RunHistoryRows {
    param(
        [string]$HistoryPath,
        [string]$Model,
        [string]$Device,
        [string]$ComputeType
    )

    if (-not (Test-Path $HistoryPath)) {
        return @()
    }

    return @(Import-Csv $HistoryPath | Where-Object {
        $_.model -eq $Model -and $_.device -eq $Device -and $_.compute_type -eq $ComputeType
    })
}

function Get-ModelEtaInfo {
    param(
        [string]$HistoryPath,
        [string]$Model,
        [string]$Device,
        [string]$ComputeType,
        [double]$AudioSeconds,
        [int]$CalibrationRunsRequired
    )

    $rows = Get-RunHistoryRows -HistoryPath $HistoryPath -Model $Model -Device $Device -ComputeType $ComputeType
    $count = $rows.Count

    if ($count -lt $CalibrationRunsRequired) {
        return [pscustomobject]@{
            Calibrated = $false
            Runs = $count
            RunsRequired = $CalibrationRunsRequired
            EtaSeconds = $null
            Display = "ETA calibrating ($count/$CalibrationRunsRequired runs collected)"
        }
    }

    $ratios = @()
    foreach ($row in $rows) {
        $audio = [double]$row.audio_seconds
        $transcription = [double]$row.transcription_seconds
        if ($audio -gt 0 -and $transcription -gt 0) {
            $ratios += ($transcription / $audio)
        }
    }

    if ($ratios.Count -eq 0) {
        return [pscustomobject]@{
            Calibrated = $false
            Runs = $count
            RunsRequired = $CalibrationRunsRequired
            EtaSeconds = $null
            Display = "ETA calibrating ($count/$CalibrationRunsRequired runs collected)"
        }
    }

    $avgRatio = ($ratios | Measure-Object -Average).Average
    $etaSeconds = [math]::Round($avgRatio * $AudioSeconds, 1)

    return [pscustomobject]@{
        Calibrated = $true
        Runs = $count
        RunsRequired = $CalibrationRunsRequired
        EtaSeconds = $etaSeconds
        Display = "ETA ~$(Format-Duration -Seconds $etaSeconds) based on $count run(s)"
    }
}

function Select-Model {
    param(
        [string]$RequestedModel,
        [string]$HistoryPath,
        [double]$AudioSeconds,
        [string]$Device,
        [string]$ComputeType,
        [int]$CalibrationRunsRequired
    )

    $options = @(
        [pscustomobject]@{ Key = '1'; Model = 'large-v3'; Description = 'Best accuracy, slowest' },
        [pscustomobject]@{ Key = '2'; Model = 'medium'; Description = 'Balanced speed and quality' },
        [pscustomobject]@{ Key = '3'; Model = 'small'; Description = 'Fastest of the three, lower accuracy' }
    )

    if ($RequestedModel -and $RequestedModel -ne 'prompt') {
        $match = $options | Where-Object { $_.Model -eq $RequestedModel } | Select-Object -First 1
        if ($match) {
            return $match.Model
        }
        throw "Unsupported model '$RequestedModel'. Supported values: large-v3, medium, small"
    }

    Write-Host ''
    Write-Step "Audio duration: $(Format-Duration -Seconds $AudioSeconds)"
    Write-Host 'Choose a model:' -ForegroundColor Yellow
    foreach ($option in $options) {
        $etaInfo = Get-ModelEtaInfo -HistoryPath $HistoryPath -Model $option.Model -Device $Device -ComputeType $ComputeType -AudioSeconds $AudioSeconds -CalibrationRunsRequired $CalibrationRunsRequired
        Write-Host ("  {0}. {1,-8} {2} | {3}" -f $option.Key, $option.Model, $option.Description, $etaInfo.Display)
    }
    Write-Host ''

    while ($true) {
        $selection = Read-Host 'Select model [1-3] (default 1)'
        if ([string]::IsNullOrWhiteSpace($selection)) {
            return 'large-v3'
        }

        $match = $options | Where-Object { $_.Key -eq $selection -or $_.Model -eq $selection } | Select-Object -First 1
        if ($match) {
            return $match.Model
        }

        Write-Host 'Invalid selection. Choose 1, 2, 3, or a model name.' -ForegroundColor Red
    }
}

function Invoke-TranscriptionWithProgress {
    param(
        [string]$PythonExe,
        [string]$TranscribeScript,
        [string]$AudioPath,
        [string]$OutputDir,
        [string]$Device,
        [string]$ComputeType,
        [string]$Model
    )

    $outputLines = New-Object System.Collections.Generic.List[string]
    & $PythonExe $TranscribeScript $AudioPath --output-dir $OutputDir --device $Device --compute-type $ComputeType --model $Model --progress 2>&1 |
        ForEach-Object {
            $line = $_.ToString()
            if ($line.StartsWith('PROGRESS|')) {
                $parts = $line.Split('|')
                if ($parts.Length -ge 4) {
                    $percent = [math]::Round([double]$parts[1], 1)
                    $current = [double]$parts[2]
                    $total = [double]$parts[3]
                    $status = ('{0}% ({1:N1}s / {2:N1}s)' -f $percent, $current, $total)
                    Write-Progress -Activity 'Transcribing audio' -Status $status -PercentComplete $percent
                }
            }
            else {
                $outputLines.Add($line)
                Write-Host $line
            }
        }

    $exitCode = $LASTEXITCODE
    Write-Progress -Activity 'Transcribing audio' -Completed

    return @{
        ExitCode = $exitCode
        OutputLines = $outputLines
    }
}

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $transcribeScript = Join-Path $scriptDir 'transcribe.py'
    $runHistoryPath = Join-Path $scriptDir 'run_history.csv'

    Write-Step 'Starting OBS transcription pipeline' Green

    if (-not (Test-Path $transcribeScript)) {
        throw "Transcription script not found: $transcribeScript"
    }

    Ensure-RunHistoryFile -HistoryPath $runHistoryPath

    Write-Step "Searching for latest $Pattern in $SourceDir"
    $latestVideo = Get-ChildItem -Path $SourceDir -Filter $Pattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestVideo) {
        throw "No files matching $Pattern were found in $SourceDir"
    }

    Write-Step "Found source video: $($latestVideo.Name)"
    $audioDurationSeconds = Get-MediaDurationSeconds -Path $latestVideo.FullName
    $selectedModel = Select-Model -RequestedModel $Model -HistoryPath $runHistoryPath -AudioSeconds $audioDurationSeconds -Device $Device -ComputeType $ComputeType -CalibrationRunsRequired $CalibrationRunsRequired
    $selectedEta = Get-ModelEtaInfo -HistoryPath $runHistoryPath -Model $selectedModel -Device $Device -ComputeType $ComputeType -AudioSeconds $audioDurationSeconds -CalibrationRunsRequired $CalibrationRunsRequired
    Write-Step "Selected model: $selectedModel"
    Write-Step $selectedEta.Display Yellow

    $pipelineStopwatch = [System.Diagnostics.Stopwatch]::StartNew()

    $runFolderName = 'transcribed_' + $latestVideo.BaseName.Replace(':', '-')
    $runFolder = Get-UniqueRunFolder -ParentDir $latestVideo.DirectoryName -BaseName $runFolderName
    $sourceFolder = Join-Path $runFolder 'transcribed_source'

    Write-Step "Creating output folder: $runFolder"
    New-Item -ItemType Directory -Force -Path $runFolder | Out-Null
    New-Item -ItemType Directory -Force -Path $sourceFolder | Out-Null

    $wavPath = Join-Path $latestVideo.DirectoryName ($latestVideo.BaseName + '.wav')

    $ffmpegStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    Write-Step "Converting MKV to WAV: $($latestVideo.FullName)"
    & ffmpeg -y -i $latestVideo.FullName -vn $wavPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed while converting $($latestVideo.FullName)"
    }
    $ffmpegStopwatch.Stop()

    Write-Step "WAV created: $wavPath" Green
    Write-Step "Starting transcription with model=$selectedModel device=$Device compute_type=$ComputeType"
    $transcriptionStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $transcriptionResult = Invoke-TranscriptionWithProgress -PythonExe 'python' -TranscribeScript $transcribeScript -AudioPath $wavPath -OutputDir $runFolder -Device $Device -ComputeType $ComputeType -Model $selectedModel
    $transcriptionStopwatch.Stop()
    if ($transcriptionResult.ExitCode -ne 0) {
        throw "Transcription failed for $wavPath"
    }

    Write-Step 'Moving source media into transcribed_source'
    Move-Item -Force -Path $latestVideo.FullName -Destination (Join-Path $sourceFolder $latestVideo.Name)
    Move-Item -Force -Path $wavPath -Destination (Join-Path $sourceFolder ([System.IO.Path]::GetFileName($wavPath)))

    $pipelineStopwatch.Stop()

    $logRow = [pscustomobject]@{
        timestamp = (Get-Date).ToString('s')
        source_file = $latestVideo.Name
        audio_seconds = [math]::Round($audioDurationSeconds, 3)
        model = $selectedModel
        device = $Device
        compute_type = $ComputeType
        ffmpeg_seconds = [math]::Round($ffmpegStopwatch.Elapsed.TotalSeconds, 3)
        transcription_seconds = [math]::Round($transcriptionStopwatch.Elapsed.TotalSeconds, 3)
        total_seconds = [math]::Round($pipelineStopwatch.Elapsed.TotalSeconds, 3)
    }
    $logRow | Export-Csv -Path $runHistoryPath -Append -NoTypeInformation

    $message = @(
        'Finished transcribing.',
        "Source file: $($latestVideo.Name)",
        "Model: $selectedModel",
        "Transcription time: $(Format-Duration -Seconds $transcriptionStopwatch.Elapsed.TotalSeconds)",
        "Transcript folder: $runFolder",
        "Source archive: $sourceFolder"
    ) -join "`n"

    Write-Host ''
    Write-Step 'JOB COMPLETE' Green
    Write-Host $message -ForegroundColor Green
    [console]::beep(1000, 250)
    [console]::beep(1400, 250)
    Show-Notification -Title 'Transcription Complete' -Message $message
}
catch {
    $errorMessage = $_.Exception.Message
    Write-Host ''
    Write-Step 'JOB FAILED' Red
    Write-Error $errorMessage
    [console]::beep(500, 400)
    Show-Notification -Title 'Transcription Failed' -Message $errorMessage -Icon ([System.Windows.Forms.MessageBoxIcon]::Error)
    exit 1
}
