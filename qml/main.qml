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
    property string serverUrl: "http://127.0.0.1:8002"

    // ── 全局播放器 ──
    NeteasePlayer {
        id: player
        onFinished: { if (root.playlist.length > 0) root.playNext() }
        onErrorOccurred: function(msg) { root.showToast("播放错误: " + msg) }
    }

    // ── 页面路由（参考 BiliPocket：独立 Loader + visible 控制）──
    property string currentPage: "home"
    property var pageStack: []
    property bool _animating: false
    property bool serverStarting: false
    property bool loginCheckInProgress: false
    property var pageStateCache: ({})

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
    property bool transferBusy: false
    property real transferProgress: 0
    property string transferLabel: ""
    property string transferFileName: ""
    property string searchKeyword: ""
    property var downloadedIds: []
    property var downloadedPaths: ({})
    property var downloadedPathsByName: ({})

    function stackContains(page) {
        for (var i = 0; i < pageStack.length; ++i) {
            if (pageStack[i] && pageStack[i].page === page) return true
        }
        return false
    }

    function savePageState(page, state) {
        if (!page) return
        if (!pageStateCache[page]) pageStateCache[page] = {}
        var target = pageStateCache[page]
        for (var key in state) {
            target[key] = state[key]
        }
    }

    function capturePageState(page) {
        var state = {}
        if (page === "playlist") {
            state.playlistId = playlistId
            state.playlistIdx = playlistIdx
        }
        if (page === "player") {
            state.currentSong = currentSong
            state.playlist = playlist
            state.currentIndex = currentIndex
        }
        return state
    }

    function restorePageState(page) {
        var state = pageStateCache[page] || {}
        if (page === "playlist") {
            if (state.playlistId !== undefined) playlistId = state.playlistId
            if (state.playlistIdx !== undefined) playlistIdx = state.playlistIdx
        }
        if (page === "player") {
            if (state.currentSong !== undefined) currentSong = state.currentSong
            if (state.playlist !== undefined) playlist = state.playlist
            if (state.currentIndex !== undefined) currentIndex = state.currentIndex
        }
    }

    function navigateTo(page, props) {
        if (_animating) return
        var newStack = pageStack.slice(0)
        savePageState(currentPage, capturePageState(currentPage))
        newStack.push({ page: currentPage, props: captureProps(currentPage) })
        pageStack = newStack
        applyProps(page, props || {})
        if (!props || Object.keys(props).length === 0) restorePageState(page)
        _animating = true
        currentPage = page
        pageTransition.restart()
    }

    function goBack() {
        if (_animating) return
        if (pageStack.length > 0) {
            var newStack = pageStack.slice(0)
            var prev = newStack.pop()
            var prevPage = prev && prev.page ? prev.page : currentPage
            savePageState(currentPage, capturePageState(currentPage))
            if (prev && prev.props) applyProps(prevPage, prev.props)
            restorePageState(prevPage)
            _animating = true
            currentPage = prevPage
            pageStack = newStack
            pageTransitionBack.restart()
        } else if (currentPage !== "home") {
            savePageState(currentPage, capturePageState(currentPage))
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
                    onOpenSearchWithKeyword: function(kw) { root.searchKeyword = kw; root.navigateTo("search") }
                    onOpenLogin: root.navigateTo("user")
                    onOpenUser: root.navigateTo("user")
                    onOpenToplist: function(idx) { root.navigateTo("toplist") }
                    onOpenLocal: root.navigateTo("local")
                    onOpenPersonalFM: root.openPersonalFM()
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
                    onPlaySong: function(song, contextSongs) { root.playSong(song, contextSongs) }
                    onPlayAll: function(songs) { root.playAll(songs) }
                    // 修复：每次 playlistId 变化时重新加载（不仅是第一次）
                    onPlaylistIdChanged: {
                        var id = root.playlistId
                        if (!id) return
                        if (item) item.load(id)
                    }
                    onLoaded: function(item) {
                        if (root.playlistId) item.load(root.playlistId)
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
                    onOpenPlaylist: function(id, index) { root.navigateTo("playlist", { id: "top_" + id, idx: id }) }
                    onLoaded: function(item) { }
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
                    id: playerPage
                    player: root.globalPlayer
                    currentSong: root.currentSong
                    playlist: root.playlist
                    currentIndex: root.currentIndex
                    onBackClicked: root.goBack()
                    onPrevSong: {
                        if (playerPage.playState === "playing") playerPage.autoPlayNext = true
                        root.playPrev()
                    }
                    onNextSong: {
                        // 正在播放时按下一首，切过去后继续播放
                        if (playerPage.playState === "playing") playerPage.autoPlayNext = true
                        root.playNext()
                    }
                    onAutoNext: {
                        if (!root.playNextDownloaded()) {
                            playerPage.autoPlayNext = false
                            playerPage.setPlayState("idle", "本歌单已播放完毕")
                        }
                    }
                    onDownloadRequested: function(song, withLyrics) { root.downloadSong(song, withLyrics) }
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
        if (serverStarting) return
        serverStarting = true
        ApiClient.baseUrl = serverUrl
        player.startServer(serverBin)
        serverStatus = "服务启动中..."
        serverCheckTimer.attempts = 0
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
                    serverStarting = false
                    checkLogin()
                }
            })
            if (attempts > 20) {
                serverStatus = "连接超时"
                serverCheckTimer.stop()
                serverStarting = false
            }
        }
    }

    function loadDownloadedIds() {
        ApiClient.downloadList(function(d) {
            if (d && d.code === 200 && d.files) {
                var ids = []
                var paths = ({})
                var pathsByName = ({})
                for (var i = 0; i < d.files.length; i++) {
                    if (d.files[i].name && d.files[i].path) {
                        pathsByName[String(d.files[i].name).trim().toLowerCase()] = d.files[i].path
                    }
                    if (d.files[i].id) {
                        ids.push(d.files[i].id)
                        paths[String(d.files[i].id)] = d.files[i].path
                    }
                }
                root.downloadedIds = ids
                root.downloadedPaths = paths
                root.downloadedPathsByName = pathsByName
                console.log("[download] 已加载", ids.length, "首已下载歌曲")
            }
        }, function(e) { console.log("[download] 加载已下载列表失败:", e) })
    }

    function checkLogin() {
        if (loginCheckInProgress) return
        loginCheckInProgress = true
        ApiClient.loginStatus(function(d) {
            loginCheckInProgress = false
            if (d.code === 200 && d.profile) {
                isLoggedIn = true
                userInfo = d.profile
                console.log("[login] 登录成功，开始签到...")
                autoSignin()
                loadDownloadedIds()
            } else {
                isLoggedIn = false
                userInfo = null
                console.log("[login] 未登录 code:", d.code)
            }
        }, function(e) {
            loginCheckInProgress = false
            console.log("[login] 检查登录状态错误:", e)
        })
    }

    function localPathForSong(song) {
        if (!song) return ""
        return root.downloadedPaths[String(song.id)] || root.downloadedPathsByName[String(song.name || "").trim().toLowerCase()] || ""
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
        root.navigateTo("playlist", { id: "fm" })
    }

    // ── 播放控制 ──
    function playSong(song, contextSongs) {
        if (!song || !song.id) return
        if (contextSongs && contextSongs.length > 0) playlist = contextSongs
        song.localPath = root.localPathForSong(song)
        song.downloaded = song.localPath !== ""
        currentSong = song
        var exists = -1
        for (var i2 = 0; i2 < playlist.length; i2++) {
            if (playlist[i2].id == song.id) { exists = i2; break }
        }
        if (exists >= 0) {
            currentIndex = exists
            playlist[exists].localPath = song.localPath
            playlist[exists].downloaded = song.downloaded
        }
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
        var s = playlist[currentIndex]
        s.localPath = root.localPathForSong(s)
        s.downloaded = s.localPath !== ""
        currentSong = s
    }

    // 自动续播：按歌单顺序找下一首「已下载」的歌；找到返回 true
    function playNextDownloaded() {
        if (playlist.length === 0) return false
        for (var idx = currentIndex + 1; idx < playlist.length; idx++) {
            var s = playlist[idx]
            var p = root.localPathForSong(s)
            if (p && p !== "") {
                s.localPath = p
                s.downloaded = true
                currentIndex = idx
                currentSong = s
                return true
            }
        }
        return false
    }

    function playPrev() {
        if (playlist.length === 0) return
        currentIndex = (currentIndex - 1 + playlist.length) % playlist.length
        var s = playlist[currentIndex]
        s.localPath = root.localPathForSong(s)
        s.downloaded = s.localPath !== ""
        currentSong = s
    }

    function downloadSong(song, includeLyrics) {
        if (!song) return
        transferBusy = true
        transferProgress = 0
        transferLabel = "下载"
        transferFileName = song.name || ""
        transferStatusTimer.restart()
        // 下载歌曲时一律同时下载同名 .lrc 文件，与歌曲放在同一目录
        ApiClient.download(song.id, song.name, song.artist, true, function(d) {
            transferBusy = false
            transferProgress = 1
            transferLabel = "下载完成"
            var ok = d && d.code === 200
            var lrcPath = d && d.lrcPath ? d.lrcPath : ""
            if (!lrcPath && d && d.path) lrcPath = d.path.replace(/\.[^.]+$/i, ".lrc")
            if (song) {
                song.downloaded = ok
                song.localPath = d && d.path ? d.path : ""
                song.localLrcPath = ok ? lrcPath : ""
                song.hasLrc = !!(d && d.lrc)
            }
            if (ok) {
                root.downloadedPaths[String(song.id)] = d.path || song.localPath || ""
                root.downloadedPathsByName[String(song.name || "").trim().toLowerCase()] = d.path || song.localPath || ""
                var found = false
                for (var di = 0; di < root.downloadedIds.length; di++) {
                    if (root.downloadedIds[di] == song.id) { found = true; break }
                }
                if (!found) root.downloadedIds.push(song.id)
            }
            for (var pi = 0; pi < playlist.length; pi++) {
                if (playlist[pi].id == song.id) {
                    playlist[pi].downloaded = ok
                    playlist[pi].localPath = song.localPath
                    playlist[pi].localLrcPath = song.localLrcPath
                    break
                }
            }
            if (currentSong && currentSong.id == song.id) currentSong = song
            var msg
            if (!ok) msg = "下载失败: " + ((d && d.msg) || "")
            else if (song && song.hasLrc) msg = "下载完成：歌曲 + 歌词（同目录同名）"
            else msg = "下载完成（该歌曲暂无歌词）"
            showToast(msg)
            transferStatusTimer.stop()
        }, function(e) {
            transferBusy = false
            transferLabel = "下载失败"
            transferStatusTimer.stop()
            showToast("下载错误: " + e)
        })
        showToast("开始下载：" + song.name + "（含歌词）")
    }

    function pollTransferStatus() {
        ApiClient.transferStatus(function(d) {
            if (!d || !d.status) return
            var s = d.status
            if (!s.running && !s.finished && s.action === "") return
            transferBusy = !!s.running || s.finished === false
            transferProgress = Math.max(0, Math.min(1, (s.total && s.total > 0) ? s.done / s.total : (s.percent || 0) / 100))
            transferLabel = (s.action === "download" ? "下载中" : (s.action === "cache" ? "缓存中" : "处理中"))
            transferFileName = s.fileName || transferFileName
            if (!s.running && s.finished) {
                transferStatusTimer.stop()
                transferBusy = false
                transferLabel = "完成"
            }
        }, function() {})
    }

    function showToast(msg) {
        toastText.text = msg
        toast.visible = true
        toastTimer.restart()
    }

    Timer {
        id: transferStatusTimer
        interval: 500
        repeat: true
        onTriggered: root.pollTransferStatus()
    }

    Rectangle {
        id: transferProgressBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 0
        height: root.transferBusy ? 28 : 0
        visible: root.transferBusy
        color: Theme.bgSecondary
        border.color: Theme.borderLight
        border.width: 1
        clip: true

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.transferProgress
            color: Theme.primary
            opacity: 0.8
        }

        Text {
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: root.transferLabel + (root.transferFileName ? (" · " + root.transferFileName) : "")
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }

        Text {
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: Math.round(root.transferProgress * 100) + "%"
            color: Theme.textPrimary
            font.pixelSize: Theme.fontSmall
            font.family: Theme.fontFamily
        }
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
