import QtQuick 2.12
import "../components"

Rectangle {
    id: localPage
    objectName: "local"
    width: Theme.screenWidth
    height: Theme.screenHeight
    color: Theme.bgPrimary

    signal backClicked()
    signal playLocal(var file)
    signal loaded(var item)

    property var files: []
    property var groups: []        // 按歌单（目录）分组后的数据
    property var expanded: ({})    // 哪些分组被展开（默认全部折叠）
    property var rows: []          // 实际显示的列表（标题行 + 展开组内的歌曲）
    property bool loading: false
    property string selectedPath: ""

    Component.onCompleted: {
        localPage.loaded(localPage)
        localPage.refresh()
    }

    // 顶部栏
    Rectangle {
        id: topBar
        width: parent.width
        height: Theme.titleBarHeight
        color: Theme.bgSecondary

        Rectangle {
            width: parent.width
            height: 1
            anchors.bottom: parent.bottom
            color: Theme.borderLight
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            spacing: 4

            Rectangle {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: backMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall

                Text {
                    anchors.centerIn: parent
                    text: "<"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                    font.family: Theme.fontFamily
                }

                MouseArea {
                    id: backMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: localPage.backClicked()
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "本地音乐"
                color: Theme.textPrimary
                font.pixelSize: Theme.fontNormal
                font.bold: true
                font.family: Theme.fontFamily
            }

            Item { width: 1 }

            // 刷新按钮
            Rectangle {
                width: 22
                height: 22
                anchors.verticalCenter: parent.verticalCenter
                color: refreshMouse.pressed ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
                radius: Theme.radiusSmall

                Text {
                    anchors.centerIn: parent
                    text: "↻"
                    color: Theme.primary
                    font.pixelSize: Theme.fontNormal
                    font.bold: true
                }

                MouseArea {
                    id: refreshMouse
                    anchors.fill: parent
                    anchors.margins: -3
                    onClicked: localPage.refresh()
                }
            }
        }
    }

    // 统计信息
    Rectangle {
        id: statsBar
        width: parent.width
        height: 20
        color: Theme.bgSecondary
        anchors.top: topBar.bottom

        Text {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            text: localPage.loading ? "扫描中..." : "共 " + localPage.files.length + " 首"
            color: Theme.textTertiary
            font.pixelSize: Theme.fontTiny
            font.family: Theme.fontFamily
        }
    }

    // 空状态
    Text {
        anchors.centerIn: parent
        text: localPage.loading ? "扫描中..." : "暂无本地音乐\n下载的歌曲会显示在这里"
        color: Theme.textTertiary
        font.pixelSize: Theme.fontSmall
        font.family: Theme.fontFamily
        horizontalAlignment: Text.AlignHCenter
        visible: localPage.files.length === 0
    }

    // 文件列表
    ListView {
        id: fileList
        anchors.top: statsBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        clip: true
        cacheBuffer: 200
        visible: localPage.files.length > 0
        model: localPage.rows

        delegate: Rectangle {
            width: fileList.width
            height: modelData.isHeader === true ? 26 : 32
            color: modelData.isHeader === true ? Theme.bgSecondary
                                               : (index % 2 === 0 ? Theme.bgPrimary : Theme.bgCard)

            scale: fileMouse.pressed ? 0.98 : 1.0
            Behavior on scale { NumberAnimation { duration: 60 } }

            // 歌单分组标题
            Row {
                visible: modelData.isHeader === true
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 6

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.expanded === true ? "▾" : "▸"
                    color: Theme.primary
                    font.pixelSize: Theme.fontTiny
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.title || ""
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                    font.family: Theme.fontFamily
                    elide: Text.ElideRight
                    width: parent.width - 60
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: (modelData.count || 0) + " 首"
                    color: Theme.textTertiary
                    font.pixelSize: Theme.fontTiny
                    font.family: Theme.fontFamily
                }
            }

            Row {
                visible: modelData.isHeader !== true
                anchors.fill: parent
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                spacing: 8

                // 音乐图标
                Rectangle {
                    width: 24
                    height: 24
                    radius: 4
                    color: Theme.withAlpha(Theme.primary, 0.15)
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "♪"
                        color: Theme.primary
                        font.pixelSize: Theme.fontSmall
                        font.bold: true
                    }
                }

                // 文件信息
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 70
                    spacing: 0

                    Text {
                        text: modelData.name
                        color: Theme.textPrimary
                        font.pixelSize: Theme.fontSmall
                        font.family: Theme.fontFamily
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Row {
                        spacing: 4
                        Text {
                            text: modelData.sizeStr + "  " + modelData.ext.toUpperCase()
                            color: Theme.textTertiary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }
                        Text {
                            visible: modelData.lrc === true
                            text: "词"
                            color: Theme.primary
                            font.pixelSize: Theme.fontTiny
                            font.bold: true
                            font.family: Theme.fontFamily
                        }
                    }
                }

                // 删除按钮
                Rectangle {
                    width: 24
                    height: 24
                    radius: 4
                    color: delMouse.pressed ? Theme.withAlpha(Theme.error, 0.3) : "transparent"
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        anchors.centerIn: parent
                        text: "✕"
                        color: Theme.error
                        font.pixelSize: Theme.fontTiny
                        font.bold: true
                    }

                    MouseArea {
                        id: delMouse
                        anchors.fill: parent
                        anchors.margins: -3
                        onClicked: {
                            localPage.selectedPath = modelData.path
                            deleteConfirm.visible = true
                        }
                    }
                }
            }

            MouseArea {
                id: fileMouse
                anchors.fill: parent
                onClicked: {
                    if (modelData.isHeader === true) localPage.toggleGroup(modelData.folder)
                    else localPage.playLocal(modelData)
                }
            }
        }
    }

    // 删除确认弹窗
    Rectangle {
        id: deleteConfirm
        width: parent.width
        height: parent.height
        color: "#80000000"
        visible: false
        z: 100

        Rectangle {
            width: 240
            height: 80
            radius: 8
            color: Theme.bgCard
            anchors.centerIn: parent
            border.color: Theme.borderLight
            border.width: 1

            Column {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Text {
                    text: "确定删除这首歌曲？"
                    color: Theme.textPrimary
                    font.pixelSize: Theme.fontSmall
                    font.family: Theme.fontFamily
                    anchors.horizontalCenter: parent.horizontalCenter
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 16

                    Rectangle {
                        width: 70
                        height: 24
                        radius: 4
                        color: Theme.bgTertiary

                        Text {
                            anchors.centerIn: parent
                            text: "取消"
                            color: Theme.textSecondary
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: deleteConfirm.visible = false
                        }
                    }

                    Rectangle {
                        width: 70
                        height: 24
                        radius: 4
                        color: Theme.error

                        Text {
                            anchors.centerIn: parent
                            text: "删除"
                            color: "white"
                            font.pixelSize: Theme.fontTiny
                            font.family: Theme.fontFamily
                            font.bold: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                deleteConfirm.visible = false
                                localPage.deleteFile(localPage.selectedPath)
                            }
                        }
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: deleteConfirm.visible = false
        }
    }

    // ── 函数 ──
    function refresh() {
        localPage.loading = true
        ApiClient.localList(function(d) {
            localPage.loading = false
            if (d.code === 200 && d.files) {
                localPage.files = d.files
                localPage.groups = localPage.buildGroups(d.files)
                localPage.rows = localPage.buildRows()
            }
        }, function(e) {
            localPage.loading = false
            console.log("[local] 扫描失败:", e)
        })
    }

    // 分组标题：取目录最后一段；netease 根目录归为「单曲」
    function folderTitle(folder) {
        if (!folder || folder.length === 0) return "本地音乐"
        var parts = String(folder).split("/")
        var last = parts[parts.length - 1]
        if (last === "netease") return "单曲 / 未分类"
        return last
    }

    // 按目录（歌单）分组，组内按下载时记录的歌单顺序（index）排列
    function buildGroups(files) {
        var groups = ({})
        var order = []
        for (var i = 0; i < files.length; i++) {
            var f = files[i]
            var key = f.folder || ""
            if (!groups[key]) {
                groups[key] = []
                order.push(key)
            }
            groups[key].push(f)
        }
        order.sort(function(a, b) {
            var ra = (a === "" || a === "netease") ? 0 : 1
            var rb = (b === "" || b === "netease") ? 0 : 1
            if (ra !== rb) return ra - rb
            return String(a).localeCompare(String(b))
        })
        var rows = []
        for (var g = 0; g < order.length; g++) {
            var key2 = order[g]
            var arr = groups[key2]
            // 有歌单顺序用顺序；老文件没有顺序则按下载时间（modTime）排
            arr.sort(function(a, b) {
                var ka = (a.index && a.index > 0) ? a.index : (1000000 + (a.modTime || 0))
                var kb = (b.index && b.index > 0) ? b.index : (1000000 + (b.modTime || 0))
                if (ka !== kb) return ka - kb
                return String(a.name).localeCompare(String(b.name))
            })
            rows.push({ key: key2, title: localPage.folderTitle(key2), songs: arr, count: arr.length })
        }
        return rows
    }

    // 根据展开状态生成显示列表：默认只显示各歌单标题（折叠），点标题才展开
    function buildRows() {
        var rows = []
        for (var g = 0; g < localPage.groups.length; g++) {
            var grp = localPage.groups[g]
            var open = localPage.expanded[grp.key] === true
            rows.push({ isHeader: true, title: grp.title, count: grp.count,
                        folder: grp.key, expanded: open })
            if (!open) continue
            for (var j = 0; j < grp.songs.length; j++) {
                var item = grp.songs[j]
                item.isHeader = false
                rows.push(item)
            }
        }
        return rows
    }

    // 展开/折叠一个歌单分组
    function toggleGroup(key) {
        var next = ({})
        for (var k in localPage.expanded) next[k] = localPage.expanded[k]
        next[key] = !(localPage.expanded[key] === true)
        localPage.expanded = next
        localPage.rows = localPage.buildRows()
    }

    function deleteFile(path) {
        ApiClient.localDelete(path, function(d) {
            if (d.code === 200) {
                console.log("[local] 已删除:", path)
                localPage.refresh()
            }
        }, function(e) {
            console.log("[local] 删除失败:", e)
        })
    }
}
