package main

import (
	"bytes"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"math/big"
	"strings"
)

const (
	presetKey = "0CoJUm6Qyw8W8jud"
	iv        = "0102030405060708"
	pubKey    = "010001"
	modulus   = "00e0b509f6259df8642dbc35662901477df22677ec152b5ff68ace615bb7b725152b3ab17a876aea8a5aa76d2e417629ec4ee341f56135fccf695280104e0312ecbda92557c93870114af6c9d05c4f7f0c3685b7a46bee255932575cce10b424d813cfe4875d3e82047b97ddef52741d546b8e289dc6935b3ece0462db0a22b8e7"
)

// 生成随机 16 位字符串
func randomString(n int) string {
	const chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	b := make([]byte, n)
	for i := range b {
		num, _ := rand.Int(rand.Reader, big.NewInt(int64(len(chars))))
		b[i] = chars[num.Int64()]
	}
	return string(b)
}

// AES-128-CBC 加密，PKCS7 填充，Base64 输出
func aesEncrypt(text, key string) string {
	block, _ := aes.NewCipher([]byte(key))
	pad := block.BlockSize() - len(text)%block.BlockSize()
	text += strings.Repeat(string(rune(pad)), pad)
	blockMode := cipher.NewCBCEncrypter(block, []byte(iv))
	out := make([]byte, len(text))
	blockMode.CryptBlocks(out, []byte(text))
	return base64Encode(out)
}

// 简单 Base64 编码（避免 import 冲突）
func base64Encode(src []byte) string {
	const table = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
	var buf bytes.Buffer
	for i := 0; i < len(src); i += 3 {
		var b [3]byte
		var n int
		for j := 0; j < 3 && i+j < len(src); j++ {
			b[j] = src[i+j]
			n++
		}
		buf.WriteByte(table[b[0]>>2])
		buf.WriteByte(table[(b[0]&0x03)<<4|b[1]>>4])
		if n > 1 {
			buf.WriteByte(table[(b[1]&0x0f)<<2|b[2]>>6])
		} else {
			buf.WriteByte('=')
		}
		if n > 2 {
			buf.WriteByte(table[b[2]&0x3f])
		} else {
			buf.WriteByte('=')
		}
	}
	return buf.String()
}

// RSA 加密（网易云方式：反转字符串 + 模幂）
func rsaEncrypt(text string) string {
	// 反转
	runes := []rune(text)
	for i, j := 0, len(runes)-1; i < j; i, j = i+1, j-1 {
		runes[i], runes[j] = runes[j], runes[i]
	}
	reversed := string(runes)
	// 转十六进制
	hex := ""
	for _, c := range reversed {
		hex += string(big.NewInt(int64(c)).Text(16))
	}
	// 模幂
	m := new(big.Int)
	m.SetString(modulus, 16)
	e := new(big.Int)
	e.SetString(pubKey, 16)
	x := new(big.Int)
	x.SetString(hex, 16)
	result := new(big.Int).Exp(x, e, m)
	// 补零到 256 位
	return strings.Repeat("0", 256-len(result.Text(16))) + result.Text(16)
}

// Weapi 加密：返回 params 和 encSecKey
func weapiEncrypt(jsonStr string) (params, encSecKey string) {
	secKey := randomString(16)
	params = aesEncrypt(jsonStr, presetKey)
	params = aesEncrypt(params, secKey)
	encSecKey = rsaEncrypt(secKey)
	return
}
