import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "login"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal loginSuccess(var user)
    signal switchToPhoneLogin()

    property string qrKey: ""
    property string qrImage: ""
    property string loginStatus: "等待扫码"
    property bool polling: false

    // 顶部栏
    Rectangle {
        width: parent.width; height: 26
        color: Theme.bgSecondary
        Row {
            anchors.fill: parent; anchors.leftMargin: 6; spacing: 4
            Rectangle {
                width: 22; height: 22; anchors.verticalCenter: parent.verticalCenter
                color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "登录"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
        }
        // 右上角手机登录按钮
        Text {
            anchors.right: parent.right; anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: "手机登录"
            color: Theme.accent; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
            MouseArea { anchors.fill: parent; anchors.margins: -4; onClicked: root.switchToPhoneLogin() }
        }
    }

    Column {
        anchors.centerIn: parent; spacing: Theme.spacingS
        // 二维码区域
        Rectangle {
            width: 70; height: 70
            color: "white"; radius: Theme.radiusM
            border.color: Theme.divider; border.width: 1
            Text {
                anchors.centerIn: parent
                text: root.qrImage ? "二维码" : "加载中..."
                color: Theme.textMuted; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
            }
            // 如果有 base64 图片数据，可以用 Image 显示
            Image {
                anchors.fill: parent; anchors.margins: 4
                fillMode: Image.PreserveAspectFit
                source: root.qrImage ? "data:image/png;base64," + root.qrImage : ""
                visible: root.qrImage.length > 0
                asynchronous: true
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.loginStatus
            color: Theme.textSecondary; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "使用网易云音乐 APP 扫码登录"
            color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily
        }

        Rectangle {
            width: 56; height: 22
            color: Theme.accent; radius: Theme.radiusM
            anchors.horizontalCenter: parent.horizontalCenter
            Text { anchors.centerIn: parent; text: "刷新"; color: "white"; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily }
            MouseArea { anchors.fill: parent; onClicked: startLogin() }
        }
    }

    // 登录状态轮询
    Timer {
        id: pollTimer
        interval: 3000
        repeat: true
        onTriggered: checkLoginStatus()
    }

    function startLogin() {
        root.loginStatus = "获取二维码..."
        root.qrImage = ""
        console.log("[Login] startLogin, baseUrl=" + ApiClient.baseUrl)
        ApiClient.loginQrKey(function(d) {
            console.log("[Login] qrKey response: " + JSON.stringify(d))
            if (d && d.code === 200 && d.unikey) {
                root.qrKey = d.unikey
                createQr()
            } else {
                root.loginStatus = "获取 key 失败: " + (d ? JSON.stringify(d) : "null")
            }
        }, function(e) {
            console.log("[Login] qrKey error: " + e)
            root.loginStatus = "网络错误: " + e
        })
    }

    function createQr() {
        console.log("[Login] createQr, key=" + root.qrKey)
        ApiClient.loginQrCreate(root.qrKey, function(d) {
            console.log("[Login] qrCreate response: " + JSON.stringify(d).substring(0, 300))
            if (d && d.code === 200) {
                if (d.qrimg) {
                    // 去掉 data:image/png;base64, 前缀
                    var img = d.qrimg
                    if (img.indexOf(",") >= 0) img = img.substring(img.indexOf(",") + 1)
                    root.qrImage = img
                    console.log("[Login] qrImage length=" + img.length)
                } else {
                    console.log("[Login] no qrimg field in response")
                }
                root.loginStatus = "请扫码"
                root.polling = true
                pollTimer.start()
            } else {
                root.loginStatus = "生成二维码失败: " + (d ? JSON.stringify(d).substring(0, 100) : "null")
            }
        }, function(e) {
            console.log("[Login] qrCreate error: " + e)
            root.loginStatus = "网络错误: " + e
        })
    }

    function checkLoginStatus() {
        if (!root.qrKey) return
        ApiClient.loginQrCheck(root.qrKey, function(d) {
            console.log("[Login] qrCheck response: " + JSON.stringify(d).substring(0, 300))
            if (d.code === 803) {
                // 官方文档：803 为授权登录成功(803 状态码下会返回 cookies)
                root.polling = false
                pollTimer.stop()
                root.loginStatus = "登录成功"
                console.log("[Login] login success (code 803)")
                // 获取用户信息
                ApiClient.loginStatus(function(ud) {
                    console.log("[Login] loginStatus response: " + JSON.stringify(ud).substring(0, 300))
                    if (ud.code === 200 && ud.data && ud.data.profile) {
                        root.loginSuccess(ud.data.profile)
                    } else if (ud.profile) {
                        root.loginSuccess(ud.profile)
                    } else if (ud.account && ud.profile) {
                        root.loginSuccess(ud.profile)
                    } else {
                        root.loginSuccess({ nickname: "用户" })
                    }
                }, function(e) {
                    console.log("[Login] loginStatus error: " + e)
                    root.loginSuccess({ nickname: "用户" })
                })
            } else if (d.code === 800) {
                root.loginStatus = "二维码过期，请刷新"
                root.polling = false
                pollTimer.stop()
            } else if (d.code === 801) {
                root.loginStatus = "等待扫码..."
            } else if (d.code === 802) {
                root.loginStatus = "扫码成功，等待确认"
            } else if (d.code === 8821) {
                root.loginStatus = "登录被风控，请刷新重试"
                root.polling = false
                pollTimer.stop()
            }
        }, function(e) {
            console.log("[Login] qrCheck error: " + e)
        })
    }

    Component.onCompleted: startLogin()
}
