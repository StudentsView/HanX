$ErrorActionPreference = 'Stop'
$script = Join-Path $PSScriptRoot 'manage-path.ps1'
$entry = Join-Path $env:TEMP ('HanX PATH test ' + [guid]::NewGuid().ToString())
$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
$original = $key.GetValue('Path', $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
$kind = if ($null -eq $original) { [Microsoft.Win32.RegistryValueKind]::ExpandString } else { $key.GetValueKind('Path') }
try {
  $baseline = '%USERPROFILE%\existing;C:\A path with spaces;'
  $key.SetValue('Path', $baseline, $kind)
  & $script -Action Install -CliDirectory $entry
  & $script -Action Install -CliDirectory $entry
  $value = $key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  if ($value -cne ($baseline + ';' + $entry)) { throw 'Install must preserve original PATH and be idempotent' }
  & $script -Action Remove -CliDirectory $entry
  # Preserve the original raw value, including variable syntax and trailing separators.
  if ($key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne $baseline) { throw 'Remove must preserve original entries' }
  $key.SetValue('Path', $baseline + $entry, $kind)
  & $script -Action Install -CliDirectory $entry
  & $script -Action Remove -CliDirectory $entry
  if ($key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames) -cne ($baseline + ';' + $entry)) { throw 'Preexisting entry must not be removed' }
  Write-Output 'PATH install/remove, idempotency, and ownership checks passed.'
} finally {
  if ($null -eq $original) { $key.DeleteValue('Path', $false) } else { $key.SetValue('Path', $original, $kind) }
  $key.Dispose()
  Remove-ItemProperty -Path 'HKCU:\Software\HanX\CLIPath' -Name $entry -ErrorAction SilentlyContinue
}
