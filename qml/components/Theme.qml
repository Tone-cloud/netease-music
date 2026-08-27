pragma Singleton
import QtQuick 2.12

Item {
    id: theme

    FontLoader {
        id: appFont
        source: "../msyh.ttf"
    }

    // 屏幕尺寸（词典笔 320x170）
    readonly property int screenWidth: 320
    readonly property int screenHeight: 170

    // ── 主题色（网易云红）──
    readonly property color primary: "#C20C0C"
    readonly property color primaryLight: "#E63946"
    readonly property color primaryDark: "#8B0000"
    readonly property color primaryGlow: "#1AC20C0C"
    readonly property color accent: "#C20C0C"

    // ── 背景色（深色主题，bili风格）──
    readonly property color bgPrimary: "#0D0D0D"
    readonly property color bgSecondary: "#181818"
    readonly property color bgTertiary: "#242424"
    readonly property color bgCard: "#1E1E1E"
    readonly property color bgCardHover: "#2A2A2A"
    readonly property color bgInput: "#2C2C2C"
    readonly property color bgOverlay: "#CC000000"

    // ── 文字颜色 ──
    readonly property color textPrimary: "#F0F0F0"
    readonly property color textSecondary: "#A0A0A0"
    readonly property color textTertiary: "#666666"
    readonly property color textOnPrimary: "#FFFFFF"
    readonly property color textLink: "#E63946"

    // ── 边框/分割线 ──
    readonly property color border: "#2E2E2E"
    readonly property color borderLight: "#3A3A3A"
    readonly property color divider: "#1F1F1F"

    // ── 状态色 ──
    readonly property color error: "#FF5252"
    readonly property color success: "#66BB6A"
    readonly property color warning: "#FFA726"

    // ── 缩放系数（320x170 小屏显示）──
    readonly property real fontScale: 1.5

    function scaledFont(size) {
        return Math.round(size * fontScale)
    }

    // ── 字体尺寸（320x170 优化）──
    readonly property int fontTiny: Math.round(7 * fontScale)
    readonly property int fontSmall: Math.round(8 * fontScale)
    readonly property int fontBody: Math.round(9 * fontScale)
    readonly property int fontNormal: Math.round(10 * fontScale)
    readonly property int fontMedium: Math.round(11 * fontScale)
    readonly property int fontLarge: Math.round(13 * fontScale)
    readonly property int fontTitle: Math.round(14 * fontScale)
    readonly property int fontHuge: Math.round(18 * fontScale)

    // 兼容旧属性名
    readonly property int fontXLarge: fontHuge
    readonly property color fontMuted: textTertiary
    readonly property color accentSoft: primaryLight
    readonly property color textMuted: textTertiary
    readonly property color bgCardAlt: bgCardHover

    // ── 间距 ──
    readonly property int spacingTiny: 2
    readonly property int spacingSmall: 4
    readonly property int spacingNormal: 6
    readonly property int spacingMedium: 8
    readonly property int spacingLarge: 12
    readonly property int spacingXL: 16

    // 兼容旧属性名
    readonly property int spacingXS: spacingTiny
    readonly property int spacingS: spacingSmall
    readonly property int spacingM: spacingNormal
    readonly property int spacingL: spacingMedium

    // ── 圆角体系 ──
    readonly property int radiusTiny: 2
    readonly property int radiusSmall: 4
    readonly property int radiusMedium: 6
    readonly property int radiusLarge: 10
    readonly property int radiusXL: 14
    readonly property int radiusRound: 999

    // 兼容旧属性名
    readonly property int radiusS: radiusSmall
    readonly property int radiusM: radiusMedium
    readonly property int radiusL: radiusLarge

    // ── 列表/卡片布局 ──
    readonly property int cardWidth: 105
    readonly property int listCacheBuffer: 640
    readonly property int listDisplayMargin: 160

    // ── 触摸最小点击区域 ──
    readonly property int touchMinSize: 28
    readonly property int buttonHeight: 24
    readonly property int buttonHeightLarge: 30

    // ── 标题栏/底部栏 ──
    readonly property int titleBarHeight: 28
    readonly property int tabBarHeight: 26

    // ── 动画时长 ──
    readonly property int animFast: 120
    readonly property int animNormal: 200
    readonly property int animSlow: 350
    readonly property int animPage: 300

    // ── 字体族 ──
    readonly property string fontFamily: appFont.name !== "" ? appFont.name : "Microsoft YaHei"

    // ── 工具函数 ──
    function withAlpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    function lighten(c, factor) {
        return Qt.lighter(c, 1.0 + factor);
    }

    function darken(c, factor) {
        return Qt.darker(c, 1.0 + factor);
    }
}
