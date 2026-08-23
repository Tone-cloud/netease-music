package main

import (
	"crypto/rand"
	"embed"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"math/big"
	"net"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
	"time"

	qrcode "github.com/skip2/go-qrcode"
	utls "github.com/refraction-networking/utls"
)

//go:embed web/*
var webFS embed.FS

var (
	client    *http.Client
	cookieJar *cookiejar.Jar
	mu        sync.Mutex
)

const (
	listenAddr = "127.0.0.1:8001"
	baseAPI    = "https://music.163.com"
	musicDir   = "/userdisk/Music/netease"
	cacheDir   = "/userdisk/Music/netease/cache"
)

// utlsDial 使用 utls 模拟 Chrome 的 TLS 指纹（ClientHello），绕过网易云风控
// 手动修改 ALPN 扩展，只保留 http/1.1，避免 HTTP/2 帧解析错误
func utlsDial(network, addr string) (net.Conn, error) {
	conn, err := net.Dial(network, addr)
	if err != nil {
		return nil, err
	}
	host := addr
	if idx := strings.Index(addr, ":"); idx >= 0 {
		host = addr[:idx]
	}
	config := utls.Config{
		ServerName: host,
	}
	uConn := utls.UClient(conn, &config, utls.HelloChrome_120)
	// 构建握手状态，手动修改 ALPN 扩展，只保留 http/1.1
	if err := uConn.BuildHandshakeState(); err != nil {
		conn.Close()
		return nil, err
	}
	for _, ext := range uConn.Extensions {
		if alpn, ok := ext.(*utls.ALPNExtension); ok {
			alpn.AlpnProtocols = []string{"http/1.1"}
			fmt.Printf("[utls] 已修改 ALPN 扩展为 http/1.1\n")
			break
		}
	}
	if err := uConn.Handshake(); err != nil {
		conn.Close()
		return nil, err
	}
	state := uConn.ConnectionState()
	fmt.Printf("[utls] 握手成功 host=%s version=%x negotiated=%s\n", host, state.Version, state.NegotiatedProtocol)
	return uConn, nil
}

func init() {
	cookieJar, _ = cookiejar.New(nil)
	// 配置 Transport，使用 utls 模拟 Chrome 的 TLS 指纹
	transport := &http.Transport{
		DialTLS:             utlsDial,
		MaxIdleConns:        100,
		IdleConnTimeout:     90 * time.Second,
		TLSHandshakeTimeout: 10 * time.Second,
		ExpectContinueTimeout: 1 * time.Second,
	}
	client = &http.Client{
		Jar:       cookieJar,
		Transport: transport,
		Timeout:   30 * time.Second,
	}
	os.MkdirAll(cacheDir, 0755)
	// 读取 cookies.json（用户从网页端登录获取的 cookies，减少风控）
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
	http.HandleFunc("/login/qr/key", handleQrKey)
	http.HandleFunc("/login/qr/create", handleQrCreate)
	http.HandleFunc("/login/qr/check", handleQrCheck)
	http.HandleFunc("/captcha/sent", handleCaptchaSent)
	http.HandleFunc("/login/cellphone", handleLoginCellphone)
	http.HandleFunc("/login/status", handleLoginStatus)
	http.HandleFunc("/logout", handleLogout)
	http.HandleFunc("/user/playlist", handleUserPlaylist)
	http.HandleFunc("/download", handleDownload)
	http.HandleFunc("/cache", handleCache)
	http.HandleFunc("/downloads", handleDownloads)

	// 异步初始化 cookie（避免阻塞 server 启动导致插件连接超时）
	go initCookies()

	fmt.Println("NeteaseMusic server listening on", listenAddr)
	// 启动 web 短信登录服务（浏览器访问，减少风控）
	go startWebLoginServer()
	http.ListenAndServe(listenAddr, nil)
}

