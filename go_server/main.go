package main

import (
	"crypto/md5"
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

)


var (
	client    *http.Client
	cookieJar *cookiejar.Jar
	mu        sync.Mutex
)

const (
	listenAddr = "127.0.0.1:8002"
	baseAPI    = "https://music.163.com"
	musicDir   = "/userdisk/Music/netease"
	cacheDir   = "/userdisk/Music/netease/cache"
	localMusicRoot = "/userdisk/Music"
	searchHistoryFile = "/userdisk/Music/netease/search_history.json"
)

// ── 批量下载管理器 ──
type BatchTask struct {
	ID     int64  `json:"id"`
	Name   string `json:"name"`
	Artist string `json:"artist"`
}

type BatchStatus struct {
	Running     bool   `json:"running"`
	Total       int    `json:"total"`
	Done        int    `json:"done"`
	Failed      int    `json:"failed"`
	Skipped     int    `json:"skipped"`
	CurrentIdx  int    `json:"currentIdx"`
	CurrentName string `json:"currentName"`
	CurrentSize int64  `json:"currentSize"`
	CurrentTotal int64 `json:"currentTotal"`
	Finished    bool   `json:"finished"`
	Cancelled   bool   `json:"cancelled"`
}

var (
	batchMu      sync.Mutex
	batchTasks   []BatchTask
	batchIdx     int
	batchStatus  BatchStatus
	batchCancel  bool
	batchRunning bool
)

func startBatchDownload(tasks []BatchTask) {
	if batchRunning {
		return
	}
	batchTasks = tasks
	batchIdx = 0
	batchCancel = false
	batchStatus = BatchStatus{
		Running: true,
		Total:   len(tasks),
	}
	batchRunning = true
	batchMu.Unlock()

	go func() {
		for {
			batchMu.Lock()
			if batchCancel || batchIdx >= len(batchTasks) {
				batchRunning = false
				batchStatus.Running = false
				batchStatus.Finished = !batchCancel
				batchStatus.Cancelled = batchCancel
				batchMu.Unlock()
				return
			}
			task := batchTasks[batchIdx]
			batchStatus.CurrentIdx = batchIdx
			batchStatus.CurrentName = task.Name
			batchStatus.CurrentSize = 0
			batchStatus.CurrentTotal = 0
			batchMu.Unlock()

			// 执行下载
			err := downloadSong(task.ID, task.Name, task.Artist)
			batchMu.Lock()
			if err != nil {
				if strings.Contains(err.Error(), "已存在") {
					batchStatus.Skipped++
				} else {
					batchStatus.Failed++
					fmt.Printf("[batch] 下载失败 %s: %v\n", task.Name, err)
				}
			} else {
				batchStatus.Done++
			}
			batchIdx++
			batchMu.Unlock()
		}
	}()
}

func downloadSong(id int64, name, artist string) error {
	safeName := sanitizeFilename(name)
	if safeName == "" {
		safeName = fmt.Sprintf("%d", id)
	}
	dlFile := filepath.Join(musicDir, safeName+".mp3")
	// 检查是否已下载
	if _, err := os.Stat(dlFile); err == nil {
		return fmt.Errorf("已存在")
	}
	// 获取地址
	body := fmt.Sprintf(`{"ids":"[%d]","level":"standard","encodeType":"mp3"}`, id)
	data, err := weapiPost("/weapi/song/enhance/player/url/v1", body)
	if err != nil {
		return err
	}
	var result map[string]interface{}
	json.Unmarshal(data, &result)
	songs, _ := result["data"].([]interface{})
	if len(songs) == 0 {
		return fmt.Errorf("无法获取播放地址")
	}
	song := songs[0].(map[string]interface{})
	songUrl, _ := song["url"].(string)
	if songUrl == "" {
		return fmt.Errorf("歌曲无可用播放地址")
	}
	return downloadFile(songUrl, dlFile)
}

func getBatchStatus() BatchStatus {
	batchMu.Lock()
	defer batchMu.Unlock()
	return batchStatus
}

