param(
  [Parameter(Mandatory=$true)][ValidateSet('Install','Remove')][string]$Action,
  [Parameter(Mandatory=$true)][string]$CliDirectory
)
$ErrorActionPreference = 'Stop'
$entry = [IO.Path]::GetFullPath($CliDirectory).TrimEnd('\')
if ($entry.Contains(';')) { throw 'PATH entries cannot contain semicolons.' }
$state = 'HKCU:\Software\HanX\CLIPath'
# Read the raw user PATH: never expand variables or replace it with the process PATH.
$key = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Environment')
try {
  $raw = [string]$key.GetValue('Path', '', [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
  $kind = if ($key.GetValueNames() -contains 'Path') { $key.GetValueKind('Path') } else { [Microsoft.Win32.RegistryValueKind]::ExpandString }
  $parts = @($raw -split ';')
  $matches = @($parts | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ieq $entry })
  if ($Action -eq 'Install') {
    if ($matches.Count -eq 0) {
      $updated = if ($raw.Length -eq 0) { $entry } else { $raw + ';' + $entry }
      $key.SetValue('Path', $updated, $kind)
      New-Item -Path $state -Force | Out-Null
      New-ItemProperty -Path $state -Name $entry -Value 1 -PropertyType DWord -Force | Out-Null
    }
  } else {
    $owned = Get-ItemPropertyValue -Path $state -Name $entry -ErrorAction SilentlyContinue
    if ($owned -eq 1) {
      $updated = ($parts | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ine $entry }) -join ';'
      $key.SetValue('Path', $updated, $kind)
      Remove-ItemProperty -Path $state -Name $entry -ErrorAction SilentlyContinue
    }
  }
} finally { $key.Dispose() }
if (-not ('HanXEnvironment' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class HanXEnvironment {
  [DllImport("user32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
  public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint msg, UIntPtr wParam, string lParam, uint flags, uint timeout, out UIntPtr result);
}
'@
}
$result = [UIntPtr]::Zero
[void][HanXEnvironment]::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result)
