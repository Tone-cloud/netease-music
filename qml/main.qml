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
    property string pluginDir: "/userdisk/PenMods/plugins/com.netease.music"
    property string serverBin: pluginDir + "/server"
    property string serverUrl: "http://127.0.0.1:8001"

    // ── 全局播放器 ──
    NeteasePlayer {
        id: player
        volume: 0.8
        onFinished: { if (root.playlist.length > 0) root.playNext() }
        onErrorOccurred: function(msg) { root.showToast("播放错误: " + msg) }
    }

    // ── 页面路由（参考 BiliPocket：独立 Loader + visible 控制）──
    property string currentPage: "home"
    property var pageStack: []
    property bool _animating: false

    // 页面参数（通过 root 属性传递）
    property string playlistId: ""
    property int playlistIdx: 0
    property var currentSong: null
    property var playlist: []
    property int currentIndex: -1
    property var userInfo: null
    property bool isLoggedIn: false
    property string serverStatus: "启动中..."
    property var globalPlayer: player   // 避免与子页面 player 属性命名冲突

    function stackContains(page) {
        for (var i = 0; i < pageStack.length; ++i) {
            if (pageStack[i] && pageStack[i].page === page) return true
        }
        return false
    }

    function navigateTo(page, props) {
        if (_animating) return
        var newStack = pageStack.slice(0)
        newStack.push({ page: currentPage, props: captureProps(currentPage) })
        pageStack = newStack
        applyProps(page, props || {})
        _animating = true
        currentPage = page
        pageTransition.restart()
    }

    function goBack() {
        if (_animating) return
        if (pageStack.length > 0) {
            var newStack = pageStack.slice(0)
            var prev = newStack.pop()
            applyProps(prev.page, prev.props || {})
            _animating = true
            currentPage = prev.page
            pageStack = newStack
            pageTransitionBack.restart()
        } else if (currentPage !== "home") {
            _animating = true
            currentPage = "home"
            pageTransitionBack.restart()
        } else {
            backButtonClicked()
        }
    }

    function captureProps(page) {
        if (page === "playlist") return { id: playlistId, idx: playlistIdx }
        return {}
    }

    function applyProps(page, props) {
        if (!props) return
        if (page === "playlist") {
            playlistId = props.id || ""
            playlistIdx = props.idx || 0
        }
    }

    // ── 页面切换动画（参考 BiliPocket）──
    Item {
        id: pageContainer
        anchors.fill: parent
        opacity: 1
        transform: Translate { id: pageTranslate; x: 0 }

        SequentialAnimation {
            id: pageTransition
            ScriptAction { script: { pageContainer.opacity = 1; pageTranslate.x = 12 } }
            ParallelAnimation {
                NumberAnimation { target: pageContainer; property: "opacity"; from: 0.96; to: 1; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageTranslate; property: "x"; from: 12; to: 0; duration: 150; easing.type: Easing.OutCubic }
            }
            onFinished: root._animating = false
        }

        SequentialAnimation {
            id: pageTransitionBack
            ScriptAction { script: { pageContainer.opacity = 1; pageTranslate.x = -12 } }
            ParallelAnimation {
                NumberAnimation { target: pageContainer; property: "opacity"; from: 0.96; to: 1; duration: 150; easing.type: Easing.OutQuad }
                NumberAnimation { target: pageTranslate; property: "x"; from: -12; to: 0; duration: 150; easing.type: Easing.OutCubic }
            }
            onFinished: root._animating = false
        }

        // ── 首页 ──
        Loader {
            active: true
            visible: currentPage === "home"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.HomePage {
                    isLoggedIn: root.isLoggedIn
                    userName: root.userInfo ? root.userInfo.nickname : ""
                    onBackButtonClicked: root.backButtonClicked()
                    onOpenPlaylist: function(id) { root.navigateTo("playlist", { id: id }) }
                    onOpenSearch: root.navigateTo("search")
                    onOpenLogin: root.navigateTo("user")
                    onOpenUser: root.navigateTo("user")
                    onOpenToplist: function(idx) { root.navigateTo("toplist") }
                    onOpenLocal: root.navigateTo("local")
                    onOpenPersonalFM: root.openPersonalFM()
                    onOpenRecent: root.openRecent()
                    onPlaySong: function(song) { root.playSong(song) }
                }
            }
        }

        // ── 搜索页 ──
        Loader {
            active: currentPage === "search" || root.stackContains("search")
            visible: currentPage === "search"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.SearchPage {
                    onBackClicked: root.goBack()
                    onPlaySong: function(song) { root.playSong(song) }
                }
            }
        }

        // ── 歌单页 ──
        Loader {
            active: currentPage === "playlist" || root.stackContains("playlist")
            visible: currentPage === "playlist"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.PlaylistPage {
                    playlistId: root.playlistId
                    onBackClicked: root.goBack()
                    onPlaySong: function(song) { root.playSong(song) }
                    onPlayAll: function(songs) { root.playAll(songs) }
                    onLoaded: function(item) {
                        var id = root.playlistId
                        if (id === "daily") item.load("daily")
                        else if (id && id.indexOf("top_") === 0) {
                            ApiClient.topListDetail(root.playlistIdx, function(d) {
                                if (d.code === 200 && d.playlist) {
                                    item.playlistName = d.playlist.name
                                    item.parseSongs(d.playlist.tracks || [])
                                }
                            }, null)
                        } else if (id) item.load(id)
                    }
                }
            }
        }

        // ── 排行榜页 ──
        Loader {
            active: currentPage === "toplist" || root.stackContains("toplist")
            visible: currentPage === "toplist"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.ToplistPage {
                    onBackClicked: root.goBack()
                    onOpenPlaylist: function(id) { root.navigateTo("playlist", { id: id }) }
                    onLoaded: function(item) { /* 排行榜数据已内置 */ }
                }
            }
        }

        // ── 播放器页 ──
        Loader {
            active: currentPage === "player"
            visible: currentPage === "player"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.PlayerPage {
            player: root.globalPlayer
                    currentSong: root.currentSong
                    onBackClicked: root.goBack()
                    onPrevSong: root.playPrev()
                    onNextSong: root.playNext()
                    onDownloadRequested: function(song) { root.downloadSong(song) }
                }
            }
        }

        // ── 用户页 ──
        Loader {
            active: currentPage === "user" || root.stackContains("user")
            visible: currentPage === "user"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.UserPage {
                    userInfo: root.userInfo
                    onBackClicked: root.goBack()
                    onOpenLogin: root.navigateTo("login")
                    onOpenPlaylist: function(id) { root.navigateTo("playlist", { id: id }) }
                    onOpenLocal: root.navigateTo("local")
                    onLogout: function() {
                        ApiClient.logout(function() {
                            root.isLoggedIn = false
                            root.userInfo = null
                            root.showToast("已退出登录")
                            root.goBack()
                        })
                    }
                }
            }
        }

        // ── 本地音乐页 ──
        Loader {
            active: currentPage === "local" || root.stackContains("local")
            visible: currentPage === "local"
            anchors.fill: parent
            sourceComponent: Component {
                Pages.LocalMusicPage {
                    onBackClicked: root.goBack()
                    onPlayLocal: function(file) {
                        root.globalPlayer.play(file.path)
                        root.showToast("正在播放: " + file.name)
                    }
                    onLoaded: function(item) { /* 页面自动刷新 */ }
                }
            }
        }
    }

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
            if (d.code === 200 && d.profile) {
                isLoggedIn = true
                userInfo = d.profile
                console.log("[login] 登录成功，开始签到...")
                autoSignin()
            } else {
                console.log("[login] 未登录 code:", d.code)
            }
        }, function(e) {
            console.log("[login] 检查登录状态错误:", e)
        })
    }

    // 自动签到（每天一次，+3经验）
    property string lastSigninDate: ""
    function autoSignin() {
        var now = new Date()
        var today = now.getFullYear() + "-" + (now.getMonth()+1) + "-" + now.getDate()
        if (lastSigninDate === today) {
            console.log("[signin] 今天已签到，跳过")
            return
        }
        lastSigninDate = today
        console.log("[signin] 开始签到...")
        ApiClient.dailySignin(function(d) {
            if (d.code === 200) {
                console.log("[signin] 签到成功 +3经验")
                root.showToast("签到成功 +3经验")
            } else {
                console.log("[signin] 签到结果 code:", d.code, "msg:", d.msg || d.message || "")
            }
        }, function(e) {
            console.log("[signin] 签到失败:", e)
        })
    }

    // ── 私人 FM ──
    function openPersonalFM() {
        console.log("[fm] 加载私人FM...")
        root.showToast("加载私人FM...")
        ApiClient.personalFM(function(d) {
            if (d.code === 200 && d.data && d.data.length > 0) {
                var songs = []
                for (var i = 0; i < d.data.length; i++) {
                    var s = d.data[i]
                    songs.push({
                        id: s.id,
                        name: s.name,
                        artist: s.artists && s.artists.length > 0 ? s.artists[0].name : "",
                        coverImgUrl: s.album ? s.album.picUrl : ""
                    })
                }
                console.log("[fm] 加载到", songs.length, "首歌")
                root.playAll(songs)
            } else {
                console.log("[fm] 加载失败 code:", d.code)
                root.showToast("私人FM加载失败")
            }
        }, function(e) {
            console.log("[fm] 加载错误:", e)
            root.showToast("私人FM加载错误")
        })
    }

    // ── 最近播放 ──
    function openRecent() {
        console.log("[recent] 加载最近播放...")
        root.showToast("加载最近播放...")
        ApiClient.recentSong(100, function(d) {
            if (d.code === 200 && d.data && d.data.list && d.data.list.length > 0) {
                var songs = []
                for (var i = 0; i < Math.min(d.data.list.length, 50); i++) {
                    var s = d.data.list[i].data
                    if (!s) continue
                    songs.push({
                        id: s.id,
                        name: s.name,
                        artist: s.artists && s.artists.length > 0 ? s.artists[0].name : "",
                        coverImgUrl: s.album ? s.album.picUrl : ""
                    })
                }
                console.log("[recent] 加载到", songs.length, "首歌")
                if (songs.length > 0) {
                    root.playAll(songs)
                } else {
                    root.showToast("暂无最近播放记录")
                }
            } else {
                console.log("[recent] 加载失败或为空 code:", d.code)
                root.showToast("最近播放加载失败")
            }
        }, function(e) {
            console.log("[recent] 加载错误:", e)
            root.showToast("最近播放加载错误")
        })
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
        width: toastText.implicitWidth + 16; height: 24
        color: "#cc000000"; radius: 12
        visible: false
        Text { id: toastText; anchors.centerIn: parent; color: "white"; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
    }
    Timer { id: toastTimer; interval: 2000; onTriggered: toast.visible = false }

    // ── 全局错误遮罩（bili风格）──
    property string globalError: ""
    function showError(msg, retryCallback) {
        root.globalError = msg
        root._errorRetryCallback = retryCallback || null
    }
    function clearError() { root.globalError = ""; root._errorRetryCallback = null }
    property var _errorRetryCallback: null

    ErrorOverlay {
        anchors.fill: parent
        errorMessage: root.globalError
        onRetryClicked: {
            var cb = root._errorRetryCallback
            root.clearError()
            if (cb) cb()
        }
        onDismissed: root.clearError()
    }

    Component.onCompleted: startServer()
}
