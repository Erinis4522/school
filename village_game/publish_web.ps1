# 마을 운영 시뮬레이션 - 웹 버전 만들고 GitHub Pages에 올리기
#
# 사용법: PowerShell에서  .\publish_web.ps1
#         (올리지 않고 만들기만:  .\publish_web.ps1 -NoPublish)
#
# 1) 사건 데이터를 검사하고, 오류가 있으면 멈춘다.
# 2) ../build/web/ 에 웹 버전을 만든다.
# 3) 그 파일들을 gh-pages 브랜치에 올린다. → https://<아이디>.github.io/<저장소>/ 에서 플레이
#
# 처음 한 번은 GitHub 저장소 Settings → Pages 에서
# Source: "Deploy from a branch", Branch: "gh-pages" / "(root)" 로 설정해야 한다.

param(
    [switch]$NoPublish,
    [string]$Message = "웹 버전 업데이트"
)

$project = $PSScriptRoot
$repo = [System.IO.Path]::GetFullPath((Join-Path $project ".."))
$godot = Join-Path $repo "tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$webDir = Join-Path $repo "build\web"
$pagesDir = Join-Path $repo "build\gh-pages"

$git = (Get-Command git -ErrorAction SilentlyContinue).Source
if (-not $git) { $git = "C:\Program Files\Git\cmd\git.exe" }

if (-not (Test-Path $godot)) {
    Write-Host "Godot을 찾을 수 없습니다: $godot" -ForegroundColor Red
    exit 1
}

Write-Host "[1/3] 사건 데이터 검사" -ForegroundColor Cyan
& $godot --headless --path $project --script res://village_sim/tools/validate_data.gd
if ($LASTEXITCODE -ne 0) {
    Write-Host "데이터에 오류가 있어 멈춥니다. 위의 [오류] 줄을 확인하세요." -ForegroundColor Red
    exit 1
}

Write-Host "[2/3] 웹 버전 만들기" -ForegroundColor Cyan
if (Test-Path $webDir) { Remove-Item $webDir -Recurse -Force }
New-Item -ItemType Directory -Force $webDir | Out-Null
& $godot --headless --path $project --export-release "Web" (Join-Path $webDir "index.html")
if ($LASTEXITCODE -ne 0 -or -not (Test-Path (Join-Path $webDir "index.html"))) {
    Write-Host "웹 버전을 만들지 못했습니다." -ForegroundColor Red
    exit 1
}
Write-Host "완료: $webDir" -ForegroundColor Green

if ($NoPublish) { exit 0 }

Write-Host "[3/3] GitHub Pages(gh-pages 브랜치)에 올리기" -ForegroundColor Cyan
& $git -C $repo worktree prune
if (-not (Test-Path (Join-Path $pagesDir ".git"))) {
    & $git -C $repo ls-remote --exit-code --heads origin gh-pages | Out-Null
    $remoteExists = ($LASTEXITCODE -eq 0)
    & $git -C $repo show-ref --verify --quiet refs/heads/gh-pages
    $localExists = ($LASTEXITCODE -eq 0)
    if ($localExists) {
        & $git -C $repo worktree add $pagesDir gh-pages
    } elseif ($remoteExists) {
        & $git -C $repo fetch origin gh-pages
        & $git -C $repo worktree add -B gh-pages $pagesDir origin/gh-pages
    } else {
        & $git -C $repo worktree add --orphan -b gh-pages $pagesDir
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "gh-pages 작업 폴더를 준비하지 못했습니다." -ForegroundColor Red
        exit 1
    }
}

# 예전 파일을 지우고 새 웹 버전으로 바꾼다
Get-ChildItem $pagesDir -Force | Where-Object { $_.Name -ne ".git" } | Remove-Item -Recurse -Force
Copy-Item (Join-Path $webDir "*") $pagesDir -Recurse
New-Item -ItemType File (Join-Path $pagesDir ".nojekyll") -Force | Out-Null

& $git -C $pagesDir add -A
& $git -C $pagesDir diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    Write-Host "바뀐 내용이 없어 올리지 않습니다." -ForegroundColor Yellow
    exit 0
}
& $git -C $pagesDir commit -q -m $Message
& $git -C $pagesDir push -u origin gh-pages
if ($LASTEXITCODE -ne 0) {
    Write-Host "올리지 못했습니다. 인터넷 연결과 GitHub 로그인을 확인하세요." -ForegroundColor Red
    exit 1
}

$remote = & $git -C $repo remote get-url origin
if ($remote -match "github\.com[:/]([^/]+)/([^/.]+)") {
    $url = "https://$($Matches[1].ToLower()).github.io/$($Matches[2])/"
    Write-Host "올리기 완료. 몇 분 뒤 이 주소에서 플레이할 수 있습니다: $url" -ForegroundColor Green
} else {
    Write-Host "올리기 완료." -ForegroundColor Green
}
