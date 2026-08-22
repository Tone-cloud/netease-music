import QtQuick 2.12
import NeteasePlayer 1.0
import "pages" as Pages
import "components"

Rectangle {
    id: root
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary
    clip: true

    signal backButtonClicked()

    // ── 常量 ──
    property string pluginDir: "/userdisk/PenMods/plugins/netease_music"
    property string serverBin: pluginDir + "/server"
    property string serverUrl: "http://127.0.0.1:8001"

    // ── 全局播放器（C++ 插件提供）──
    NeteasePlayer {
        id: player
        volume: 0.8
        onFinished: {
            if (root.playlist.length > 0) root.playNext()
        }
        onErrorOccurred: function(msg) {
            root.showToast("播放错误: " + msg)
        }
    }

    // ── 页面路由 ──
    property string currentPage: "home"
    property var pageStack: []
    property var pageProps: ({})

    function navigateTo(page, props) {
        pageStack.push({ page: currentPage, props: pageProps })
        currentPage = page
        pageProps = props || ({})
    }

    function goBack() {
        if (pageStack.length > 0) {
            var entry = pageStack.pop()
            currentPage = entry.page
            pageProps = entry.props
        } else {
            backButtonClicked()
        }
    }

    // ── 全局状态 ──
    property var playlist: []
    property int currentIndex: -1
    property var currentSong: null
    property var userInfo: null
    property bool isLoggedIn: false
    property string serverStatus: "启动中..."

    // ── 启动 Go server ──
    function startServer() {
        ApiClient.baseUrl = serverUrl
        player.startServer(serverBin)
        serverStatus = "服务启动中..."
        serverCheckTimer.start()
    }

    Timer {
        id: serverCheckTimer
        interval: 800
        repeat: true
        property int attempts: 0
        onTriggered: {
            attempts++
            ApiClient.ping(function(ok) {
                if (ok) {
                    serverStatus = "已连接"
                    serverCheckTimer.stop()
                    checkLogin()
                }
            })
            if (attempts > 15) {
                serverStatus = "连接超时"
                serverCheckTimer.stop()
            }
        }
    }

    function checkLogin() {
        ApiClient.loginStatus(function(d) {
            if (d.code === 200 && d.data && d.data.profile) {
                isLoggedIn = true
                userInfo = d.data.profile
            }
        }, null)
    }

    // ── 播放控制 ──
    function playSong(song) {
        if (!song || !song.id) return
        currentSong = song
        var exists = -1
        for (var i = 0; i < playlist.length; i++) {
            if (playlist[i].id === song.id) { exists = i; break }
        }
        if (exists >= 0) currentIndex = exists
        else { playlist.push(song); currentIndex = playlist.length - 1 }
        navigateTo("player")
    }

    function playAll(songs) {
        if (!songs || songs.length === 0) return
        playlist = songs
        currentIndex = 0
        currentSong = songs[0]
        navigateTo("player")
    }

    function playNext() {
        if (playlist.length === 0) return
        currentIndex = (currentIndex + 1) % playlist.length
        currentSong = playlist[currentIndex]
    }

    function playPrev() {
        if (playlist.length === 0) return
        currentIndex = (currentIndex - 1 + playlist.length) % playlist.length
        currentSong = playlist[currentIndex]
    }

    function downloadSong(song) {
        if (!song) return
        ApiClient.download(song.id, song.name, song.artist, function(d) {
            showToast(d.code === 200 ? "下载完成" : "下载失败: " + (d.msg || ""))
        }, function(e) { showToast("下载错误: " + e) })
        showToast("开始下载: " + song.name)
    }

    function showToast(msg) {
        toastText.text = msg
        toast.visible = true
        toastTimer.restart()
    }

    // ── Toast ──
    Rectangle {
        id: toast
        anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottomMargin: 55
        width: childrenRect.width + 16; height: 24
        color: "#cc000000"; radius: 12
        visible: false
        Text { id: toastText; anchors.centerIn: parent; color: "white"; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
    }
    Timer { id: toastTimer; interval: 2000; onTriggered: toast.visible = false }

    // ── 服务器状态 ──
    Text {
        anchors.top: parent.top; anchors.right: parent.right
        anchors.margins: 2
        text: serverStatus
        color: serverStatus === "已连接" ? Theme.success : Theme.warning
        font.pixelSize: Theme.fontTiny
        visible: currentPage === "home"
    }

    // ── 页面容器 ──
    StackView {
        id: stack
        anchors.fill: parent
        initialItem: homeComp

        Component {
            id: homeComp
            Pages.HomePage {
                isLoggedIn: root.isLoggedIn
                userName: root.userInfo ? root.userInfo.nickname : ""
                onBackClicked: root.backButtonClicked()
                onOpenPlaylist: function(id) { stack.push(playlistComp, { id: id }) }
                onOpenSearch: stack.push(searchComp)
                onOpenLogin: stack.push(loginComp)
                onOpenUser: stack.push(userComp)
                onOpenToplist: function(idx) { stack.push(playlistComp, { id: "top_" + idx, idx: idx }) }
                onPlaySong: function(song) { root.playSong(song) }
            }
        }

        Component {
            id: searchComp
            Pages.SearchPage {
                onBackClicked: stack.pop()
                onPlaySong: function(song) { root.playSong(song) }
            }
        }

        Component {
            id: playlistComp
            Pages.PlaylistPage {
                onBackClicked: stack.pop()
                onPlaySong: function(song) { root.playSong(song) }
                onPlayAll: function(songs) { root.playAll(songs) }
                onLoaded: function(item) {
                    var props = item.properties || {}
                    if (props.id === "daily") item.load("daily")
                    else if (props.id && props.id.indexOf("top_") === 0) {
                        ApiClient.topListDetail(props.idx, function(d) {
                            if (d.code === 200 && d.playlist) {
                                item.playlistName = d.playlist.name
                                item.parseSongs(d.playlist.tracks || [])
                            }
                        }, null)
                    } else if (props.id) item.load(props.id)
                }
            }
        }

        Component {
            id: playerComp
            Pages.PlayerPage {
                player: root.player
                onBackClicked: stack.pop()
                onPrevSong: root.playPrev()
                onNextSong: root.playNext()
                onDownloadRequested: function(song) { root.downloadSong(song) }
            }
        }

        Component {
            id: loginComp
            Pages.LoginPage {
                onBackClicked: stack.pop()
                onLoginSuccess: function(user) {
                    root.isLoggedIn = true
                    root.userInfo = user
                    root.showToast("登录成功: " + (user.nickname || ""))
                    stack.pop()
                }
            }
        }

        Component {
            id: userComp
            Pages.UserPage {
                userInfo: root.userInfo
                onBackClicked: stack.pop()
                onOpenPlaylist: function(id) { stack.push(playlistComp, { id: id }) }
                onOpenDownloads: stack.push(downloadComp)
                onLogout: function() {
                    ApiClient.logout(function() {
                        root.isLoggedIn = false
                        root.userInfo = null
                        root.showToast("已退出登录")
                        stack.pop()
                    })
                }
            }
        }

        Component {
            id: downloadComp
            Pages.DownloadPage {
                onBackClicked: stack.pop()
                onPlayLocal: function(path, name) {
                    root.player.play(path)
                    root.showToast("正在播放: " + name)
                }
            }
        }
    }

    // currentPage 同步（用于状态显示）
    Binding on currentPage {
        value: stack.currentItem.objectName || "home"
    }

    Component.onCompleted: startServer()
}
