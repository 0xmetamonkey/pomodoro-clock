<#
.SYNOPSIS
  Builds the Windows release, packages it as a zip, and optionally installs it
  for the current user (app folder + Start Menu entry, no admin needed).

.EXAMPLE
  .\scripts\build_windows.ps1              # build + zip into dist\
  .\scripts\build_windows.ps1 -Install     # also install to %LOCALAPPDATA%\Programs
  .\scripts\build_windows.ps1 -Install -DesktopShortcut
#>
[CmdletBinding()]
param(
  [switch]$Install,
  [switch]$DesktopShortcut
)

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$AppName  = 'Pomodoro Clock'
$ExeName  = 'pomodoro_clock.exe'
# pubspec carries "1.0.0+1"; the build number belongs in the app, not the filename.
$VersionParts = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim().Split('+')
$Version      = $VersionParts[0]
$BuildNumber  = if ($VersionParts.Count -gt 1) { $VersionParts[1] } else { '1' }
$DistDir  = 'dist'
$ZipName  = "PomodoroClock-$Version-windows-x64"
$ZipPath  = Join-Path $DistDir "$ZipName.zip"

Write-Host "==> flutter build windows --release ($Version+$BuildNumber)"
flutter build windows --release --build-name $Version --build-number $BuildNumber
if ($LASTEXITCODE -ne 0) { throw "flutter build failed with exit code $LASTEXITCODE" }

# Flutter has moved this output path across releases; take whichever exists.
$candidates = @(
  'build\windows\x64\runner\Release',
  'build\windows\x64\Release',
  'build\windows\runner\Release'
)
$source = $candidates | Where-Object { Test-Path (Join-Path $_ $ExeName) } | Select-Object -First 1
if (-not $source) { throw "Could not find $ExeName under: $($candidates -join ', ')" }
Write-Host "==> Built: $source"

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

# Stage under a named top-level folder so extracting doesn't scatter the app
# files into whatever directory the user unzipped into.
$StageRoot = Join-Path $env:TEMP "pomodoro-clock-zip"
$StageDir  = Join-Path $StageRoot $ZipName
if (Test-Path $StageRoot) { Remove-Item $StageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $StageDir -Recurse
$payload = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File)
try {
  # Compress-Archive writes '\' inside entry names, which is not per the ZIP
  # spec; Explorer tolerates it but 7-Zip/macOS Archive Utility do not.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
  try {
    $baseLen = $StageDir.Length + 1
    foreach ($file in $payload) {
      $relative = $file.FullName.Substring($baseLen).Replace('\', '/')
      [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive, $file.FullName, "$ZipName/$relative",
        [System.IO.Compression.CompressionLevel]::Optimal)
    }
  } finally {
    $archive.Dispose()
  }
} finally {
  Remove-Item $StageRoot -Recurse -Force
}
Write-Host "==> Packaged: $ZipPath  ($($payload.Count) files)"

if (-not $Install) {
  Write-Host ''
  Write-Host "Extract, then run $ZipName\$ExeName. Re-run with -Install to set it up automatically."
  exit 0
}

$target = Join-Path $env:LOCALAPPDATA "Programs\$AppName"
Write-Host "==> Installing to $target"
if (Test-Path $target) { Remove-Item $target -Recurse -Force }
New-Item -ItemType Directory -Force -Path $target | Out-Null
Copy-Item -Path (Join-Path $source '*') -Destination $target -Recurse

$shell = New-Object -ComObject WScript.Shell
$startMenu = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
$shortcutPath = Join-Path $startMenu "$AppName.lnk"
$shortcut = $shell.CreateShortcut($shortcutPath)
$shortcut.TargetPath = Join-Path $target $ExeName
$shortcut.WorkingDirectory = $target
$shortcut.Description = 'Pomodoro timer and world clock'
$shortcut.Save()
Write-Host "==> Start Menu entry: $shortcutPath"

if ($DesktopShortcut) {
  $desktop = [Environment]::GetFolderPath('Desktop')
  $desktopLnk = Join-Path $desktop "$AppName.lnk"
  $link = $shell.CreateShortcut($desktopLnk)
  $link.TargetPath = Join-Path $target $ExeName
  $link.WorkingDirectory = $target
  $link.Save()
  Write-Host "==> Desktop shortcut: $desktopLnk"
}

Write-Host ''
Write-Host "Installed. Launch '$AppName' from the Start Menu, or:"
Write-Host "  Start-Process '$(Join-Path $target $ExeName)'"
