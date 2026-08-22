# 网易云音乐 - 词典笔插件 v3.0

为有道词典笔（YDP02x，PenMods）开发的网易云音乐客户端。

## 架构

```
┌─────────────────────────────────────────────┐
│                   QML 前端                    │
│  (7个页面: 首页/搜索/歌单/播放器/登录/用户/下载) │
├─────────────────────────────────────────────┤
│  libnetease_player.so (C++ QML 插件)         │
│  FFmpeg 解码 + QAudioOutput 播放              │
│  NeteasePlayer QML 类型                       │
├─────────────────────────────────────────────┤
│  server (Go, linux/arm64)                    │
│  网易云 weapi 加密代理 / 登录态 / 下载 / 缓存    │
│  监听 127.0.0.1:8001                         │
└─────────────────────────────────────────────┘
```

**与 v2.x 的区别**：
- v2.x 用 `shell.execAsync` 调命令行播放器（mpg123/mpv），依赖 shell 插件
- v3.x 用独立 C++ 插件 `libnetease_player.so`，FFmpeg 解码 + QAudioOutput 直接输出，不依赖 shell
- 支持直接播放 HTTP URL（FFmpeg 网络协议），无需先缓存到本地

## 功能

- ✅ 二维码扫码登录
- ✅ 搜索歌曲/歌手
- ✅ 推荐歌单 / 排行榜 / 每日推荐
- ✅ 歌单详情 / 播放全部
- ✅ 在线播放（FFmpeg 直接播 HTTP 流）
- ✅ 歌词同步显示
- ✅ 播放控制（播放/暂停/停止/上一首/下一首/进度拖动）
- ✅ 歌曲下载到本地
- ✅ 下载管理 / 本地播放
- ✅ 个人中心 / 我的歌单 / 退出登录

## 安装

### 1. 编译 C++ 播放器插件

`libnetease_player.so` 需要交叉编译为 linux/arm64。推荐用 GitHub Actions：

1. Fork 本仓库到你的 GitHub
2. 推送代码到 `main` 分支
3. GitHub Actions 会自动编译，在 Actions 页面下载 `libnetease_player.so`

或者参考 `.github/workflows/build.yml` 在本地 Linux 环境编译。

### 2. 打包安装

将以下文件放到 `/userdisk/PenMods/plugins/netease_music/`：

```
netease_music/
├── metadata.json
├── libnetease_player.so    ← GitHub Actions 编译产物
├── server                   ← Go server（已预编译）
├── icon.png
├── README.md
└── qml/
    ├── main.qml
    ├── components/
    │   ├── Theme.qml
    │   └── ApiClient.qml
    └── pages/
        ├── HomePage.qml
        ├── SearchPage.qml
        ├── PlaylistPage.qml
        ├── PlayerPage.qml
        ├── LoginPage.qml
        ├── UserPage.qml
        └── DownloadPage.qml
```

3. 在 PenMods 插件管理中启用「网易云音乐」
4. 重启词典笔
5. 打开插件，首页右上角显示「已连接」表示 server 正常

## 编译说明

### Go server（已预编译）

```bash
cd go_server
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o ../server .
```

### C++ 播放器插件（需要交叉编译）

依赖：
- Qt 5.15.2 for aarch64（词典笔专用）
- aarch64-dictpen-linux-gnu-gcc 工具链
- FFmpeg 库（dictpen-libs）

参考 `.github/workflows/build.yml`，用 GitHub Actions 自动编译。

## 故障排查

### 插件打不开
- 确认 `libnetease_player.so` 已放到插件目录
- 确认 `metadata.json` 中 `main_so` 字段为 `libnetease_player.so`
- 确认 .so 是 linux/arm64 架构（用 `file` 命令检查）

### 没有声音
- 确认词典笔音量已打开
- C++ 插件用 QAudioOutput 直接输出到 ALSA，不依赖系统播放器
- 检查 `/dev/snd/` 设备是否存在

### 播放失败（VIP 歌曲）
- 网易云部分歌曲需要 VIP 才能播放，server 会返回「无法获取播放地址」
- 已下载的歌曲可以在下载管理中本地播放

### server 连接超时
- server 由插件启动时自动拉起（`player.startServer()`）
- 手动测试：`./server` 然后 `wget http://127.0.0.1:8001/ping`
- 确认 server 有执行权限：`chmod +x server`

## API 接口（Go server）

| 路径 | 说明 |
|------|------|
| `/ping` | 健康检查 |
| `/search?keywords=xxx` | 搜索 |
| `/song/url?id=xxx` | 获取播放地址 |
| `/lyric?id=xxx` | 歌词 |
| `/playlist/detail?id=xxx` | 歌单详情 |
| `/recommend/resource` | 推荐歌单 |
| `/recommend/songs` | 每日推荐 |
| `/toplist` | 排行榜列表 |
| `/top/list?idx=0` | 排行榜详情 |
| `/login/qr/key` | 二维码登录 key |
| `/login/qr/create?key=xxx` | 生成二维码 |
| `/login/qr/check?key=xxx` | 检查登录状态 |
| `/login/status` | 当前登录状态 |
| `/logout` | 退出登录 |
| `/user/playlist?uid=xxx` | 用户歌单 |
| `/cache?id=xxx&name=xxx` | 缓存到本地 |
| `/download?id=xxx&name=xxx` | 下载歌曲 |
| `/downloads` | 下载列表 |

## 技术栈

- **C++ 播放器**：Qt 5.15 + FFmpeg (libavformat/libavcodec/libswresample) + QAudioOutput (ALSA)
- **Go server**：Go 1.22，标准库 net/http，网易云 weapi 加密（AES-128-CBC + RSA）
- **QML 前端**：QtQuick 2.12，320x170 触摸屏适配
- **编译**：qmake + GitHub Actions 交叉编译

## License

GPL-3.0
