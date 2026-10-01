# 마을 운영 시뮬레이션 - 웹 버전 만들고 Vercel에 올리기
#
# 사용법: PowerShell에서  .\deploy_vercel.ps1
#
# 1) publish_web.ps1 -NoPublish 로 ../build/web/ 에 웹 버전을 만든다 (데이터 검사 + 오픈그래프 이미지 포함).
# 2) ../build/vercel/village-choice/ 로 옮겨 Vercel 프로젝트 "village-choice"에 운영(Production) 배포한다.
#    → https://village-choice.vercel.app/
#
# Vercel CLI는 ../tools/node/ 의 휴대용 Node.js에 깔려 있다. 처음 한 번은 로그인이 필요하다:
#   ..\tools\node\vercel.cmd login   (브라우저에서 승인)

$project = $PSScriptRoot
$repo = [System.IO.Path]::GetFullPath((Join-Path $project ".."))
$node = Join-Path $repo "tools\node"
$vercel = Join-Path $node "vercel.cmd"
$webDir = Join-Path $repo "build\web"
$stageDir = Join-Path $repo "build\vercel\village-choice"   # 폴더 이름이 Vercel 프로젝트 이름이 된다

if (-not (Test-Path $vercel)) {
    Write-Host "Vercel CLI를 찾을 수 없습니다: $vercel" -ForegroundColor Red
    exit 1
}

& (Join-Path $project "publish_web.ps1") -NoPublish
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "[Vercel] 배포 준비" -ForegroundColor Cyan
# .vercel (프로젝트 연결 정보)은 남기고 나머지만 새 파일로 바꾼다
New-Item -ItemType Directory -Force $stageDir | Out-Null
Get-ChildItem $stageDir -Force | Where-Object { $_.Name -ne ".vercel" } | Remove-Item -Recurse -Force
Copy-Item (Join-Path $webDir "*") $stageDir -Recurse

Write-Host "[Vercel] 운영 배포" -ForegroundColor Cyan
$env:Path = "$node;$env:Path"
Push-Location $stageDir
& $vercel deploy --prod --yes
$code = $LASTEXITCODE
Pop-Location
if ($code -ne 0) {
    Write-Host "Vercel 배포에 실패했습니다." -ForegroundColor Red
    exit 1
}
Write-Host "배포 완료: https://village-choice.vercel.app/" -ForegroundColor Green
