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

    // 二维码登录 key
    function loginQrKey(onSuccess, onError) {
        get("/login/qr/key", onSuccess, onError)
    }

    // 二维码登录 生成
    function loginQrCreate(key, onSuccess, onError) {
        get("/login/qr/create?key=" + key + "&qrimg=1", onSuccess, onError)
    }

    // 二维码登录 检查
    function loginQrCheck(key, onSuccess, onError) {
        get("/login/qr/check?key=" + key, onSuccess, onError)
    }

    // 发送验证码
    function captchaSent(phone, onSuccess, onError) {
        get("/captcha/sent?phone=" + phone, onSuccess, onError)
    }

    // 手机验证码登录
    function loginCellphone(phone, captcha, onSuccess, onError) {
        get("/login/cellphone?phone=" + phone + "&captcha=" + captcha, onSuccess, onError)
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
}
