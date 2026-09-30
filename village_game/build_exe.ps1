# 마을 운영 시뮬레이션 - 실행 파일(.exe) 만들기
#
# 사용법: 이 파일을 마우스 오른쪽 버튼 → "PowerShell에서 실행"
#         또는 PowerShell에서  .\build_exe.ps1
#
# 1) 사건 데이터를 검사하고, 오류가 있으면 멈춘다.
# 2) ../build/마을운영.exe 를 만든다. (파일 하나. 설치 없이 더블클릭으로 실행)
#
# Godot은 ../tools/godot 폴더의 휴대용 버전을 쓴다. (설치 불필요)
# 게임이 켜져 있으면 exe를 덮어쓸 수 없으므로 게임을 먼저 닫는다.

$project = $PSScriptRoot
$godot = Join-Path $project "..\tools\godot\Godot_v4.7.2-stable_win64_console.exe"
$outDir = [System.IO.Path]::GetFullPath((Join-Path $project "..\build"))
$outFile = Join-Path $outDir "마을운영.exe"

if (-not (Test-Path $godot)) {
    Write-Host "Godot을 찾을 수 없습니다: $godot" -ForegroundColor Red
    exit 1
}

# 게임이 켜져 있는지 확인 (켜져 있으면 exe 파일이 잠겨 있다)
if (Test-Path $outFile) {
    try {
        $stream = [System.IO.File]::Open($outFile, 'Open', 'ReadWrite', 'None')
        $stream.Close()
    } catch {
        Write-Host "마을운영.exe 가 실행 중입니다. 게임을 닫은 뒤 다시 실행하세요." -ForegroundColor Yellow
        exit 1
    }
}

Write-Host "[1/2] 사건 데이터 검사" -ForegroundColor Cyan
& $godot --headless --path $project --script res://village_sim/tools/validate_data.gd
if ($LASTEXITCODE -ne 0) {
    Write-Host "데이터에 오류가 있어 멈춥니다. 위의 [오류] 줄을 확인하세요." -ForegroundColor Red
    exit 1
}

Write-Host "[2/2] 실행 파일 만들기" -ForegroundColor Cyan
New-Item -ItemType Directory -Force $outDir | Out-Null
Remove-Item (Join-Path $outDir "*.tmp") -ErrorAction SilentlyContinue
& $godot --headless --path $project --export-release "Windows" $outFile
if ($LASTEXITCODE -ne 0 -or -not (Test-Path $outFile)) {
    Write-Host "실행 파일을 만들지 못했습니다." -ForegroundColor Red
    exit 1
}

$size = [math]::Round((Get-Item $outFile).Length / 1MB)
Write-Host "완료: $outFile ($size MB)" -ForegroundColor Green
