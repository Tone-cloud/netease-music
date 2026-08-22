package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/cookiejar"
	"net/url"
	"os"
	"path/filepath"
	"strings"
	"sync"
)

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

func init() {
	cookieJar, _ = cookiejar.New(nil)
	client = &http.Client{Jar: cookieJar}
	os.MkdirAll(cacheDir, 0755)
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
	http.HandleFunc("/login/status", handleLoginStatus)
	http.HandleFunc("/logout", handleLogout)
	http.HandleFunc("/user/playlist", handleUserPlaylist)
	http.HandleFunc("/download", handleDownload)
	http.HandleFunc("/cache", handleCache)
	http.HandleFunc("/downloads", handleDownloads)

	fmt.Println("NeteaseMusic server listening on", listenAddr)
	http.ListenAndServe(listenAddr, nil)
}

// ── 工具函数 ──

func writeJSON(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	json.NewEncoder(w).Encode(data)
}

func writeError(w http.ResponseWriter, msg string) {
	writeJSON(w, map[string]interface{}{"code": 500, "msg": msg})
}

// weapi POST 请求
func weapiPost(path, jsonStr string) ([]byte, error) {
	params, encSecKey := weapiEncrypt(jsonStr)
	form := url.Values{}
	form.Set("params", params)
	form.Set("encSecKey", encSecKey)

	req, _ := http.NewRequest("POST", baseAPI+path, strings.NewReader(form.Encode()))
	req.Header.Set("Content-Type", "application/x-www-form-urlencoded")
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
	req.Header.Set("Origin", "https://music.163.com")

	mu.Lock()
	resp, err := client.Do(req)
	mu.Unlock()
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	return io.ReadAll(resp.Body)
}

// 简单 GET（用于不需要加密的接口）
func simpleGet(path string) ([]byte, error) {
	req, _ := http.NewRequest("GET", baseAPI+path, nil)
	req.Header.Set("User-Agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36")
	req.Header.Set("Referer", "https://music.163.com/")
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
	data, err := simpleGet("/weapi/login/qrcode/unikey?type=1")
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleQrCreate(w http.ResponseWriter, r *http.Request) {
	key := r.URL.Query().Get("key")
	qrimg := r.URL.Query().Get("qrimg")
	body := fmt.Sprintf(`{"key":"%s","type":1,"qrimg":%s}`, key, qrimg)
	data, err := weapiPost("/weapi/login/qrcode/create", body)
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
}

func handleQrCheck(w http.ResponseWriter, r *http.Request) {
	key := r.URL.Query().Get("key")
	data, err := simpleGet("/weapi/login/qrcode/client/login?key=" + key + "&type=1")
	if err != nil {
		writeError(w, err.Error())
		return
	}
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.Write(data)
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
