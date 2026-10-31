# Called only after an explicit HanX setup option or an unchecked-by-default installer checkbox.
param([Parameter(Mandatory=$true)][switch]$Install)
$ErrorActionPreference='Stop'
if (-not $Install) { throw 'PDF dependency installation requires explicit selection.' }
$winget=Get-Command winget.exe -ErrorAction SilentlyContinue
if (-not $winget) { throw 'Windows 앱 설치 관리자(winget)를 먼저 설치한 뒤 다시 선택하세요: https://aka.ms/getwinget' }
Write-Output '선택한 PDF 도구를 설치합니다: LibreOffice, Poppler. 패키지 관리자가 게시자의 체크섬을 확인합니다.'
# Winget validates the package manifest SHA256 and installs portable Poppler command
# links on the persistent user PATH. It may request approval for its prerequisites.
foreach ($id in @('TheDocumentFoundation.LibreOffice','oschwartz10612.Poppler')) {
  & $winget.Source install --id $id --exact --source winget --accept-package-agreements --accept-source-agreements --disable-interactivity
  if ($LASTEXITCODE -ne 0 -and $LASTEXITCODE -ne -1978335189) { throw "$id 설치를 완료하지 못했습니다 (코드 $LASTEXITCODE). winget에서 해당 패키지를 확인하세요." }
}
Write-Output 'PDF 도구 설치 완료. 새 터미널 또는 HanX 앱을 다시 열면 사용할 수 있습니다.'
