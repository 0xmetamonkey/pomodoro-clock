<#
.SYNOPSIS
  Runs the built Windows app and screenshots its own window — and only its own.

.DESCRIPTION
  PrintWindow hands back a black frame for this Flutter window, so the capture
  is a screen-region grab. That is only safe when the window really is the top
  thing at those pixels, so every grab first asks WindowFromPoint who owns the
  centre of the window and refuses to shoot if the answer is somebody else's
  app. Whatever else is on the screen stays off these files.

  Keys are posted at the window instead of injected, so nothing the user is
  typing somewhere else gets hijacked: T flips the theme, Space starts a block,
  R resets it — the same shortcuts the UI advertises.
#>
param(
  [int]$Width = 1240,
  [int]$Height = 780,
  [string]$OutDir = "$PSScriptRoot\..\screenshots"
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct Rect { public int l, t, r, b; }
  [StructLayout(LayoutKind.Sequential)] public struct Point { public int x, y; }

  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool r);
  [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int w, int ht, uint f);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint msg, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out Rect r);
  [DllImport("user32.dll")] public static extern IntPtr WindowFromPoint(Point p);
  [DllImport("user32.dll")] public static extern IntPtr GetAncestor(IntPtr h, uint flags);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
'@
[Win]::SetProcessDPIAware() | Out-Null

function Find-App { Get-Process pomodoro_clock -ErrorAction SilentlyContinue }

# One instance at a time, closed politely rather than killed.
foreach ($p in Find-App) {
  Write-Host "closing existing instance $($p.Id) with WM_CLOSE"
  [Win]::PostMessage($p.MainWindowHandle, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}
while (Find-App) { Start-Sleep -Milliseconds 250 }

$exe = Join-Path $PSScriptRoot '..\build\windows\x64\runner\Release\pomodoro_clock.exe'
$app = Start-Process $exe -PassThru
Start-Sleep -Seconds 6
$app.Refresh()
$hwnd = $app.MainWindowHandle
if ([int64]$hwnd -eq 0) { throw 'the app window did not appear' }

# Topmost is enough; taking the foreground would yank focus off whatever the
# user is doing.
[Win]::ShowWindow($hwnd, 5) | Out-Null
[Win]::MoveWindow($hwnd, 40, 40, $Width, $Height, $true) | Out-Null
[Win]::SetWindowPos($hwnd, [IntPtr](-1), 0, 0, 0, 0, [UInt32](0x40 -bor 0x1 -bor 0x4)) | Out-Null
Start-Sleep -Milliseconds 1500

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Test-Topmost {
  $r = New-Object Win+Rect
  [Win]::GetWindowRect($hwnd, [ref]$r) | Out-Null
  $pt = New-Object Win+Point
  $pt.x = ($r.l + $r.r) / 2
  $pt.y = ($r.t + $r.b) / 2
  $hit = [Win]::WindowFromPoint($pt)
  # GA_ROOT (2): the top-level owner of whatever window sits at those pixels.
  return [int64]([Win]::GetAncestor($hit, 2)) -eq [int64]$hwnd
}

function Grab([string]$name) {
  if (-not (Test-Topmost)) {
    Write-Warning "$name skipped: another window is above the app, not shooting it"
    return
  }
  $r = New-Object Win+Rect
  [Win]::GetWindowRect($hwnd, [ref]$r) | Out-Null
  $w = $r.r - $r.l; $h = $r.b - $r.t
  $bmp = New-Object System.Drawing.Bitmap $w, $h
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.l, $r.t, 0, 0, $bmp.Size)
  $path = Join-Path $OutDir $name
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Host "wrote $path ($w x $h)"
}

# lParam carries a real scan code: that is what the engine reads next to the
# virtual key when it maps a physical key.
function Tap([int]$vk, [int]$scan, [int]$char) {
  $down = ($scan -shl 16) -bor 1
  $up = $down -bor 0xC0010000
  [Win]::PostMessage($hwnd, 0x0100, [IntPtr]$vk, [IntPtr]$down) | Out-Null
  [Win]::PostMessage($hwnd, 0x0102, [IntPtr]$char, [IntPtr]$down) | Out-Null
  [Win]::PostMessage($hwnd, 0x0101, [IntPtr]$vk, [IntPtr]$up) | Out-Null
  Start-Sleep -Milliseconds 700
}

Grab 'windows-dark.png'
Tap 0x54 0x14 0x54          # T — light
Grab 'windows-light.png'
Tap 0x54 0x14 0x54          # T — back to dark, the shipped default
Tap 0x20 0x39 0x20          # Space — a block is counting
Start-Sleep -Milliseconds 1200
Grab 'windows-running.png'
Tap 0x20 0x39 0x20          # pause again
Tap 0x52 0x13 0x52          # R — reset, so nothing half-finished is left behind

[Win]::SetWindowPos($hwnd, [IntPtr](0), 0, 0, 0, 0, [UInt32](0x40 -bor 0x1 -bor 0x4)) | Out-Null
[Win]::PostMessage($hwnd, 0x0010, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
Write-Host 'done'
