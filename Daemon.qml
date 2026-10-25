import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common

// daemon surface：手势守护进程常驻，跟控制中心面板是否展开无关。
Item {
    id: root

    readonly property string pluginDir: Qt.resolvedUrl(".").toString().replace("file://", "")

    // 退出码 143 = SIGTERM（插件重载/停用），不要自动重启
    Process {
        id: gestureProc
        command: ["python3", root.pluginDir + "scripts/touch-gestures.py"]
        running: true

        onExited: (code) => {
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
}
