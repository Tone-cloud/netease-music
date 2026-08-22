$env:GOOS = "linux"
$env:GOARCH = "arm64"
$env:CGO_ENABLED = "0"
Set-Location "C:\Users\aresi\Desktop\cc\netease_music_v3\go_server"
& "C:\Users\aresi\go-sdk\go\bin\go.exe" build -ldflags="-s -w" -trimpath -o "..\server" .
Write-Host "Exit code: $LASTEXITCODE"
