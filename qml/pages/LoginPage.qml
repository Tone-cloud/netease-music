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
    }

    Column {
        anchors.centerIn: parent; spacing: Theme.spacingM
        // 二维码区域
        Rectangle {
            width: 80; height: 80
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
            width: 60; height: 24
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
        ApiClient.loginQrKey(function(d) {
            if (d.code === 200 && d.data && d.data.unikey) {
                root.qrKey = d.data.unikey
                createQr()
            } else {
                root.loginStatus = "获取 key 失败"
            }
        }, function(e) { root.loginStatus = "网络错误: " + e })
    }

    function createQr() {
        ApiClient.loginQrCreate(root.qrKey, function(d) {
            if (d.code === 200 && d.data) {
                if (d.data.qrimg) {
                    // 去掉 data:image/png;base64, 前缀
                    var img = d.data.qrimg
                    if (img.indexOf(",") >= 0) img = img.substring(img.indexOf(",") + 1)
                    root.qrImage = img
                }
                root.loginStatus = "请扫码"
                root.polling = true
                pollTimer.start()
            } else {
                root.loginStatus = "生成二维码失败"
            }
        }, function(e) { root.loginStatus = "网络错误: " + e })
    }

    function checkLoginStatus() {
        if (!root.qrKey) return
        ApiClient.loginQrCheck(root.qrKey, function(d) {
            if (d.code === 803) {
                // 登录成功
                root.polling = false
                pollTimer.stop()
                root.loginStatus = "登录成功"
                // 获取用户信息
                ApiClient.loginStatus(function(ud) {
                    if (ud.code === 200 && ud.data && ud.data.profile) {
                        root.loginSuccess(ud.data.profile)
                    } else {
                        root.loginSuccess({ nickname: "用户" })
                    }
                }, null)
            } else if (d.code === 800) {
                root.loginStatus = "二维码过期，请刷新"
                root.polling = false
                pollTimer.stop()
            } else if (d.code === 801) {
                root.loginStatus = "等待扫码..."
            } else if (d.code === 802) {
                root.loginStatus = "扫码成功，等待确认"
            }
        }, null)
    }

    Component.onCompleted: startLogin()
}
