# 打包脚本 - 生成 netease_music_v3.zip
# 注意：libnetease_player.so 需要从 GitHub Actions 下载后放入插件目录

$ErrorActionPreference = "Stop"
$root = "C:\Users\aresi\Desktop\cc\netease_music_v3"
$out = "C:\Users\aresi\Desktop\cc\netease_music_v3.zip"

if (Test-Path $out) { Remove-Item $out -Force }

# 打包运行时文件
$files = @(
    "$root\metadata.json",
    "$root\server",
    "$root\icon.png",
    "$root\README.md"
)

# 检查 libnetease_player.so 是否存在
$soFile = "$root\plugin\build\libnetease_player.so"
if (Test-Path $soFile) {
    Copy-Item $soFile "$root\libnetease_player.so" -Force
    $files += "$root\libnetease_player.so"
    Write-Host "已包含 libnetease_player.so"
} else {
    Write-Host "警告: libnetease_player.so 不存在，请从 GitHub Actions 下载后放入插件目录"
    Write-Host "打包将不包含 .so 文件"
}

# 打包
Compress-Archive -Path $files -DestinationPath $out -Force
# 追加 qml 目录
Compress-Archive -Path "$root\qml" -DestinationPath $out -Update

$size = (Get-Item $out).Length / 1MB
Write-Host "打包完成: $out ($([math]::Round($size, 2)) MB)"
