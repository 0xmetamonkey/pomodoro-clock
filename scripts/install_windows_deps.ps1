# Adds the components `flutter build windows` needs to the existing
# Visual Studio 2019 Build Tools instance. Run it, then accept the UAC prompt.
$ErrorActionPreference = 'Stop'

$installer = 'C:\Program Files (x86)\Microsoft Visual Studio\Installer\setup.exe'
$installPath = 'C:\Program Files (x86)\Microsoft Visual Studio\2019\BuildTools'

if (-not (Test-Path $installer)) {
  Write-Error "Visual Studio installer not found at $installer"
}

$components = @(
  'Microsoft.VisualStudio.Component.Windows10SDK.20348',
  'Microsoft.VisualStudio.Component.VC.CMake.Project'
)

# Start-Process joins an argument *array* with spaces without re-quoting, so the
# spaced install path must be quoted here or the installer rejects the command.
$argList = "modify --installPath `"$installPath`"" +
  " --add Microsoft.VisualStudio.Component.Windows10SDK.20348" +
  " --add Microsoft.VisualStudio.Component.VC.CMake.Project" +
  " --passive --norestart"

Write-Host "Requesting elevation for: $($components -join ', ')"
$proc = Start-Process -FilePath $installer -ArgumentList $argList -Verb RunAs -PassThru
Write-Host "Installer PID $($proc.Id); waiting for it to finish..."
$proc.WaitForExit()
Write-Host "Installer exit code: $($proc.ExitCode)"
