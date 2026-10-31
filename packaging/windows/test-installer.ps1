param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference='Stop'
if ($env:GITHUB_ACTIONS -ne 'true') { throw 'This installer integration test changes its disposable CI user PATH. Run it only in GitHub Actions.' }
$installerPath=(Resolve-Path -LiteralPath $Installer).Path
$fixture=Join-Path $env:TEMP ('HanX installer test ' + [guid]::NewGuid())
New-Item -ItemType Directory -Path $fixture | Out-Null
$foreign=Join-Path $fixture 'Foreign Tools'
$key=[Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
$original=$key.GetValue('Path',$null,[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$kind=if ($null -eq $original) { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { $key.GetValueKind('Path') }
$baseline='%USERPROFILE%\HanX unrelated path;' + $foreign + ';'
function Run-And-Wait([string]$file,[string]$arguments,[int]$timeout=240) {
  $process=Start-Process -FilePath $file -ArgumentList $arguments -PassThru
  if (-not $process.WaitForExit($timeout*1000)) { Stop-Process -Id $process.Id -Force; throw "Process timed out: $file" }
  $process.Refresh()
  if ($process.ExitCode -ne 0) { throw "Process exited $($process.ExitCode): $file" }
}
try {
  foreach ($mode in @('cli','gui','all')) {
    $target=Join-Path $fixture $mode
    $key.SetValue('Path',$baseline,$kind)
    # NSIS /D must be last and uses the rest of the command line, including spaces.
    Run-And-Wait $installerPath "/S /COMPONENTS=$mode /D=$target"
    $cli=Join-Path $target 'resources\cli\hanx.exe'
    $gui=Join-Path $target 'HanX.exe'
    $cliDirectory=Split-Path $cli
    $raw=[string]$key.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    $hasCLI=@($raw -split ';' | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ieq $cliDirectory }).Count -gt 0
    if ($mode -eq 'cli') {
      if (Test-Path -LiteralPath $gui) { throw 'CLI-only installed a GUI executable.' }
      if (Test-Path -LiteralPath (Join-Path $target 'resources\app.asar')) { throw 'CLI-only retained the GUI application payload.' }
    } elseif (-not (Test-Path -LiteralPath $gui)) { throw "$mode did not install the desktop executable." }
    if ($mode -eq 'gui') {
      if ($hasCLI) { throw 'GUI-only exposed native CLI commands on PATH.' }
      if ($raw -cne $baseline) { throw 'GUI-only changed unrelated user PATH data.' }
    } else {
      if (-not $hasCLI) { throw "$mode did not expose terminal commands." }
      if ($raw -cne ($baseline + ';' + $cliDirectory)) { throw 'Installer rewrote unrelated user PATH entries.' }
      $version=(& $cli --version | ConvertFrom-Json)
      if ($LASTEXITCODE -ne 0 -or $version.data.version -ne '2.9.0') { throw 'Installed CLI version smoke failed.' }
      $aliasVersion=(& (Join-Path $cliDirectory 'hanx-cli.cmd') --version | ConvertFrom-Json)
      if ($LASTEXITCODE -ne 0 -or $aliasVersion.data.version -ne '2.9.0') { throw 'Installed hanx-cli alias failed.' }
    }
    if ($mode -eq 'all') {
      Run-And-Wait $gui '--smoke-test' 180
    }
    $uninstallers=@(Get-ChildItem -LiteralPath $target -Filter 'Uninstall*.exe')
    if ($uninstallers.Count -ne 1) { throw 'Expected one registered uninstaller.' }
    Run-And-Wait $uninstallers[0].FullName "/S _?=$target"
    $after=[string]$key.GetValue('Path','',[Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
    if ($after -cne $baseline) { throw 'Uninstaller did not restore unrelated user PATH data exactly.' }
    if (Test-Path -LiteralPath $cli) { throw 'Uninstaller left the installed native executable.' }
    if (Test-Path -LiteralPath $gui) { throw 'Uninstaller left the desktop executable.' }
    Write-Output "NSIS $mode install, payload, PATH ownership and uninstall passed."
  }
} finally {
  if ($null -eq $original) { $key.DeleteValue('Path',$false) } else { $key.SetValue('Path',$original,$kind) }
  $key.Dispose()
  Remove-Item -LiteralPath $fixture -Recurse -Force -ErrorAction SilentlyContinue
}
