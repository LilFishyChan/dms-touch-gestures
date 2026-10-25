import QtQuick
import qs.Common
import qs.Widgets
import qs.DCommon.Widgets as DCommon
import qs.Modules.Plugins

PluginSettings {
    id: settings
    pluginId: "nabuTouchGestures"

    function tr(term) {
        return I18n.trFor("nabuTouchGestures", term);
    }

    // ---- 启动阶段的写入守卫 ----
    // DMS 会在插件数据从磁盘加载之前就预创建设置页；此时每个 Setting 的
    // loadValue() 只能拿到 defaultValue，而 onValueChanged 会立刻把这个默认值
    // 保存回去，把磁盘上的真实设置冲掉（症状：重启 DMS 后设置全变回默认）。
    // 所以在数据就绪之前一律拦住写入，就绪后再统一重读一遍。
    property bool savingEnabled: false

    function saveValue(key, value) {
        if (!settings.savingEnabled)
            return
        if (pluginService && pluginService.savePluginData) {
            pluginService.savePluginData(pluginId, key, value)
            settingChanged()
        }
    }

    Timer {
        interval: 1200
        running: true
        repeat: false
        onTriggered: {
            // 此刻数据已就绪，先把所有控件重读成真实值
            const stack = [settings]
            while (stack.length > 0) {
                const item = stack.pop()
                if (typeof item.loadValue === "function")
                    item.loadValue()
                for (let i = 0; i < item.children.length; i++)
                    stack.push(item.children[i])
            }
            // 之后才允许写入
            settings.savingEnabled = true
        }
    }


    // 动作表：value 必须和 scripts/touch-gestures.py 的 ACTIONS 键一致
    readonly property var actionOptions: [
        {label: tr("None"), value: "none"},
        {label: tr("Toggle overview"), value: "toggle-overview"},
        {label: tr("Open overview"), value: "open-overview"},
        {label: tr("Close overview"), value: "close-overview"},
        {label: tr("Focus column left"), value: "niri-focus-left"},
        {label: tr("Focus column right"), value: "niri-focus-right"},
        {label: tr("Focus window up"), value: "niri-focus-up"},
        {label: tr("Focus window down"), value: "niri-focus-down"},
        {label: tr("Move column left"), value: "niri-move-left"},
        {label: tr("Move column right"), value: "niri-move-right"},
        {label: tr("Close window"), value: "niri-close"},
        {label: tr("Toggle fullscreen"), value: "niri-fullscreen"},
        {label: tr("Toggle floating"), value: "niri-float"},
        {label: tr("Workspace up"), value: "niri-ws-up"},
        {label: tr("Workspace down"), value: "niri-ws-down"},
        {label: tr("Control center"), value: "control-center"},
        {label: tr("Launcher"), value: "launcher"},
        {label: tr("Notifications"), value: "notifications"},
        {label: tr("Power menu"), value: "powermenu"},
        {label: tr("Clipboard"), value: "clipboard"},
        {label: tr("Dashboard"), value: "dms-dash"},
        {label: tr("Volume up"), value: "dms-vol-up"},
        {label: tr("Volume down"), value: "dms-vol-down"},
        {label: tr("Mute"), value: "dms-mute"},
        {label: tr("Brightness up"), value: "dms-bri-up"},
        {label: tr("Brightness down"), value: "dms-bri-down"},
        {label: tr("Custom command"), value: "custom"}
    ]

    // 一个手势 = 标题 + 动作下拉 + 自定义命令输入
    // 滑块 + 右侧重置图标；只在值偏离默认值时出现
    component ResettableSlider: Column {
        id: rs
        property string settingKey
        property string label
        property string description: ""
        property int defaultValue: 0
        property int minimum: 0
        property int maximum: 100
        property string unit: ""

        width: parent.width
        spacing: 0

        SliderSetting {
            id: slider
            width: rs.width
            settingKey: rs.settingKey
            label: rs.label
            description: rs.description
            defaultValue: rs.defaultValue
            minimum: rs.minimum
            maximum: rs.maximum
            unit: rs.unit
        }

        Item {
            width: rs.width
            height: 20
            visible: slider.value !== rs.defaultValue

            DCommon.DIcon {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                name: "restart_alt"
                size: 15
                color: Theme.primary

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: slider.value = rs.defaultValue
                }
            }
        }
    }

    // 一行一个手势：左边手势名，右边动作下拉；
    // 只有动作选到「自定义命令」时才多出一条命令输入框。
    component GestureRow: Column {
        id: gestureRow
        property string settingKey
        property string title
        property string defaultAction

        width: parent.width
        spacing: Theme.spacingS

        Row {
            width: gestureRow.width
            spacing: Theme.spacingM

            StyledText {
                id: gestureLabel
                readonly property real labelWidth: Math.round((gestureRow.width - Theme.spacingM) * 0.44)
                width: labelWidth
                height: sel.implicitHeight
                text: gestureRow.title
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                wrapMode: Text.WordWrap
                verticalAlignment: Text.AlignVCenter
            }

            SelectionSetting {
                id: sel
                width: gestureRow.width - Theme.spacingM - gestureLabel.labelWidth
                settingKey: gestureRow.settingKey
                label: ""
                options: settings.actionOptions
                defaultValue: gestureRow.defaultAction

            }
        }

        StringSetting {
            visible: sel.value === "custom"
            height: visible ? implicitHeight : 0
            settingKey: "custom_" + gestureRow.settingKey
            label: settings.tr("Custom command")
            description: ""
            placeholder: "niri msg action toggle-overview"
            defaultValue: ""
        }
    }

    StyledText {
        width: parent.width
        text: tr("Swipe gestures on the touchscreen. Reads the panel directly, so the compositor and apps still receive the touch as well.")
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    // ---- 灵敏度 ----
    StyledText {
        width: parent.width
        text: tr("Sensitivity")
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    ResettableSlider {
        settingKey: "edge_width_px"
        label: tr("Edge band thickness")
        description: tr("How thick the edge bands are, in pixels")
        defaultValue: 5
        minimum: 2
        maximum: 30
        unit: " px"
    }

    ResettableSlider {
        settingKey: "edge_width_pct"
        label: tr("Edge band length")
        description: tr("How much of the middle span (short side minus both corners) the band runs along")
        defaultValue: 50
        minimum: 10
        maximum: 100
        unit: "%"
    }

    ResettableSlider {
        settingKey: "corner_size_pct"
        label: tr("Corner arm length")
        description: tr("How far the L-shaped corner zones reach along each edge")
        defaultValue: 22
        minimum: 5
        maximum: 45
        unit: "%"
    }

    ResettableSlider {
        settingKey: "swipe_min_pct"
        label: tr("Minimum swipe distance")
        description: tr("Below this the touch is treated as a tap and ignored")
        defaultValue: 6
        minimum: 2
        maximum: 20
        unit: "%"
    }

    // ---- 单指 ----
    StyledText {
        width: parent.width
        text: tr("One finger")
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    GestureRow {
        settingKey: "1_bottom_up";   title: tr("Swipe up from the bottom edge");   defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_top_down";    title: tr("Swipe down from the top edge");    defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_left_right";  title: tr("Swipe right from the left edge");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_right_left";  title: tr("Swipe left from the right edge");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_top-left_down";    title: tr("Swipe down from the top-left corner");     defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_top-right_down";   title: tr("Swipe down from the top-right corner");    defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_bottom-left_up";   title: tr("Swipe up from the bottom-left corner");    defaultAction: "none"
    }
    GestureRow {
        settingKey: "1_bottom-right_up";  title: tr("Swipe up from the bottom-right corner");   defaultAction: "none"
    }

    // ---- 三指 ----
    StyledText {
        width: parent.width
        text: tr("Three fingers")
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    GestureRow {
        settingKey: "3_center_up";    title: tr("Three fingers up");    defaultAction: "none"
    }
    GestureRow {
        settingKey: "3_center_down";  title: tr("Three fingers down");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "3_center_left";  title: tr("Three fingers left");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "3_center_right"; title: tr("Three fingers right"); defaultAction: "none"
    }

    // ---- 四指 ----
    StyledText {
        width: parent.width
        text: tr("Four fingers")
        font.pixelSize: Theme.fontSizeMedium
        font.bold: true
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    GestureRow {
        settingKey: "4_center_up";    title: tr("Four fingers up");    defaultAction: "none"
    }
    GestureRow {
        settingKey: "4_center_down";  title: tr("Four fingers down");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "4_center_left";  title: tr("Four fingers left");  defaultAction: "none"
    }
    GestureRow {
        settingKey: "4_center_right"; title: tr("Four fingers right"); defaultAction: "none"
    }
}
