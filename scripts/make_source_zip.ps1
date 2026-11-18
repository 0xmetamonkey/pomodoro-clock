<#
.SYNOPSIS
  Packages the project source into dist\PomodoroClock-<version>-source.zip,
  ready to hand to someone who will run `flutter pub get` and build it themselves.

.EXAMPLE
  .\scripts\make_source_zip.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-Location (Join-Path $PSScriptRoot '..')

$VersionParts = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim().Split('+')
$Version = $VersionParts[0]
$ZipName = "PomodoroClock-$Version"
$DistDir = 'dist'
$ZipPath = Join-Path $DistDir "$ZipName-source.zip"

# Only what a fresh clone needs. Nothing generated belongs in the archive.
$include = @('lib', 'test', 'tool', 'assets', 'scripts', 'docs', 'web',
             'android', 'ios', 'macos', 'windows',
             'pubspec.yaml', 'pubspec.lock', 'analysis_options.yaml',
             'README.md', '.gitignore', '.metadata')

# Flutter regenerates these on `pub get` / first build; they are large and host-specific.
$excludeDirs = @('ephemeral', '.symlinks', 'xcuserdata', 'Pods', 'build', '.dart_tool', 'dist')

$StageRoot = Join-Path $env:TEMP "pomodoro-clock-source-zip"
$StageDir  = Join-Path $StageRoot $ZipName
if (Test-Path $StageRoot) { Remove-Item $StageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageDir | Out-Null

foreach ($item in $include) {
  if (-not (Test-Path $item)) { Write-Host "   (skipping absent: $item)"; continue }
  if ((Get-Item $item).PSIsContainer) {
    Copy-Item -Path $item -Destination (Join-Path $StageDir $item) -Recurse
  } else {
    Copy-Item -Path $item -Destination $StageDir
  }
}

# Materialise first, then delete deepest-first so removing a generated folder
# never invalidates a child still queued for removal.
@(Get-ChildItem -LiteralPath $StageDir -Recurse -Directory -Force) |
  Where-Object { $_.Name -in $excludeDirs } |
  Sort-Object { $_.FullName.Length } -Descending |
  ForEach-Object { Remove-Item $_.FullName -Recurse -Force }

# Sanity check: the archive must at least hold the app entry point, the tests,
# and a drone asset — a Mac built from this zip would otherwise run silently.
foreach ($required in @('lib\main.dart', 'pubspec.yaml', 'test',
                        'assets\audio\tanpura_c.wav')) {
  if (-not (Test-Path (Join-Path $StageDir $required))) {
    throw "Source package would be missing $required - aborting."
  }
}

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }

$files = @(Get-ChildItem -LiteralPath $StageDir -Recurse -File)
try {
  # Same reason as build_windows.ps1: entry names must use '/', not '\'.
  Add-Type -AssemblyName System.IO.Compression.FileSystem
  $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, 'Create')
  try {
    $baseLen = $StageDir.Length + 1
    foreach ($file in $files) {
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

Write-Host "==> $ZipPath  ($($files.Count) files, $([math]::Round((Get-Item $ZipPath).Length / 1KB)) KB)"
