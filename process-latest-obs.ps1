param(
    [string]$SourceDir = 'E:\OneDrive\desktop',
    [string]$Pattern = '*.mkv',
    [string]$Model = 'large-v3',
    [string]$Device = 'cuda',
    [string]$ComputeType = 'float16'
)

$ErrorActionPreference = 'Stop'

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

try {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $transcribeScript = Join-Path $scriptDir 'transcribe.py'

    Write-Step 'Starting OBS transcription pipeline' Green

    if (-not (Test-Path $transcribeScript)) {
        throw "Transcription script not found: $transcribeScript"
    }

    Write-Step "Searching for latest $Pattern in $SourceDir"
    $latestVideo = Get-ChildItem -Path $SourceDir -Filter $Pattern -File |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1

    if (-not $latestVideo) {
        throw "No files matching $Pattern were found in $SourceDir"
    }

    Write-Step "Found source video: $($latestVideo.Name)"

    $runFolderName = 'transcribed_' + $latestVideo.BaseName.Replace(':', '-')
    $runFolder = Get-UniqueRunFolder -ParentDir $latestVideo.DirectoryName -BaseName $runFolderName
    $sourceFolder = Join-Path $runFolder 'transcribed_source'

    Write-Step "Creating output folder: $runFolder"
    New-Item -ItemType Directory -Force -Path $runFolder | Out-Null
    New-Item -ItemType Directory -Force -Path $sourceFolder | Out-Null

    $wavPath = Join-Path $latestVideo.DirectoryName ($latestVideo.BaseName + '.wav')

    Write-Step "Converting MKV to WAV: $($latestVideo.FullName)"
    & ffmpeg -y -i $latestVideo.FullName -vn $wavPath
    if ($LASTEXITCODE -ne 0) {
        throw "ffmpeg failed while converting $($latestVideo.FullName)"
    }

    Write-Step "WAV created: $wavPath" Green
    Write-Step "Starting transcription with model=$Model device=$Device compute_type=$ComputeType"
    & python $transcribeScript $wavPath --output-dir $runFolder --device $Device --compute-type $ComputeType --model $Model
    if ($LASTEXITCODE -ne 0) {
        throw "Transcription failed for $wavPath"
    }

    Write-Step 'Moving source media into transcribed_source'
    Move-Item -Force -Path $latestVideo.FullName -Destination (Join-Path $sourceFolder $latestVideo.Name)
    Move-Item -Force -Path $wavPath -Destination (Join-Path $sourceFolder ([System.IO.Path]::GetFileName($wavPath)))

    $message = @(
        'Finished transcribing.',
        "Source file: $($latestVideo.Name)",
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
