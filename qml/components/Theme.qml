pragma Singleton
import QtQuick 2.12

QtObject {
    id: theme

    // 屏幕尺寸（词典笔 320x170）
    readonly property int screenWidth: 320
    readonly property int screenHeight: 170

    // 颜色 - 网易云红黑风格
    readonly property color bgPrimary: "#1a1a1a"
    readonly property color bgSecondary: "#242424"
    readonly property color bgCard: "#2e2e2e"
    readonly property color accent: "#C20C0C"       // 网易云红
    readonly property color accentSoft: "#E63946"
    readonly property color textPrimary: "#FFFFFF"
    readonly property color textSecondary: "#B0B0B0"
    readonly property color textMuted: "#666666"
    readonly property color divider: "#333333"
    readonly property color success: "#4CAF50"
    readonly property color warning: "#FF9800"
    readonly property color error: "#F44336"

    // 字体
    readonly property int fontTiny: 8
    readonly property int fontSmall: 10
    readonly property int fontNormal: 12
    readonly property int fontLarge: 14
    readonly property int fontXLarge: 16

    // 间距
    readonly property int spacingXS: 2
    readonly property int spacingS: 4
    readonly property int spacingM: 6
    readonly property int spacingL: 8
    readonly property int spacingXL: 12

    // 圆角
    readonly property int radiusS: 3
    readonly property int radiusM: 5
    readonly property int radiusL: 8

    // 中文字体
    readonly property string fontFamily: (typeof qmlGlobal !== "undefined" && qmlGlobal.fontFamilyZhCn) ? qmlGlobal.fontFamilyZhCn : "Microsoft YaHei"
}