func cancelBatchDownload() {
	batchMu.Lock()
	batchCancel = true
	batchMu.Unlock()
}

func init() {
	cookieJar, _ = cookiejar.New(nil)
	// 使用标准 http.Client（API 调用无需伪造 TLS 指纹）
	client = &http.Client{
		Jar:     cookieJar,
		Timeout: 30 * time.Second,
	}
	os.MkdirAll(cacheDir, 0755)
	os.MkdirAll(musicDir, 0755)
	// 异步清理超过 7 天的缓存文件
	go cleanOldCache()
	// 读取 cookies.json（登录状态）
	loadCookiesFromFile()
}

// 从 cookies.json 加载 cookies 到 cookieJar
func loadCookiesFromFile() {
	exePath, err := os.Executable()
	if err != nil {
		return
	}
	cookiePath := filepath.Join(filepath.Dir(exePath), "cookies.json")
	data, err := os.ReadFile(cookiePath)
	if err != nil {
		fmt.Println("[cookies] 未找到 cookies.json，跳过")
		return
	}
	var cookieMap map[string]string
	if err := json.Unmarshal(data, &cookieMap); err != nil {
		fmt.Println("[cookies] 解析 cookies.json 失败:", err)
		return
	}
	url, _ := url.Parse("https://music.163.com")
	var cookies []*http.Cookie
	for name, value := range cookieMap {
		cookies = append(cookies, &http.Cookie{
			Name:   name,
			Value:  value,
			Domain: ".music.163.com",
			Path:   "/",
		})
	}
	cookieJar.SetCookies(url, cookies)
	fmt.Printf("[cookies] 已从 cookies.json 加载 %d 个 cookies\n", len(cookies))
}

func main() {
	http.HandleFunc("/ping", handlePing)
	http.HandleFunc("/search", handleSearch)
	http.HandleFunc("/song/url", handleSongUrl)
	http.HandleFunc("/lyric", handleLyric)
	http.HandleFunc("/playlist/detail", handlePlaylistDetail)
	http.HandleFunc("/recommend/resource", handleRecommend)
	http.HandleFunc("/recommend/songs", handleDailyRecommend)
	http.HandleFunc("/toplist", handleToplist)
	http.HandleFunc("/top/list", handleTopListDetail)
	http.HandleFunc("/login", handleLoginPage)
	http.HandleFunc("/login/status", handleLoginStatus)
	http.HandleFunc("/cookies/import", handleImportCookies)
	http.HandleFunc("/logout", handleLogout)
	http.HandleFunc("/user/playlist", handleUserPlaylist)
	http.HandleFunc("/user/detail", handleUserDetail)
	http.HandleFunc("/user/level", handleUserLevel)
	http.HandleFunc("/user/subcount", handleUserSubcount)
	http.HandleFunc("/personal_fm", handlePersonalFM)
	http.HandleFunc("/record/recent/song", handleRecentSong)
	http.HandleFunc("/like", handleLike)
	http.HandleFunc("/daily_signin", handleDailySignin)
	http.HandleFunc("/scrobble", handleScrobble)
	http.HandleFunc("/download", handleDownload)
	http.HandleFunc("/cache", handleCache)
	http.HandleFunc("/downloads", handleDownloads)
	http.HandleFunc("/download/batch/start", handleBatchStart)
	http.HandleFunc("/download/batch/status", handleBatchStatus)
	http.HandleFunc("/download/batch/cancel", handleBatchCancel)
	http.HandleFunc("/local/list", handleLocalList)
	http.HandleFunc("/local/delete", handleLocalDelete)
	http.HandleFunc("/audio", handleAudioProxy)
	http.HandleFunc("/search/history", handleSearchHistory)

	// 异步初始化 cookie（避免阻塞 server 启动导致插件连接超时）
	go initCookies()

	fmt.Println("NeteaseMusic server listening on", listenAddr)
	http.ListenAndServe(listenAddr, nil)
}

