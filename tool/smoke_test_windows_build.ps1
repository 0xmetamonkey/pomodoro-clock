# Smoke-tests a Windows build without touching the installed app or the
# user's real settings.
#
#   powershell -File tool/smoke_test_windows_build.ps1 -Zip C:\path\to\x.zip
#
# It unpacks to a temp directory, runs the exe, waits for the real window,
# closes it with WM_CLOSE rather than killing it, and cleans everything up.
# Exits 1 on any failure so CI or a script can branch on it.
#
# The app's settings ARE touched: path_provider resolves %APPDATA% through
# SHGetKnownFolderPath, which ignores an environment override, so the build
# reads and writes the real shared_preferences.json under
# %APPDATA%\com.pomodoro. That file is therefore copied aside first and put
# back byte-for-byte afterwards.

param(
    [Parameter(Mandatory = $true)][string]$Zip,
    [int]$WindowTimeoutSeconds = 40
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$sources = @'
using System;
using System.Runtime.InteropServices;
public static class Win {
    [DllImport("user32.dll", SetLastError = true)]
    public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr W, IntPtr L);
    [DllImport("user32.dll")]
    public static extern bool IsWindowVisible(IntPtr hWnd);
    public const uint WM_CLOSE = 0x0010;
}
'@
Add-Type -TypeDefinition $sources

function Fail([string]$m) { Write-Host "FAIL  $m"; exit 1 }

if (-not (Test-Path $Zip)) { Fail "no such zip: $Zip" }

$work = Join-Path $env:TEMP ("smoke_" + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Force -Path $work | Out-Null

$prefsPath = Join-Path $env:APPDATA 'com.pomodoro\pomodoro_clock\shared_preferences.json'
$prefsBackup = Join-Path $work 'shared_preferences.json.bak'
$prefsExisted = $false

try {
    if (Test-Path $prefsPath) {
        Copy-Item $prefsPath $prefsBackup
        $prefsExisted = $true
        Write-Host "settings  : backed up $prefsPath"
    } else {
        Write-Host 'settings  : no existing file to back up'
    }

    Write-Host "Unpacking $Zip"
    Expand-Archive -LiteralPath $Zip -DestinationPath $work -Force

    $exe = Get-ChildItem -Path $work -Recurse -Filter 'pomodoro_clock.exe' |
        Select-Object -First 1
    if (-not $exe) { Fail 'pomodoro_clock.exe not found in the archive' }
    $appDir = $exe.DirectoryName

    Write-Host "Launching $appDir\pomodoro_clock.exe"
    $proc = Start-Process -FilePath $exe.FullName -WorkingDirectory $appDir `
        -PassThru

    $deadline = (Get-Date).AddSeconds($WindowTimeoutSeconds)
    $hwnd = [IntPtr]::Zero
    while ((Get-Date) -lt $deadline) {
        $proc.Refresh()
        if ($proc.HasExited) {
            Fail "process exited early with code $($proc.ExitCode)"
        }
        if ($proc.MainWindowHandle -ne [IntPtr]::Zero) {
            $hwnd = $proc.MainWindowHandle
            break
        }
        Start-Sleep -Milliseconds 500
    }
    if ($hwnd -eq [IntPtr]::Zero) { Fail 'no main window appeared' }
    Write-Host ("window    : ""{0}""  visible={1}" -f `
            $proc.MainWindowTitle, [Win]::IsWindowVisible($hwnd))

    # Let the engine settle and the first frame render.
    Start-Sleep -Seconds 6
    $proc.Refresh()
    if ($proc.HasExited) { Fail "process exited during idle with code $($proc.ExitCode)" }

    # Graceful close, never Stop-Process -Force.
    [void][Win]::PostMessage($hwnd, [Win]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
    if (-not $proc.WaitForExit(20000)) { Fail 'window did not close on WM_CLOSE' }
    Write-Host "exit code : $($proc.ExitCode)"
    if ($proc.ExitCode -ne 0) { Fail "non-zero exit code $($proc.ExitCode)" }

    $crashes = Get-ChildItem -Path $work -Recurse -Filter '*.dmp' -ErrorAction SilentlyContinue
    if ($crashes) { Fail "crash dumps present: $($crashes.Name -join ', ')" }

    Write-Host 'PASS      the build launched, drew its window and closed cleanly'
} finally {
    Get-Process pomodoro_clock -ErrorAction SilentlyContinue | ForEach-Object {
        if ($_.StartTime -gt (Get-Date).AddMinutes(-5)) {
            [void][Win]::PostMessage($_.MainWindowHandle, [Win]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
        }
    }
    Start-Sleep -Seconds 2

    # Put the user's settings back exactly as they were, whether or not the
    # test succeeded.
    if ($prefsExisted) {
        Copy-Item $prefsBackup $prefsPath -Force
        Write-Host "settings  : restored $((Get-Item $prefsPath).Length) bytes to $prefsPath"
    } elseif (Test-Path $prefsPath) {
        Remove-Item $prefsPath -Force
        Write-Host 'settings  : removed the file the test created'
    }

    Remove-Item -Path $work -Recurse -Force -ErrorAction SilentlyContinue
}
