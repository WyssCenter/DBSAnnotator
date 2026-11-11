# Records a docs video of the real Windows app while an integration test drives it,
# with captions (a WebVTT file beside the video) and a spoken voice from the same lines.
#   powershell -File tool/record_video.ps1 -Flow record_block
#   powershell -File tool/record_video.ps1 -Flow reports
# The voice is Piper's public-domain LJSpeech voice, run offline; it is downloaded once
# into %LOCALAPPDATA%\dbs_annotator_voices. -NoVoice records captions only.
param(
    [Parameter(Mandatory)][ValidateSet('record_block', 'reports')][string]$Flow,
    [switch]$NoVoice
)
$ErrorActionPreference = 'Stop'

$root = Resolve-Path "$PSScriptRoot/.."
$out = "$root/docs/_static/videos"
$marks = Join-Path ([IO.Path]::GetTempPath()) "dbs_video_$Flow"
$raw = "$marks/raw.mkv"
$ffmpeg = (Get-Command ffmpeg -ErrorAction SilentlyContinue).Source
if (-not $ffmpeg) { $ffmpeg = "$env:LOCALAPPDATA/Microsoft/WinGet/Links/ffmpeg.exe" }
$flutter = (Get-Command flutter -ErrorAction SilentlyContinue).Source
if (-not $flutter) { $flutter = 'C:/ProgramData/flutter/bin/flutter.bat' }
$uvx = (Get-Command uvx -ErrorAction Stop).Source

Remove-Item $marks -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $marks, $out | Out-Null

$defines = "--dart-define=VIDEO_ROOT=$root --dart-define=VIDEO_MARKS=$marks"
if (-not $NoVoice) {
    $voices = "$env:LOCALAPPDATA/dbs_annotator_voices"
    $voice = "$voices/en_US-ljspeech-high.onnx"
    if (-not (Test-Path $voice)) {
        New-Item -ItemType Directory -Force $voices | Out-Null
        Push-Location $voices
        & $uvx --from piper-tts python -m piper.download_voices en_US-ljspeech-high
        Pop-Location
    }
    $defines += " --dart-define=VIDEO_VOICE=$voice --dart-define=VIDEO_UVX=$uvx"
}

function Wait-Mark($name, $test) {
    while (-not (Test-Path "$marks/$name")) {
        if ($test.HasExited) { throw "The test ended before '$name'. See $marks/test.log" }
        Start-Sleep -Milliseconds 100
    }
}

$test = Start-Process $flutter -PassThru -NoNewWindow -WorkingDirectory $root `
    -RedirectStandardOutput "$marks/test.log" -RedirectStandardError "$marks/test.err" `
    -ArgumentList "test integration_test/videos/${Flow}_test.dart -d windows $defines"
Wait-Mark ready $test

$psi = [Diagnostics.ProcessStartInfo]::new($ffmpeg,
    "-y -hide_banner -loglevel error -f gdigrab -framerate 30 -draw_mouse 0 -i `"title=DBS Annotator video`" -c:v libx264 -preset ultrafast -crf 10 `"$raw`"")
$psi.UseShellExecute = $false
$psi.RedirectStandardInput = $true
$rec = [Diagnostics.Process]::Start($psi)
$recStart = [DateTimeOffset]::Now.ToUnixTimeMilliseconds()
Wait-Mark done $test
$rec.StandardInput.Write('q')
$rec.WaitForExit()
$test.WaitForExit()

# Each line the test said: when it started and ended, its WAV, and its text.
$cues = @(
    if (Test-Path "$marks/captions.tsv") {
        Get-Content "$marks/captions.tsv" -Encoding UTF8 | ForEach-Object {
            $f = $_ -split "`t", 4
            [pscustomobject]@{
                Start = [math]::Max(0, [long]$f[0] - $recStart)
                End   = [long]$f[1] - $recStart
                Wav   = $f[2]
                Text  = $f[3]
            }
        }
    }
)

function Stamp([long]$ms) {
    $t = [TimeSpan]::FromMilliseconds($ms)
    '{0:00}:{1:00}:{2:00}.{3:000}' -f [int][math]::Floor($t.TotalHours), $t.Minutes, $t.Seconds, $t.Milliseconds
}
$vtt = [Text.StringBuilder]::new("WEBVTT`n`n")
for ($i = 0; $i -lt $cues.Count; $i++) {
    $end = $cues[$i].End
    if ($i + 1 -lt $cues.Count) { $end = [math]::Min($end, $cues[$i + 1].Start) }
    [void]$vtt.Append("$(Stamp $cues[$i].Start) --> $(Stamp $end)`n$($cues[$i].Text)`n`n")
}
[IO.File]::WriteAllText("$out/$Flow.vtt", $vtt.ToString(), [Text.UTF8Encoding]::new($false))

$inputs = @('-i', $raw)
$filter = '[0:v]scale=1280:-2[v]'
$audio = @('-an')
$spoken = @($cues | Where-Object { $_.Wav })
if ($spoken.Count -gt 0) {
    $labels = ''
    for ($i = 0; $i -lt $spoken.Count; $i++) {
        $inputs += @('-i', $spoken[$i].Wav)
        $delay = $spoken[$i].Start
        $filter += ";[$($i + 1):a]adelay=${delay}|${delay}[a$i]"
        $labels += "[a$i]"
    }
    $filter += ";${labels}amix=inputs=$($spoken.Count):normalize=0[voice]"
    $audio = @('-map', '[voice]', '-c:a', 'aac', '-b:a', '96k')
}
& $ffmpeg -y -hide_banner -loglevel error @inputs -filter_complex $filter -map '[v]' `
    -c:v libx264 -crf 28 -pix_fmt yuv420p -movflags +faststart @audio "$out/$Flow.mp4"
& $ffmpeg -y -hide_banner -loglevel error -ss 0.5 -i "$out/$Flow.mp4" -frames:v 1 "$out/$Flow.png"
Get-Item "$out/$Flow.mp4", "$out/$Flow.png", "$out/$Flow.vtt" | Select-Object Name, Length