// 初始化 cookie：获取 NMTID/__csrf 等必需 cookie
func initCookies() {
	// 设置必需的 cookie
	// 这些 cookie 是 weapi 接口必需的
	u, _ := url.Parse("https://music.163.com")
	csrfToken := randomHex(32)
	nmtid := randomString(22)
	cookieJar.SetCookies(u, []*http.Cookie{
		{Name: "__csrf", Value: csrfToken, Path: "/", Domain: ".music.163.com"},
		{Name: "NMTID", Value: nmtid, Path: "/", Domain: ".music.163.com"},
		{Name: "os", Value: "pc", Path: "/", Domain: ".music.163.com"},
	})
	fmt.Printf("[cookies] 手动设置 __csrf=%s NMTID=%s\n", csrfToken, nmtid)
	// 访问首页，让服务器设置更多 cookie
	req, _ := http.NewRequest("GET", "https://music.163.com/", nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	resp, err := client.Do(req)
	if err != nil {
		fmt.Println("[cookies] 访问首页失败:", err)
	} else {
		resp.Body.Close()
	}
	cookies := cookieJar.Cookies(u)
	fmt.Printf("[cookies] 初始化完成，获取到 %d 个 cookies\n", len(cookies))
	for _, c := range cookies {
		fmt.Printf("[cookies]   %s=%s\n", c.Name, c.Value[:min(20, len(c.Value))])
	}
}

// 生成指定长度的十六进制随机串
func randomHex(n int) string {
	const chars = "0123456789abcdef"
	b := make([]byte, n)
	for i := range b {
		num, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[num.Int64()]
	}
	return string(b)
}

// web cookies 导入服务（监听 8667，浏览器访问）

// 导入 cookies（支持 JSON 格式和字符串格式）


// ── 工具函数 ──

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, msg string) {
	writeJSON(w, map[string]interface{}{"code": 500, "msg": msg})
}

// 从 cookie 中获取 _csrf token
func getCsrfToken() string {
	u, _ := url.Parse("https://music.163.com")
	cookies := cookieJar.Cookies(u)
	for _, c := range cookies {
		if c.Name == "__csrf" || c.Name == "_csrf" {
			return c.Value
		}
	}
	return ""
}

// weapi POST 请求
func weapiPost(path, jsonStr string) ([]byte, error) {
	// 从 cookie 中获取 _csrf，加到请求体中（网易云 weapi 接口要求）
	csrf := getCsrfToken()
	if csrf != "" {
		var data map[string]interface{}
		if err := json.Unmarshal([]byte(jsonStr), &data); err == nil {
			data["csrf_token"] = csrf
			if b, err := json.Marshal(data); err == nil {
				jsonStr = string(b)
			}
		}
	}
	params, encSecKey := weapiEncrypt(jsonStr)
	form := url.Values{}
	form.Set("params", params)
	form.Set("encSecKey", encSecKey)

	req, _ := http.NewRequest("POST", baseAPI+path, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Origin", "https://music.163.com")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	req.Header.Set("X-Requested-With", "XMLHttpRequest")
	// 浏览器特有的 sec-* 头
	req.Header.Set("sec-ch-ua", `"Not_A Brand";v="8", "Chromium";v="120", "Google Chrome";v="120"`)
	req.Header.Set("sec-ch-ua-mobile", "?0")
	req.Header.Set("sec-ch-ua-platform", `"Windows"`)
	req.Header.Set("sec-fetch-dest", "empty")
	req.Header.Set("sec-fetch-mode", "cors")
	req.Header.Set("sec-fetch-site", "same-origin")

	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("[weapiPost] 请求失败 path=%s err=%s\n", path, err.Error())
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		fmt.Printf("[weapiPost] 读取响应失败 path=%s err=%s\n", path, err.Error())
		return nil, err
	}
	fmt.Printf("[weapiPost] path=%s status=%d size=%d\n", path, resp.StatusCode, len(data))
	return data, nil
}

