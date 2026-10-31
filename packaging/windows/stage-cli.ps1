param([string]$Binary = '.build/release/hanx.exe', [string[]]$RuntimeDirectories = @())
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PWD 'build/platform/cli'
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath $Binary -Destination (Join-Path $destination 'hanx.exe')
$target = (& swift -print-target-info | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'swift -print-target-info failed' }
$directories = @($RuntimeDirectories) + @($target.paths.runtimeLibraryPaths) + @((Split-Path (Get-Command swift).Source)) + @($env:Path -split ';' | Where-Object { $_ -match 'Swift' })
foreach ($directory in ($directories | Select-Object -Unique)) {
  if (Test-Path -LiteralPath $directory) {
    Get-ChildItem -LiteralPath $directory -Filter '*.dll' -File | Copy-Item -Destination $destination
  }
}
if (-not (Test-Path (Join-Path $destination 'swiftCore.dll'))) { throw 'Swift runtime DLLs missing; pass -RuntimeDirectories with Swift runtime bin directories.' }
Copy-Item LICENSE, NOTICE -Destination $destination
# Validate without the developer toolchain on PATH: bundled runtime must suffice.
$savedPath = $env:Path
try {
  $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
  & (Join-Path $destination 'hanx.exe') --version
  if ($LASTEXITCODE -ne 0) { throw 'Staged CLI needs missing runtime DLLs' }
} finally { $env:Path = $savedPath }
