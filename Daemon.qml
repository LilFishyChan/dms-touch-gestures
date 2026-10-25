import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common

// daemon surface：手势守护进程常驻，跟控制中心面板是否展开无关。
// 根必须是 ShellRoot：PanelWindow 是 shell surface，不能挂在普通 Item 下
// （否则日志里出现 "Created graphical object was not placed in the graphics scene"）。
ShellRoot {
    id: root

    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    // 区域尺寸（百分比，与 touch-gestures.py 的判定一致）
    property real edgeWidthPct: 50
    property real edgeWidthPx: 5
    property real cornerPct: 22
    property bool configLoaded: false
    property bool previewVisible: false

    // ==================== 手势守护进程 ====================
    // 退出码 143 = SIGTERM（插件重载/停用），不要自动重启
    Process {
        id: gestureProc
        command: ["python3", root.pluginDir + "scripts/touch-gestures.py"]
        running: true

        onExited: code => {
            if (code !== 0 && code !== 143)
                restartTimer.restart()
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        repeat: false
        onTriggered: gestureProc.running = true
    }

    // ==================== 设置轮询 ====================
    // 只关心区域相关的两项；改动任一项就把区域画出来给用户看
    Process {
        id: configProc
        command: ["python3", "-c",
            "import json;" +
            "d=json.load(open('" + Quickshell.env("HOME") + "/.config/dms/plugin_settings.json')).get('nabuTouchGestures',{});" +
            "print(json.dumps({'p':d.get('edge_width_pct',50),'x':d.get('edge_width_px',5),'c':d.get('corner_size_pct',22)}))"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text.trim() || "{}")
                    const p = Number(d.p)
                    const x = Number(d.x)
                    const c = Number(d.c)
                    if (isNaN(p) || isNaN(x) || isNaN(c))
                        return
                    // 首次读取不弹，只在真正变化时预览
                    if (root.configLoaded
                        && (p !== root.edgeWidthPct || x !== root.edgeWidthPx || c !== root.cornerPct)) {
                        root.previewVisible = true
                        previewTimer.restart()
                    }
                    root.edgeWidthPct = p
                    root.edgeWidthPx = x
                    root.cornerPct = c
                    root.configLoaded = true
                } catch (err) {
                    // 读取失败就保持现状
                }
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: configProc.running = true
    }

    Timer {
        id: previewTimer
        interval: 3000
        repeat: false
        onTriggered: root.previewVisible = false
    }

    // ==================== 区域预览 ====================
    // 全屏 overlay；mask 是空 Region，所以完全不吃触摸
    PanelWindow {
        id: overlay

        visible: root.previewVisible
        color: "transparent"
        mask: Region {}

        WlrLayershell.layer: WlrLayershell.Overlay
        WlrLayershell.namespace: "nabu-touch-gestures-preview"
        // -1 = 完全忽略其他 surface 预留的区域，铺满真正的屏幕（含顶部栏/底部
        // dock 那一条）。0 只是不预留，仍会被已有的 exclusive zone 挤开。
        WlrLayershell.exclusiveZone: -1

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        // 判定用的是「屏幕短边」的百分比，绘制也用短边
        readonly property real shortSide: Math.min(width, height)
        // 粗细直接用 px。长度按**各自那条边**算：顶部/底部看宽，左右看高，
        // 都先扣掉两端的角落臂长，再乘比例，并沿该边居中。
        readonly property real thicknessPx: root.edgeWidthPx
        readonly property real spanX: Math.max(0, width - cornerPx * 2)
        readonly property real spanY: Math.max(0, height - cornerPx * 2)
        readonly property real lenX: spanX * root.edgeWidthPct / 100
        readonly property real lenY: spanY * root.edgeWidthPct / 100
        readonly property real cornerPx: shortSide * root.cornerPct / 100

        component Band: Rectangle {
            color: Theme.withAlpha(Theme.primary, 0.10)
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.35)
        }

        // 角落不是方块，是贴住两条边的 L 形（两个小长方形）
        component CornerBar: Rectangle {
            color: Theme.withAlpha(Theme.primary, 0.22)
            border.width: 1
            border.color: Theme.withAlpha(Theme.primary, 0.65)
        }

        // ---- 四边：顶部/底部按宽算长度，左/右按高算长度，各自居中 ----
        Band {
            x: (parent.width - overlay.lenX) / 2
            y: 0
            width: overlay.lenX
            height: overlay.thicknessPx
        }
        Band {
            x: (parent.width - overlay.lenX) / 2
            y: parent.height - overlay.thicknessPx
            width: overlay.lenX
            height: overlay.thicknessPx
        }
        Band {
            x: 0
            y: (parent.height - overlay.lenY) / 2
            width: overlay.thicknessPx
            height: overlay.lenY
        }
        Band {
            x: parent.width - overlay.thicknessPx
            y: (parent.height - overlay.lenY) / 2
            width: overlay.thicknessPx
            height: overlay.lenY
        }

        // ---- 四角 L 形：每角 = 横条 + 竖条（都只有 thicknessPx 粗）----
        // 左上
        CornerBar {
            x: 0
            y: 0
            width: overlay.cornerPx
            height: overlay.thicknessPx
        }
        CornerBar {
            x: 0
            y: 0
            width: overlay.thicknessPx
            height: overlay.cornerPx
        }
        // 右上
        CornerBar {
            x: parent.width - overlay.cornerPx
            y: 0
            width: overlay.cornerPx
            height: overlay.thicknessPx
        }
        CornerBar {
            x: parent.width - overlay.thicknessPx
            y: 0
            width: overlay.thicknessPx
            height: overlay.cornerPx
        }
        // 左下
        CornerBar {
            x: 0
            y: parent.height - overlay.thicknessPx
            width: overlay.cornerPx
            height: overlay.thicknessPx
        }
        CornerBar {
            x: 0
            y: parent.height - overlay.cornerPx
            width: overlay.thicknessPx
            height: overlay.cornerPx
        }
        // 右下
        CornerBar {
            x: parent.width - overlay.cornerPx
            y: parent.height - overlay.thicknessPx
            width: overlay.cornerPx
            height: overlay.thicknessPx
        }
        CornerBar {
            x: parent.width - overlay.thicknessPx
            y: parent.height - overlay.cornerPx
            width: overlay.thicknessPx
            height: overlay.cornerPx
        }
    }
}