// 简单 GET（用于不需要加密的接口）
func simpleGet(path string) ([]byte, error) {
	req, _ := http.NewRequest("GET", baseAPI+path, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	resp, err := client.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

// ── 处理器 ──

func handlePing(w http.ResponseWriter, r *http.Request) {
	writeJSON(w, map[string]interface{}{"code": 200, "msg": "pong"})
}

func handleSearch(w http.ResponseWriter, r *http.Request) {
	kw := r.URL.Query().Get("keywords")
	if kw == "" {
		writeError(w, "缺少 keywords")
		return
	}
	body := fmt.Sprintf(`{"s":"%s","type":1,"limit":30,"offset":0}`, kw)
	data, err := weapiPost("/weapi/search/get", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleSongUrl(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	body := fmt.Sprintf(`{"ids":"[%d]","level":"standard","encodeType":"mp3"}`, id)
	data, err := weapiPost("/weapi/song/enhance/player/url/v1", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleLyric(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	body := fmt.Sprintf(`{"id":%s,"lv":-1,"tv":-1}`, id)
	data, err := weapiPost("/weapi/song/lyric", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handlePlaylistDetail(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	body := fmt.Sprintf(`{"id":%s,"n":1000,"s":8}`, id)
	data, err := weapiPost("/weapi/v6/playlist/detail", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleRecommend(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/v1/discovery/recommend/resource", `{"cat":"全部","limit":10,"offset":0,"total":true}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleDailyRecommend(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/v2/discovery/recommend/songs", `{"limit":30,"offset":0,"total":true}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleToplist(w http.ResponseWriter, r *http.Request) {
	data, err := simpleGet("/api/toplist")
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleTopListDetail(w http.ResponseWriter, r *http.Request) {
	idx := r.URL.Query().Get("idx")
	if idx == "" {
		idx = "0"
	}
	body := fmt.Sprintf(`{"id":0,"idx":%s,"limit":30,"offset":0,"total":true}`, idx)
	data, err := weapiPost("/weapi/top/list", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// 保存当前 cookies 到 cookies.json
func saveCookiesToFile() {
	exePath, err := os.Executable()
	if err != nil {
		return
	}
	cookiePath := filepath.Join(filepath.Dir(exePath), "cookies.json")
	url, _ := url.Parse("https://music.163.com")
	cookies := cookieJar.Cookies(url)
	cookieMap := make(map[string]string)
	for _, c := range cookies {
		cookieMap[c.Name] = c.Value
	}
	data, _ := json.MarshalIndent(cookieMap, "", "  ")
	os.WriteFile(cookiePath, data, 0644)
}

// 极简登录页（只需要粘贴 MUSIC_U）
func handleLoginPage(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Write([]byte(`<!DOCTYPE html>
<html><head><meta charset="utf-8"><title>网易云登录</title>
<style>body{font-family:sans-serif;max-width:500px;margin:40px auto;padding:20px}
h1{font-size:20px;color:#c20c0c}.tip{color:#666;font-size:14px;line-height:1.8;margin:15px 0}
textarea{width:100%;height:80px;padding:10px;box-sizing:border-box;border:1px solid #ddd;border-radius:4px;font-family:monospace;font-size:13px}
button{padding:10px 30px;background:#c20c0c;color:white;border:none;border-radius:4px;cursor:pointer;font-size:15px}
button:hover{background:#a00a0a}#result{margin-top:15px;font-weight:bold}</style></head>
<body><h1>网易云音乐登录</h1>
<div class="tip">1. 电脑浏览器打开 <b>music.163.com</b> 并登录<br>
2. 按 <b>F12</b> → Application(应用) → Cookies → 找到 <b>MUSIC_U</b><br>
3. 复制 MUSIC_U 的值，粘贴到下面，点击导入</div>
<textarea id="musicU" placeholder="粘贴 MUSIC_U 的值（一长串字符）"></textarea>
<br><br><button onclick="doImport()">导入登录</button>
<p id="result"></p>
<script>function doImport(){var v=document.getElementById("musicU").value.trim();
if(!v){alert("请输入 MUSIC_U");return}
fetch("/cookies/import",{method:"POST",headers:{"Content-Type":"application/json"},
body:JSON.stringify({MUSIC_U:v})}).then(r=>r.json()).then(d=>{
if(d.code===200){document.getElementById("result").innerHTML='<span style="color:green">登录成功！可以关闭此页面，回到词典笔查看</span>'}
else{document.getElementById("result").innerHTML='<span style="color:red">失败: "+(d.msg||"未知错误")+"</span>'}
}).catch(e=>{document.getElementById("result").innerHTML='<span style="color:red">请求失败: "+e+"</span>'})}</script>
</body></html>`))
}

// 导入 cookies（只需要 MUSIC_U）
func handleImportCookies(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, "需要 POST 请求")
		return
	}
	var req map[string]string
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, "JSON 解析失败")
		return
	}
	musicU, ok := req["MUSIC_U"]
	if !ok || musicU == "" {
		writeError(w, "MUSIC_U 不能为空")
		return
	}
	// 设置 MUSIC_U cookie
	u, _ := url.Parse("https://music.163.com")
	cookieJar.SetCookies(u, []*http.Cookie{
		{Name: "MUSIC_U", Value: musicU, Domain: ".music.163.com", Path: "/"},
	})
	// 访问首页获取 __csrf 和 NMTID（网易云需要这些）
	client.Get("https://music.163.com")
	// 保存到文件
	saveCookiesToFile()
	fmt.Printf("[cookies] 导入 MUSIC_U 成功，已保存到 cookies.json\n")
	writeJSON(w, map[string]interface{}{"code": 200, "msg": "登录成功"})
}

func handleLoginStatus(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/w/nuser/account/get", `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleLogout(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/logout", `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleUserPlaylist(w http.ResponseWriter, r *http.Request) {
	uid := r.URL.Query().Get("uid")
	if uid == "" {
		writeError(w, "缺少 uid")
		return
	}
	body := fmt.Sprintf(`{"uid":%s,"limit":30,"offset":0,"includeVideo":true}`, uid)
	data, err := weapiPost("/weapi/user/playlist", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 用户详情（等级、签名、关注/粉丝、听歌次数）──
func handleUserDetail(w http.ResponseWriter, r *http.Request) {
	uid := r.URL.Query().Get("uid")
	if uid == "" {
		writeError(w, "缺少 uid")
		return
	}
	data, err := weapiPost("/weapi/v1/user/detail/"+uid, `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 用户等级 ──
func handleUserLevel(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/user/level", `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 用户订阅统计（歌单、歌手、专辑、MV等数量）──
func handleUserSubcount(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/user/subcount", `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 私人 FM ──
func handlePersonalFM(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/v1/radio/get", `{}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 最近播放记录 ──
func handleRecentSong(w http.ResponseWriter, r *http.Request) {
	limit := r.URL.Query().Get("limit")
	if limit == "" { limit = "100" }
	// 最近播放是 GET 接口，不是 weapi POST
	data, err := simpleGet("/api/record/recent/song?limit=" + limit)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}
// ── 喜欢/取消喜欢音乐 ──
func handleLike(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	like := r.URL.Query().Get("like")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	if like == "" {
		like = "true"
	}
	body := fmt.Sprintf(`{"alg":"itembased","trackId":%s,"like":%s,"time":25}`, id, like)
	data, err := weapiPost("/weapi/radio/like", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 每日签到（+3经验，安卓端）──
func handleDailySignin(w http.ResponseWriter, r *http.Request) {
	// type=1 安卓端（+3经验），type=0 PC端（+2经验）
	body := `{"type":1}`
	data, err := weapiPost("/weapi/point/dailyTask", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 提交听歌记录（+0.5经验/首，每天上限10首）──
func handleScrobble(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	sourceid := r.URL.Query().Get("sourceid")
	timeStr := r.URL.Query().Get("time")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	if sourceid == "" {
		sourceid = "0"
	}
	if timeStr == "" {
		timeStr = "0"
	}
	// 构造听歌记录日志
	logs := fmt.Sprintf(`[{"action":"play","json":{"id":%s,"sourceId":%s,"time":%s,"download":0,"end":"ui","type":"song","wifi":0}}]`, id, sourceid, timeStr)
	body := fmt.Sprintf(`{"logs":%s}`, logs)
	data, err := weapiPost("/weapi/feedback/weblog", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

// ── 下载和缓存 ──

func handleCache(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	urlParam := r.URL.Query().Get("url")

	if id == "" && urlParam == "" {
		writeError(w, "缺少 id 或 url")
		return
	}

	var cacheFile string
	var songUrl string

	if urlParam != "" {
		// 直接传 URL，用哈希作为缓存文件名
		hash := md5.Sum([]byte(urlParam))
		cacheFile = filepath.Join(cacheDir, fmt.Sprintf("%x.mp3", hash))
		songUrl = urlParam
	} else {
		// 传 ID，先获取播放地址
		cacheFile = filepath.Join(cacheDir, id+".mp3")
	}

	// 检查缓存
	if _, err := os.Stat(cacheFile); err == nil {
		writeJSON(w, map[string]interface{}{"code": 200, "path": cacheFile, "cached": true})
		return
	}

	// 如果是 ID 模式，先获取播放地址
	if songUrl == "" {
		body := fmt.Sprintf(`{"ids":"[%d]","level":"standard","encodeType":"mp3"}`, id)
		data, err := weapiPost("/weapi/song/enhance/player/url/v1", body)
		if err != nil {
			writeError(w, err.Error())
			return
		}
		var result map[string]interface{}
		json.Unmarshal(data, &result)
		songs, _ := result["data"].([]interface{})
		if len(songs) == 0 {
			writeError(w, "无法获取播放地址")
			return
		}
		song := songs[0].(map[string]interface{})
		songUrl, _ = song["url"].(string)
		if songUrl == "" {
			writeError(w, "歌曲无可用播放地址（可能需要 VIP）")
			return
		}
	}

	fmt.Printf("[cache] downloading to %s\n", cacheFile)
	// 下载
	if err := downloadFile(songUrl, cacheFile); err != nil {
		writeError(w, "下载失败: "+err.Error())
		return
	}
	writeJSON(w, map[string]interface{}{"code": 200, "path": cacheFile, "cached": false})
}

func handleDownload(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	name := r.URL.Query().Get("name")
	artist := r.URL.Query().Get("artist")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	safeName := sanitizeFilename(name)
	if safeName == "" {
		safeName = id
	}
	dlFile := filepath.Join(musicDir, safeName+".mp3")
	// 检查是否已下载
	if _, err := os.Stat(dlFile); err == nil {
		writeJSON(w, map[string]interface{}{"code": 200, "path": dlFile, "msg": "已存在"})
		return
	}
	// 获取地址并下载
	body := fmt.Sprintf(`{"ids":"[%d]","level":"standard","encodeType":"mp3"}`, id)
	data, err := weapiPost("/weapi/song/enhance/player/url/v1", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	var result map[string]interface{}
	json.Unmarshal(data, &result)
	songs, _ := result["data"].([]interface{})
	if len(songs) == 0 {
		writeError(w, "无法获取播放地址")
		return
	}
	song := songs[0].(map[string]interface{})
	songUrl, _ := song["url"].(string)
	if songUrl == "" {
		writeError(w, "歌曲无可用播放地址")
		return
	}
	if err := downloadFile(songUrl, dlFile); err != nil {
		writeError(w, "下载失败: "+err.Error())
		return
	}
	writeJSON(w, map[string]interface{}{"code": 200, "path": dlFile, "name": name, "artist": artist})
}

func handleDownloads(w http.ResponseWriter, r *http.Request) {
	files, err := os.ReadDir(musicDir)
	if err != nil {
		writeJSON(w, map[string]interface{}{"code": 200, "files": []interface{}{}})
		return
	}
	var list []map[string]interface{}
	for _, f := range files {
		if f.IsDir() {
			continue
		}
		ext := strings.ToLower(filepath.Ext(f.Name()))
		if ext == ".mp3" || ext == ".flac" || ext == ".m4a" || ext == ".aac" {
			info, _ := f.Info()
			list = append(list, map[string]interface{}{
				"name": strings.TrimSuffix(f.Name(), ext),
				"path": filepath.Join(musicDir, f.Name()),
				"size": fmt.Sprintf("%.1fMB", float64(info.Size())/1024/1024),
			})
		}
	}
	writeJSON(w, map[string]interface{}{"code": 200, "files": list})
}

// ── 批量下载 API ──
func handleBatchStart(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, "需要 POST")
		return
	}
	var req struct {
		Songs []BatchTask `json:"songs"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, "JSON 解析失败: "+err.Error())
		return
	}
	if len(req.Songs) == 0 {
		writeError(w, "歌曲列表为空")
		return
	}
	startBatchDownload(req.Songs)
	writeJSON(w, map[string]interface{}{"code": 200, "msg": "已开始批量下载", "total": len(req.Songs)})
}

func handleBatchStatus(w http.ResponseWriter, r *http.Request) {
	status := getBatchStatus()
	writeJSON(w, map[string]interface{}{"code": 200, "status": status})
}

func handleBatchCancel(w http.ResponseWriter, r *http.Request) {
	cancelBatchDownload()
	writeJSON(w, map[string]interface{}{"code": 200, "msg": "已取消"})
}

// ── 本地音乐管理 API ──
func handleLocalList(w http.ResponseWriter, r *http.Request) {
	var list []map[string]interface{}
	// 扫描 /userdisk/Music/ 下所有音乐文件（包括子目录）
	filepath.Walk(localMusicRoot, func(path string, info os.FileInfo, err error) error {
		if err != nil || info.IsDir() {
			return nil
		}
		ext := strings.ToLower(filepath.Ext(path))
		if ext == ".mp3" || ext == ".flac" || ext == ".m4a" || ext == ".aac" || ext == ".wav" || ext == ".ogg" {
			// 跳过缓存目录
			if strings.Contains(path, "/cache/") {
				return nil
			}
			list = append(list, map[string]interface{}{
				"name":    strings.TrimSuffix(info.Name(), ext),
				"path":    path,
				"size":    info.Size(),
				"sizeStr": fmt.Sprintf("%.1fMB", float64(info.Size())/1024/1024),
				"modTime": info.ModTime().Unix(),
				"ext":     ext,
			})
		}
		return nil
	})
	if list == nil {
		list = []map[string]interface{}{}
	}
	writeJSON(w, map[string]interface{}{"code": 200, "files": list, "count": len(list)})
}

func handleLocalDelete(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, "需要 POST")
		return
	}
	var req struct {
		Path string `json:"path"`
	}
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		writeError(w, "JSON 解析失败")
		return
	}
	if req.Path == "" {
		writeError(w, "缺少 path")
		return
	}
	// 安全检查：只允许删除 /userdisk/Music/ 下的文件
	if !strings.HasPrefix(req.Path, localMusicRoot) {
		writeError(w, "路径不合法")
		return
	}
	if err := os.Remove(req.Path); err != nil {
		writeError(w, "删除失败: "+err.Error())
		return
	}
	writeJSON(w, map[string]interface{}{"code": 200, "msg": "已删除"})
}

// 下载文件
func downloadFile(url, dest string) error {
	os.MkdirAll(filepath.Dir(dest), 0755)
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return err
	}
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Accept", "*/*")
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	fmt.Printf("[download] status=%d content-type=%s content-length=%s\n",
		resp.StatusCode, resp.Header.Get("Content-Type"), resp.Header.Get("Content-Length"))
	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()
	n, err := io.Copy(out, resp.Body)
	fmt.Printf("[download] saved %d bytes to %s\n", n, dest)
	return err
}

// 清理文件名中的非法字符
// 清理超过 7 天的缓存文件，避免缓存目录无限增长
func cleanOldCache() {
	files, err := os.ReadDir(cacheDir)
	if err != nil { return }
	now := time.Now()
	cleaned := 0
	for _, f := range files {
		if f.IsDir() { continue }
		info, err := f.Info()
		if err != nil { continue }
		if now.Sub(info.ModTime()) > 7*24*time.Hour {
			os.Remove(filepath.Join(cacheDir, f.Name()))
			cleaned++
		}
	}
	if cleaned > 0 {
		fmt.Printf("[cache] 清理了 %d 个过期缓存文件\n", cleaned)
	}
}

func sanitizeFilename(name string) string {
	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return strings.TrimSpace(replacer.Replace(name))
}


// ── 搜索历史持久化 ──
// 保存到本地 JSON 文件，重启后不丢失

func loadSearchHistory() []string {
	data, err := os.ReadFile(searchHistoryFile)
	if err != nil { return []string{} }
	var list []string
	if err := json.Unmarshal(data, &list); err != nil { return []string{} }
	return list
}

func saveSearchHistory(list []string) {
	os.MkdirAll(filepath.Dir(searchHistoryFile), 0755)
	data, _ := json.Marshal(list)
	os.WriteFile(searchHistoryFile, data, 0644)
}

func handleSearchHistory(w http.ResponseWriter, r *http.Request) {
	switch r.Method {
	case "GET":
		list := loadSearchHistory()
		writeJSON(w, map[string]interface{}{"code": 200, "history": list})
	case "POST":
		var req struct { Keyword string `json:"keyword"` }
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			writeError(w, "JSON 解析失败")
			return
		}
		kw := strings.TrimSpace(req.Keyword)
		if kw == "" { writeError(w, "关键词为空"); return }
		list := loadSearchHistory()
		newList := []string{kw}
		for _, item := range list {
			if item != kw { newList = append(newList, item) }
		}
		if len(newList) > 20 { newList = newList[:20] }
		saveSearchHistory(newList)
		writeJSON(w, map[string]interface{}{"code": 200, "history": newList})
	case "DELETE":
		saveSearchHistory([]string{})
		writeJSON(w, map[string]interface{}{"code": 200, "msg": "已清除"})
	default:
		writeError(w, "不支持的方法")
	}
}

// 音频流代理：C++ 播放器从本地 127.0.0.1:8002/audio?url=xxx 读取，Go 转发到网易云 CDN
// 音频流代理
func handleAudioProxy(w http.ResponseWriter, r *http.Request) {
	audioUrl := r.URL.Query().Get("url")
	if audioUrl == "" {
		http.Error(w, "missing url", 400)
		return
	}
	fmt.Printf("[audio-proxy] proxying: %s\n", audioUrl[:min(80, len(audioUrl))])

	req, err := http.NewRequest("GET", audioUrl, nil)
	if err != nil {
		http.Error(w, "create request failed: "+err.Error(), 500)
		return
	}
	// 设置请求头
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Accept", "*/*")
	// 注意：不透传 Range 请求，总是返回完整文件（200）
	// FFmpeg 的 avformat_open_input() 对 206 分块响应支持不好，会报 Invalid data
	// 跳转播放时 FFmpeg 会重新发 Range，但初始打开必须是完整文件

	resp, err := client.Do(req)
	if err != nil {
		fmt.Printf("[audio-proxy] request failed: %v\n", err)
		http.Error(w, "upstream failed: "+err.Error(), 502)
		return
	}
	defer resp.Body.Close()

	fmt.Printf("[audio-proxy] upstream status: %d, content-type: %s, content-length: %s\n",
		resp.StatusCode, resp.Header.Get("Content-Type"), resp.Header.Get("Content-Length"))

	// 只透传安全的响应头，不透传 Content-Encoding（避免 FFmpeg 不支持的压缩）
	w.Header().Set("Content-Type", resp.Header.Get("Content-Type"))
	if cl := resp.Header.Get("Content-Length"); cl != "" {
		w.Header().Set("Content-Length", cl)
	}
	w.Header().Set("Accept-Ranges", "bytes")
	// 强制返回 200（即使上游返回 206），确保 FFmpeg 拿到完整文件
	w.WriteHeader(200)

	// 流式转发音频数据
	written, err := io.Copy(w, resp.Body)
	if err != nil {
		fmt.Printf("[audio-proxy] copy error after %d bytes: %v\n", written, err)
	} else {
		fmt.Printf("[audio-proxy] done, %d bytes\n", written)
	}
}
