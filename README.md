# 网易云音乐 - 词典笔插件 v1.00

为有道词典笔（YDP02x，PenMods 框架）开发的网易云音乐第三方客户端。

## 架构

```
┌─────────────────────────────────────────────┐
│                   QML 前端                    │
│  (首页/搜索/歌单/播放器/用户/下载)            │
├─────────────────────────────────────────────┤
│  libnetease_player.so (C++ QML 插件)         │
│  调用词典笔系统播放器播放                      │
│  自动 chmod +x 启动 server                   │
│  系统播放器状态轮询（自动切歌）                │
├─────────────────────────────────────────────┤
│  server (Go, linux/arm64)                    │
│  网易云 weapi 加密代理 / 登录态 / 下载 / 缓存  │
│  主服务: 127.0.0.1:8002                      │
│  登录服务: 0.0.0.0:8667 (外部浏览器访问)      │
└─────────────────────────────────────────────┘
```

## 功能

### 核心功能
- ✅ **极简登录** — 只需粘贴 `MUSIC_U` 一个值，无需二维码/手机验证
- ✅ 搜索歌曲/歌手
- ✅ 推荐歌单 / 排行榜（热门/欧美/ACG/民谣/韩语）/ 每日推荐
- ✅ **私人 FM** — 自动连播，无歌单列表，一首接一首
- ✅ 歌单详情 / 播放全部
- ✅ 系统播放器播放（调用词典笔自带音乐播放器）
- ✅ 歌词同步显示
- ✅ 播放控制（上一首/下一首/自动切歌）
- ✅ **歌曲缓存** — 播放前自动下载到本地，支持离线播放
- ✅ **批量下载** — 一键下载整个歌单
- ✅ 单首下载 / 下载管理 / 本地播放
- ✅ 个人中心 / 我的歌单 / 退出登录
- ✅ 搜索历史持久化
- ✅ 每日签到

## 安装

### 1. 获取插件包

从 Releases 下载 `com.netease.music.zip`，或自行编译：
- Go server：本地交叉编译（见下方编译说明）
- C++ 插件 `libnetease_player.so`：推送代码到 GitHub，Actions 自动编译后下载

### 2. 安装插件

将解压后的文件放到 `/userdisk/PenMods/plugins/com.netease.music/`：

```
com.netease.music/
├── metadata.json
├── libnetease_player.so    ← GitHub Actions 编译产物
├── server                   ← Go server（已预编译）
├── icon.png
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
        └── UserPage.qml
```

3. 在 PenMods 插件管理中启用「网易云音乐」
4. 重启词典笔
5. 打开插件，首页显示「已连接」表示 server 正常

### 3. 登录

1. 在电脑浏览器访问 `http://词典笔IP:8667/verify.html`
2. 在浏览器中打开 Cookie-Editor 扩展
3. 找到网易云音乐域名下的 `MUSIC_U`，复制值并粘贴到登录页
4. 登录成功后插件自动识别

> 登录服务监听 `0.0.0.0:8667`，允许外部浏览器访问；主 API 服务监听 `127.0.0.1:8002`，更安全。

## 编译说明

### Go server

```bash
cd go_server
GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -ldflags="-s -w" -trimpath -o ../server .
```

### C++ 播放器插件

依赖：
- Qt 5.15.2 for aarch64（词典笔专用）
- aarch64-dictpen-linux-gnu-gcc 工具链

参考 `.github/workflows/build.yml`，推送代码到 `main` 分支后 GitHub Actions 自动编译，在 Actions 页面下载 `libnetease_player.so`。

## 故障排查

### 插件打不开 / server 启动失败
- 插件启动时会自动执行 `chmod +x server`，无需手动操作
- 如仍失败，手动执行：`chmod +x /userdisk/PenMods/plugins/com.netease.music/server`
- 确认 .so 是 linux/arm64 架构（用 `file` 命令检查）

### 无法播放歌曲
- 部分歌曲需要 VIP 权限，会提示「无法播放（可能需要 VIP）」
- 确认已登录（MUSIC_U 有效）
- 检查网络连接

### 登录页面打不开
- 确认电脑和词典笔在同一 WiFi 网络
- 访问地址：`http://词典笔IP:8667/verify.html`
- 登录服务独立运行，不依赖主 server

### 下载失败
- 批量下载进度显示在歌单页面顶部
- 已下载的歌曲保存在 `/userdisk/Music/netease/`
- 缓存文件保存在 `/userdisk/Music/netease/cache/`

## API 接口（Go server）

| 路径 | 方法 | 说明 |
|------|------|------|
| `/ping` | GET | 健康检查 |
| `/search?keywords=xxx` | GET | 搜索 |
| `/song/url?id=xxx` | GET | 获取播放地址 |
| `/lyric?id=xxx` | GET | 歌词 |
| `/playlist/detail?id=xxx` | GET | 歌单详情 |
| `/recommend/resource` | GET | 推荐歌单 |
| `/recommend/songs` | GET | 每日推荐 |
| `/toplist` | GET | 排行榜列表 |
| `/top/list?idx=0` | GET | 排行榜详情 |
| `/personal_fm` | GET | 私人 FM |
| `/login/status` | GET | 当前登录状态 |
| `/logout` | GET | 退出登录 |
| `/user/playlist?uid=xxx` | GET | 用户歌单 |
| `/cache?url=xxx` | GET | 缓存歌曲到本地 |
| `/download?id=xxx&name=xxx` | GET | 单首下载 |
| `/downloads` | GET | 下载列表 |
| `/download/batch/start` | POST | 批量下载开始 |
| `/download/batch/status` | GET | 批量下载进度 |
| `/download/batch/cancel` | POST | 取消批量下载 |
| `/search/history` | GET/POST | 搜索历史 |
| `/local/list` | GET | 本地歌曲列表 |
| `/local/delete` | POST | 删除本地歌曲 |
| `/login` | GET | 极简登录页（浏览器访问） |
| `/cookies/import` | POST | 导入 MUSIC_U 登录 |

## 技术栈

- **C++ 插件**：Qt 5.15，符号解析调用词典笔系统播放器 API，自动启动 Go server
- **Go server**：Go 1.22，标准库 net/http，网易云 weapi 加密（AES-128-CBC + RSA）
- **QML 前端**：QtQuick 2.12，320x170 触摸屏适配
- **编译**：qmake + GitHub Actions 交叉编译（C++），本地交叉编译（Go）

## License

GPL-3.0
