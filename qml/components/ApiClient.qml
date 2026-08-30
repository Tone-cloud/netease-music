pragma Singleton
import QtQuick 2.12

QtObject {
    id: apiClient

    property string baseUrl: "http://127.0.0.1:8001"

    // 通用 GET 请求
    function get(path, onSuccess, onError) {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", baseUrl + path, true)
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        if (onSuccess) onSuccess(data)
                    } catch (e) {
                        if (onError) onError("JSON 解析失败: " + e)
                    }
                } else {
                    if (onError) onError("HTTP " + xhr.status)
                }
            }
        }
        xhr.onerror = function() {
            if (onError) onError("网络错误")
        }
        xhr.send()
    }

    // 通用 POST 请求
    function post(path, body, onSuccess, onError) {
        var xhr = new XMLHttpRequest()
        xhr.open("POST", baseUrl + path, true)
        xhr.setRequestHeader("Content-Type", "application/json")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4) {
                if (xhr.status === 200) {
                    try {
                        var data = JSON.parse(xhr.responseText)
                        if (onSuccess) onSuccess(data)
                    } catch (e) {
                        if (onError) onError("JSON 解析失败")
                    }
                } else {
                    if (onError) onError("HTTP " + xhr.status)
                }
            }
        }
        xhr.onerror = function() { if (onError) onError("网络错误") }
        xhr.send(JSON.stringify(body))
    }

    // 健康检查
    function ping(onSuccess) {
        get("/ping", function(d) { if (onSuccess) onSuccess(d.code === 200) },
            function() { if (onSuccess) onSuccess(false) })
    }

    // 搜索
    function search(keywords, onSuccess, onError) {
        get("/search?keywords=" + encodeURIComponent(keywords), onSuccess, onError)
    }

    // 歌曲详情/播放地址
    function songUrl(id, onSuccess, onError) {
        get("/song/url?id=" + id, onSuccess, onError)
    }

    // 歌词
    function lyric(id, onSuccess, onError) {
        get("/lyric?id=" + id, onSuccess, onError)
    }

    // 歌单详情
    function playlistDetail(id, onSuccess, onError) {
        get("/playlist/detail?id=" + id, onSuccess, onError)
    }

    // 推荐歌单
    function recommend(onSuccess, onError) {
        get("/recommend/resource", onSuccess, onError)
    }

    // 每日推荐
    function dailyRecommend(onSuccess, onError) {
        get("/recommend/songs", onSuccess, onError)
    }

    // 排行榜
    function toplist(onSuccess, onError) {
        get("/toplist", onSuccess, onError)
    }

    // 排行榜详情
    function topListDetail(idx, onSuccess, onError) {
        get("/top/list?idx=" + idx, onSuccess, onError)
    }

    // 登录状态
    function loginStatus(onSuccess, onError) {
        get("/login/status", onSuccess, onError)
    }

    // 退出登录
    function logout(onSuccess, onError) {
        get("/logout", onSuccess, onError)
    }

    // 用户歌单
    function userPlaylist(uid, onSuccess, onError) {
        get("/user/playlist?uid=" + uid, onSuccess, onError)
    }

    // 用户详情（等级、签名、关注/粉丝）
    function userDetail(uid, onSuccess, onError) {
        get("/user/detail?uid=" + uid, onSuccess, onError)
    }

    // 用户等级
    function userLevel(onSuccess, onError) {
        get("/user/level", onSuccess, onError)
    }

    // 用户订阅统计
    function userSubcount(onSuccess, onError) {
        get("/user/subcount", onSuccess, onError)
    }

    // 私人 FM
    function personalFM(onSuccess, onError) {
        get("/personal_fm", onSuccess, onError)
    }

    // 最近播放
    function recentSong(limit, onSuccess, onError) {
        var l = limit || 100
        get("/record/recent/song?limit=" + l, onSuccess, onError)
    }

    // 喜欢/取消喜欢
    function like(id, like, onSuccess, onError) {
        var l = like === false ? "false" : "true"
        get("/like?id=" + id + "&like=" + l, onSuccess, onError)
    }

    // 每日签到（+3经验）
    function dailySignin(onSuccess, onError) {
        get("/daily_signin", onSuccess, onError)
    }

    // 提交听歌记录（+0.5经验/首）
    function scrobble(id, sourceid, time, onSuccess, onError) {
        var sid = sourceid || 0
        var t = time || 0
        get("/scrobble?id=" + id + "&sourceid=" + sid + "&time=" + t, onSuccess, onError)
    }


    // ── 搜索历史（持久化到本地文件）──
    function getSearchHistory(onSuccess, onError) {
        get("/search/history", onSuccess, onError)
    }

    function addSearchHistory(keyword, onSuccess, onError) {
        post("/search/history", { keyword: keyword }, onSuccess, onError)
    }

    function clearSearchHistory(onSuccess, onError) {
        var xhr = new XMLHttpRequest()
        xhr.open("DELETE", "http://127.0.0.1:8001/search/history")
        xhr.onreadystatechange = function() {
            if (xhr.readyState === 4 && onSuccess) onSuccess(JSON.parse(xhr.responseText || "{}"))
        }
        xhr.send()
    }

    // 下载
    function download(id, name, artist, onSuccess, onError) {
        get("/download?id=" + id + "&name=" + encodeURIComponent(name) + "&artist=" + encodeURIComponent(artist),
            onSuccess, onError)
    }

    // 缓存（返回本地路径）
    function cache(id, name, artist, onSuccess, onError) {
        get("/cache?id=" + id + "&name=" + encodeURIComponent(name) + "&artist=" + encodeURIComponent(artist),
            onSuccess, onError)
    }

    // 下载列表
    function downloadList(onSuccess, onError) {
        get("/downloads", onSuccess, onError)
    }

    // ── 批量下载 ──
    function batchStart(songs, onSuccess, onError) {
        post("/download/batch/start", { songs: songs }, onSuccess, onError)
    }

    function batchStatus(onSuccess, onError) {
        get("/download/batch/status", onSuccess, onError)
    }

    function batchCancel(onSuccess, onError) {
        post("/download/batch/cancel", {}, onSuccess, onError)
    }

    // ── 本地音乐管理 ──
    function localList(onSuccess, onError) {
        get("/local/list", onSuccess, onError)
    }

    function localDelete(path, onSuccess, onError) {
        post("/local/delete", { path: path }, onSuccess, onError)
    }
}
