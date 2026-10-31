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
      $ownership = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey('Software\HanX\CLIPath')
      try { $ownership.SetValue($entry, 1, [Microsoft.Win32.RegistryValueKind]::DWord) } finally { $ownership.Dispose() }
    }
  } else {
    # An absent ownership value means this entry belongs to somebody else.
    $ownership = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Software\HanX\CLIPath', $true)
    $owned = if ($null -ne $ownership) { $ownership.GetValue($entry, $null) } else { $null }
    if ($owned -eq 1) {
      $updated = ($parts | Where-Object { $_.Trim().Trim('"').TrimEnd('\') -ine $entry }) -join ';'
      $key.SetValue('Path', $updated, $kind)
      $ownership.DeleteValue($entry, $false)
    }
    if ($null -ne $ownership) { $ownership.Dispose() }
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
