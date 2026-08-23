import QtQuick 2.12
import "../components"

Rectangle {
    id: root
    objectName: "phoneLogin"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal loginSuccess(var user)
    signal switchToQrLogin()

    property string phone: ""
    property string captcha: ""
    property int countdown: 0
    property string status: ""

    // 虚拟键盘
    VirtualKeyboardInput {
        id: phoneKeyboard
        onAccepted: {
            root.phone = content.trim()
            phoneDisplay.text = root.phone
        }
    }

    VirtualKeyboardInput {
        id: captchaKeyboard
        onAccepted: {
            root.captcha = content.trim()
            captchaDisplay.text = root.captcha
        }
    }

    Timer {
        id: countdownTimer
        interval: 1000
        repeat: true
        onTriggered: {
            root.countdown--
            if (root.countdown <= 0) countdownTimer.stop()
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 6
        spacing: 6

        // 顶部栏
        Row {
            width: parent.width
            spacing: Theme.spacingS
            Rectangle {
                width: 22; height: 22; color: Theme.bgCard; radius: Theme.radiusS
                Text { anchors.centerIn: parent; text: "<"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true }
                MouseArea { anchors.fill: parent; onClicked: root.backClicked() }
            }
            Text { anchors.verticalCenter: parent.verticalCenter; text: "手机登录"; color: Theme.textPrimary; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
        }

        // 手机号输入
        Rectangle {
            width: parent.width; height: 28
            color: Theme.bgCard; radius: Theme.radiusM
            Text {
                id: phoneDisplay
                anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
                text: root.phone || "请输入手机号"
                color: root.phone ? Theme.textPrimary : Theme.textMuted
                font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
            }
            MouseArea { anchors.fill: parent; onClicked: phoneKeyboard.open(root.phone) }
        }

        // 验证码输入 + 发送按钮
        Row {
            width: parent.width; spacing: Theme.spacingS
            Rectangle {
                width: parent.width - 64 - Theme.spacingS; height: 28
                color: Theme.bgCard; radius: Theme.radiusM
                Text {
                    id: captchaDisplay
                    anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 10
                    text: root.captcha || "请输入验证码"
                    color: root.captcha ? Theme.textPrimary : Theme.textMuted
                    font.pixelSize: Theme.fontNormal; font.family: Theme.fontFamily
                }
                MouseArea { anchors.fill: parent; onClicked: captchaKeyboard.open(root.captcha) }
            }
            Rectangle {
                width: 64; height: 28
                color: root.countdown > 0 ? Theme.bgSecondary : (root.phone.length === 11 ? Theme.accent : Theme.bgSecondary)
                radius: Theme.radiusM
                Text {
                    anchors.centerIn: parent
                    text: root.countdown > 0 ? root.countdown + "s" : "发送"
                    color: "white"; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.countdown <= 0 && root.phone.length === 11
                    onClicked: sendCaptcha()
                }
            }
        }

        // 登录按钮
        Rectangle {
            width: parent.width; height: 30
            color: (root.phone.length === 11 && root.captcha.length === 6) ? Theme.accent : Theme.bgSecondary
            radius: Theme.radiusM
            Text { anchors.centerIn: parent; text: "登录"; color: "white"; font.pixelSize: Theme.fontNormal; font.bold: true; font.family: Theme.fontFamily }
            MouseArea {
                anchors.fill: parent
                enabled: root.phone.length === 11 && root.captcha.length === 6
                onClicked: doLogin()
            }
        }

        // 状态提示
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.status
            color: Theme.textMuted; font.pixelSize: Theme.fontTiny; font.family: Theme.fontFamily
        }

        // 切换到二维码登录
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "二维码登录"
            color: Theme.accent; font.pixelSize: Theme.fontSmall; font.family: Theme.fontFamily
            MouseArea { anchors.fill: parent; onClicked: root.switchToQrLogin() }
        }
    }

    function sendCaptcha() {
        root.status = "发送中..."
        ApiClient.captchaSent(root.phone, function(d) {
            console.log("[PhoneLogin] captchaSent response: " + JSON.stringify(d))
            if (d.code === 200) {
                root.status = "验证码已发送"
                root.countdown = 60
                countdownTimer.start()
            } else {
                root.status = "发送失败: " + (d.message || d.code)
            }
        }, function(e) {
            root.status = "网络错误: " + e
        })
    }

    function doLogin() {
        root.status = "登录中..."
        ApiClient.loginCellphone(root.phone, root.captcha, function(d) {
            console.log("[PhoneLogin] login response: " + JSON.stringify(d).substring(0, 300))
            if (d.code === 200) {
                root.status = "登录成功"
                var profile = d.profile || (d.account && d.profile) || {}
                root.loginSuccess(profile)
            } else if (d.code === 502) {
                root.status = "验证码错误"
            } else if (d.code === 509) {
                root.status = "验证码过期"
            } else {
                root.status = "登录失败: " + (d.message || d.code)
            }
        }, function(e) {
            root.status = "网络错误: " + e
        })
    }
}