// 初始化 cookie：先调用匿名登录接口获取 NMTID/__csrf 等 cookie，减少风控
func initCookies() {
	// 手动设置网易云网页端必需的 cookie（SPA 页面通过 JS 设置，Go 客户端拿不到，自己生成）
	// 这些 cookie 服务器只用于风控/防 CSRF，不验证有效性
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
func startWebLoginServer() {
	mux := http.NewServeMux()
	// 静态文件
	sub, _ := fs.Sub(webFS, "web")
	mux.Handle("/", http.FileServer(http.FS(sub)))
	// API
	mux.HandleFunc("/api/sms/send", handleWebSmsSend)
	mux.HandleFunc("/api/login/sms", handleWebSmsLogin)
	mux.HandleFunc("/api/import", handleImportCookies)
	mux.HandleFunc("/pull", handleWebPull)
	addr := "0.0.0.0:8667"
	fmt.Println("[web-login] 登录服务监听于 http://" + addr + "/verify.html")
	http.ListenAndServe(addr, mux)
}

func handleWebSmsSend(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	if phone == "" {
		writeError(w, "缺少 phone")
		return
	}
	body := fmt.Sprintf(`{"phone":"%s","ctcode":"86"}`, phone)
	data, err := weapiPost("/weapi/sms/captcha/sent", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleWebSmsLogin(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	captcha := r.URL.Query().Get("captcha")
	if phone == "" || captcha == "" {
		writeError(w, "缺少 phone 或 captcha")
		return
	}
	body := fmt.Sprintf(`{"phone":"%s","captcha":"%s","rememberLogin":"true","csrf_token":""}`, phone, captcha)
	data, err := weapiPost("/weapi/login/cellphone", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
	// 登录成功后保存 cookies
	var resp struct {
		Code int `json:"code"`
	}
	if json.Unmarshal(data, &resp) == nil && resp.Code == 200 {
		saveCookiesToFile()
		fmt.Println("[web-login] 短信登录成功，已保存 cookies")
	}
}

// 导入 cookies（支持 JSON 格式和字符串格式）
func handleImportCookies(w http.ResponseWriter, r *http.Request) {
	if r.Method != "POST" {
		writeError(w, "需要 POST")
		return
	}
	body, _ := io.ReadAll(r.Body)
	cookieStr := strings.TrimSpace(string(body))
	if cookieStr == "" {
		// 尝试从表单获取
		cookieStr = r.FormValue("cookies")
	}
	if cookieStr == "" {
		writeError(w, "cookies 为空")
		return
	}

	u, _ := url.Parse("https://music.163.com")
	count := 0

	// 尝试 JSON 格式：[{"name":"xxx","value":"yyy"},...] 或 {"xxx":"yyy",...}
	if strings.HasPrefix(cookieStr, "[") || strings.HasPrefix(cookieStr, "{") {
		// 数组格式
		var arr []struct {
			Name  string `json:"name"`
			Value string `json:"value"`
		}
		if err := json.Unmarshal([]byte(cookieStr), &arr); err == nil {
			for _, c := range arr {
				if c.Name != "" {
					cookieJar.SetCookies(u, []*http.Cookie{{Name: c.Name, Value: c.Value, Path: "/", Domain: ".music.163.com"}})
					count++
				}
			}
		} else {
			// map 格式
			var m map[string]string
			if err := json.Unmarshal([]byte(cookieStr), &m); err == nil {
				for name, value := range m {
					cookieJar.SetCookies(u, []*http.Cookie{{Name: name, Value: value, Path: "/", Domain: ".music.163.com"}})
					count++
				}
			}
		}
	} else {
		// 字符串格式：name=value; name=value; ...
		pairs := strings.Split(cookieStr, ";")
		for _, pair := range pairs {
			pair = strings.TrimSpace(pair)
			if pair == "" {
				continue
			}
			idx := strings.Index(pair, "=")
			if idx > 0 {
				name := strings.TrimSpace(pair[:idx])
				value := strings.TrimSpace(pair[idx+1:])
				if name != "" {
					cookieJar.SetCookies(u, []*http.Cookie{{Name: name, Value: value, Path: "/", Domain: ".music.163.com"}})
					count++
				}
			}
		}
	}

	if count == 0 {
		writeError(w, "未能解析任何 cookies")
		return
	}

	// 自动补全必需的 cookies（__csrf、NMTID、os）
	existing := make(map[string]bool)
	for _, c := range cookieJar.Cookies(u) {
		existing[c.Name] = true
	}
	var extraCookies []*http.Cookie
	if !existing["__csrf"] {
		extraCookies = append(extraCookies, &http.Cookie{Name: "__csrf", Value: randomHex(32), Path: "/", Domain: ".music.163.com"})
	}
	if !existing["NMTID"] {
		extraCookies = append(extraCookies, &http.Cookie{Name: "NMTID", Value: randomString(22), Path: "/", Domain: ".music.163.com"})
	}
	if !existing["os"] {
		extraCookies = append(extraCookies, &http.Cookie{Name: "os", Value: "pc", Path: "/", Domain: ".music.163.com"})
	}
	if len(extraCookies) > 0 {
		cookieJar.SetCookies(u, extraCookies)
		count += len(extraCookies)
		fmt.Printf("[web-login] 自动补全 %d 个 cookies\n", len(extraCookies))
	}

	// 保存到文件
	saveCookiesToFile()
	fmt.Printf("[web-login] 导入 %d 个 cookies，已保存\n", count)

	// 验证登录状态
	data, err := weapiPost("/weapi/w/nuser/account/get", "{}")
	loggedIn := false
	nickname := ""
	if err == nil {
		var resp struct {
			Code int `json:"code"`
			Profile struct {
				Nickname string `json:"nickname"`
			} `json:"profile"`
		}
		if json.Unmarshal(data, &resp) == nil && resp.Code == 200 && resp.Profile.Nickname != "" {
			loggedIn = true
			nickname = resp.Profile.Nickname
		}
	}

	writeJSON(w, map[string]interface{}{
		"code":     200,
		"count":    count,
		"loggedIn": loggedIn,
		"nickname": nickname,
		"message":  func() string {
			if loggedIn {
				return "导入成功！已登录为：" + nickname
			}
			return "已导入 " + fmt.Sprintf("%d", count) + " 个 cookies，但未检测到登录状态，请确认 cookies 包含 MUSIC_U"
		}(),
	})
}

func handleWebPull(w http.ResponseWriter, r *http.Request) {
	u, _ := url.Parse("https://music.163.com")
	cookies := cookieJar.Cookies(u)
	cookieMap := make(map[string]string)
	for _, c := range cookies {
		cookieMap[c.Name] = c.Value
	}
	writeJSON(w, map[string]interface{}{
		"code":    200,
		"cookies": cookieMap,
	})
}

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

	mu.Lock()
	resp, err := client.Do(req)
	mu.Unlock()
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
	preview := string(data)
	if len(preview) > 200 {
		preview = preview[:200]
	}
	fmt.Printf("[weapiPost] path=%s status=%d body=%s\n", path, resp.StatusCode, preview)
	return data, nil
}

// 简单 GET（用于不需要加密的接口）
func simpleGet(path string) ([]byte, error) {
	req, _ := http.NewRequest("GET", baseAPI+path, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Accept", "application/json, text/plain, */*")
	req.Header.Set("Accept-Language", "zh-CN,zh;q=0.9,en;q=0.8")
	mu.Lock()
	resp, err := client.Do(req)
	mu.Unlock()
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
	body := fmt.Sprintf(`{"ids":"[%s]","level":"standard","encodeType":"aac"}`, id)
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

func handleQrKey(w http.ResponseWriter, r *http.Request) {
	data, err := weapiPost("/weapi/login/qrcode/unikey", `{"type":1}`)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleQrCreate(w http.ResponseWriter, r *http.Request) {
	key := r.URL.Query().Get("key")
	if key == "" {
		writeError(w, "缺少 key")
		return
	}
	// 二维码内容：网易云登录 URL
	qrContent := "https://music.163.com/login?codekey=" + key
	// 生成二维码 PNG
	png, err := qrcode.Encode(qrContent, qrcode.Medium, 256)
	if err != nil {
		writeError(w, "生成二维码失败: "+err.Error())
		return
	}
	// 转 base64
	base64Img := base64.StdEncoding.EncodeToString(png)
	writeJSON(w, map[string]interface{}{
		"code":  200,
		"qrimg": "data:image/png;base64," + base64Img,
	})
}

func handleQrCheck(w http.ResponseWriter, r *http.Request) {
	key := r.URL.Query().Get("key")
	body := fmt.Sprintf(`{"key":"%s","type":1}`, key)
	// 官方文档要求：调用务必带上时间戳，防止缓存
	path := fmt.Sprintf("/weapi/login/qrcode/client/login?timestamp=%d", time.Now().UnixMilli())
	data, err := weapiPost(path, body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleCaptchaSent(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	if phone == "" {
		writeError(w, "缺少 phone")
		return
	}
	ctcode := r.URL.Query().Get("ctcode")
	if ctcode == "" {
		ctcode = "86"
	}
	// 网易云 weapi 接口需要 csrf_token 参数
	body := fmt.Sprintf(`{"phone":"%s","ctcode":"%s","csrf_token":""}`, phone, ctcode)
	fmt.Printf("[captcha/sent] phone=%s ctcode=%s body=%s\n", phone, ctcode, body)
	data, err := weapiPost("/weapi/sms/captcha/sent", body)
	if err != nil {
		fmt.Printf("[captcha/sent] error: %v\n", err)
		writeError(w, err.Error())
		return
	}
	fmt.Printf("[captcha/sent] response: %s\n", string(data))
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleLoginCellphone(w http.ResponseWriter, r *http.Request) {
	phone := r.URL.Query().Get("phone")
	captcha := r.URL.Query().Get("captcha")
	if phone == "" || captcha == "" {
		writeError(w, "缺少 phone 或 captcha")
		return
	}
	body := fmt.Sprintf(`{"phone":"%s","captcha":"%s","rememberLogin":"true","csrf_token":""}`, phone, captcha)
	data, err := weapiPost("/weapi/login/cellphone", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
	// 登录成功后保存 cookies 到文件
	var resp struct {
		Code int `json:"code"`
	}
	if json.Unmarshal(data, &resp) == nil && resp.Code == 200 {
		saveCookiesToFile()
		fmt.Println("[cookies] 登录成功，已保存 cookies 到 cookies.json")
	}
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

// ── 下载和缓存 ──

func handleCache(w http.ResponseWriter, r *http.Request) {
	id := r.URL.Query().Get("id")
	if id == "" {
		writeError(w, "缺少 id")
		return
	}
	// 检查缓存
	cacheFile := filepath.Join(cacheDir, id+".mp3")
	if _, err := os.Stat(cacheFile); err == nil {
		writeJSON(w, map[string]interface{}{"code": 200, "path": cacheFile, "cached": true})
		return
	}
	// 获取播放地址并下载
	body := fmt.Sprintf(`{"ids":"[%s]","level":"standard","encodeType":"aac"}`, id)
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
		writeError(w, "歌曲无可用播放地址（可能需要 VIP）")
		return
	}
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
	body := fmt.Sprintf(`{"ids":"[%s]","level":"standard","encodeType":"aac"}`, id)
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

// 下载文件
func downloadFile(url, dest string) error {
	os.MkdirAll(filepath.Dir(dest), 0755)
	resp, err := http.Get(url)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return fmt.Errorf("HTTP %d", resp.StatusCode)
	}
	out, err := os.Create(dest)
	if err != nil {
		return err
	}
	defer out.Close()
	_, err = io.Copy(out, resp.Body)
	return err
}

// 清理文件名中的非法字符
func sanitizeFilename(name string) string {
	replacer := strings.NewReplacer("/", "_", "\\", "_", ":", "_", "*", "_", "?", "_", "\"", "_", "<", "_", ">", "_", "|", "_")
	return strings.TrimSpace(replacer.Replace(name))
}
