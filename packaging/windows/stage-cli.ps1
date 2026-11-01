param([string]$Binary = '.build/release/hanx.exe', [string[]]$RuntimeDirectories = @())
$ErrorActionPreference = 'Stop'
$destination = Join-Path $PWD 'build/platform/cli'
if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
New-Item -ItemType Directory -Path $destination -Force | Out-Null
Copy-Item -LiteralPath $Binary -Destination (Join-Path $destination 'hanx.exe')
Set-Content -LiteralPath (Join-Path $destination 'hanx-cli.cmd') -Encoding Ascii -Value '@echo off', '"%~dp0hanx.exe" %*'
$target = (& swift -print-target-info | ConvertFrom-Json)
if ($LASTEXITCODE -ne 0) { throw 'swift -print-target-info failed' }
$directories = @($RuntimeDirectories) + @($target.paths.runtimeLibraryPaths) + @((Split-Path (Get-Command swift).Source)) + @($env:Path -split ';' | Where-Object { $_ -match 'Swift' })
# Follow actual PE imports so compiler/debugger DLLs are not shipped.
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$vs = & $vswhere -latest -products '*' -property installationPath
# App-local VC redistributables make the engine independent of installed VS.
$crtDirectories = @(Get-ChildItem "$vs\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory | Sort-Object FullName -Descending | Select-Object -ExpandProperty FullName)
if ($crtDirectories.Count -eq 0) { throw 'MSVC app-local redistributables are missing' }
$directories = $crtDirectories + $directories
$dumpbin = Get-Command dumpbin.exe -ErrorAction SilentlyContinue
if ($dumpbin) { $dumpbinPath = $dumpbin.Source } else {
  $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
  $vs = & $vswhere -latest -products '*' -property installationPath
  $dumpbinPath = Get-ChildItem "$vs\VC\Tools\MSVC\*\bin\Hostx64\x64\dumpbin.exe" | Sort-Object FullName -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $dumpbinPath) { throw 'Visual Studio dumpbin is required for runtime dependency staging' }
# Swift release DLLs can live beside either the compiler or runtime libraries.
$directories += @($env:Path -split ';')
$queue = [System.Collections.Generic.Queue[string]]::new()
$queue.Enqueue((Join-Path $destination 'hanx.exe'))
$seen = @{}
while ($queue.Count -gt 0) {
  $file = $queue.Dequeue()
  $imports = & $dumpbinPath /NOLOGO /DEPENDENTS $file
  if ($LASTEXITCODE -ne 0) { throw "Cannot inspect runtime dependencies: $file" }
  foreach ($line in $imports) {
    if ($line -match '^\s+([A-Za-z0-9_.+-]+\.dll)\s*$') {
      $name = $matches[1]
      if ($seen.ContainsKey($name.ToLowerInvariant())) { continue }
      $seen[$name.ToLowerInvariant()] = $true
      $source = $null
      foreach ($directory in ($directories | Select-Object -Unique)) {
        if (-not $directory) { continue }
        $candidate = Join-Path $directory $name
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $source = $candidate; break }
      }
      if ($source -and -not $source.StartsWith($env:SystemRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $targetFile = Join-Path $destination $name
        Copy-Item -LiteralPath $source -Destination $targetFile
        $queue.Enqueue($targetFile)
      } elseif (-not $source -and $name -notmatch '^(api-ms-|ext-ms-)') {
        throw "Unresolved runtime dependency $name (required by $file)"
      }
    }
  }
}
if (-not (Test-Path (Join-Path $destination 'swiftCore.dll'))) { throw 'Swift runtime DLLs missing; pass -RuntimeDirectories with Swift runtime bin directories.' }
Copy-Item LICENSE, NOTICE -Destination $destination
Copy-Item 'docs/cli/README.md' -Destination (Join-Path $destination 'README.md')
Copy-Item 'docs/cli/examples' -Destination (Join-Path $destination 'examples') -Recurse
$licenses = Join-Path $destination 'third-party-licenses'
New-Item -ItemType Directory -Path $licenses -Force | Out-Null
Copy-Item 'Sources/CMiniz/LICENSE' -Destination (Join-Path $licenses 'miniz.txt')
'Microsoft Visual C++ Runtime redistributable files from Visual Studio 2022 VC/Redist/MSVC. Official redistributable: https://aka.ms/vs/17/release/vc_redist.x64.exe' | Set-Content (Join-Path $licenses 'msvc-runtime-source.txt')
$notices = @(
  @('swift', 'LICENSE.txt'), @('swift-foundation', 'LICENSE.md'),
  @('swift-foundation', 'NOTICE.txt'), @('swift-foundation-icu', 'LICENSE.md'),
  @('swift-corelibs-foundation', 'LICENSE'), @('swift-corelibs-libdispatch', 'LICENSE')
)
foreach ($notice in $notices) {
  $repository, $filename = $notice
  $url = "https://raw.githubusercontent.com/swiftlang/$repository/swift-6.2.1-RELEASE/$filename"
  Invoke-WebRequest -Uri $url -OutFile (Join-Path $licenses "$repository-$filename")
}
# FoundationXML/Networking use these permissively licensed runtime libraries.
$dependencyNotices = @(
  @('libxml2', 'https://raw.githubusercontent.com/GNOME/libxml2/v2.14.5/Copyright'),
  @('curl', 'https://raw.githubusercontent.com/curl/curl/curl-8_14_1/COPYING'),
  @('zlib', 'https://raw.githubusercontent.com/madler/zlib/v1.3.1/LICENSE')
)
foreach ($notice in $dependencyNotices) {
  Invoke-WebRequest -Uri $notice[1] -OutFile (Join-Path $licenses ($notice[0] + '.txt'))
}

# Validate without the developer toolchain on PATH: bundled runtime must suffice.
$savedPath = $env:Path
try {
  $env:Path = "$env:SystemRoot\System32;$env:SystemRoot"
  & (Join-Path $destination 'hanx.exe') --version
  if ($LASTEXITCODE -ne 0) { throw 'Staged CLI needs missing runtime DLLs' }
  $aliasVersion = (& (Join-Path $destination 'hanx-cli.cmd') --version | ConvertFrom-Json)
  if ($LASTEXITCODE -ne 0 -or $aliasVersion.data.version -ne '2.9.1') { throw 'Staged hanx-cli alias failed without developer tools' }
} finally { $env:Path = $savedPath }
