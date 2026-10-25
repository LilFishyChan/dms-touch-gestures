import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    id: settings
    pluginId: "nabuTouchGestures"

    function tr(term) {
        return I18n.trFor("nabuTouchGestures", term);
    }

    // 动作表：value 必须和 scripts/touch-gestures.py 的 ACTIONS 键一致
    readonly property var actionOptions: [
        {label: tr("None"), value: ""},
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
    component GestureRow: Column {
        id: gestureRow
        property string settingKey
        property string title
        property string defaultAction

        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            width: gestureRow.width
            text: gestureRow.title
            font.pixelSize: Theme.fontSizeMedium
            font.bold: true
            color: Theme.surfaceText
            topPadding: Theme.spacingM
        }

        SelectionSetting {
            settingKey: gestureRow.settingKey
            label: settings.tr("Action")
            options: settings.actionOptions
            defaultValue: gestureRow.defaultAction
        }

        StringSetting {
            settingKey: "custom_" + gestureRow.settingKey
            label: settings.tr("Custom command")
            description: settings.tr("Used only when the action above is 'Custom command'")
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

    SliderSetting {
        settingKey: "edge_width_pct"
        label: tr("Edge band width")
        description: tr("Percent of the short side that counts as an edge")
        defaultValue: 12
        minimum: 5
        maximum: 30
        unit: "%"
    }

    SliderSetting {
        settingKey: "corner_size_pct"
        label: tr("Corner size")
        description: tr("Percent of the short side that counts as a corner")
        defaultValue: 22
        minimum: 10
        maximum: 40
        unit: "%"
    }

    SliderSetting {
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
        settingKey: "1_bottom_up";   title: tr("Swipe up from the bottom edge");   defaultAction: "toggle-overview"
    }
    GestureRow {
        settingKey: "1_top_down";    title: tr("Swipe down from the top edge");    defaultAction: "notifications"
    }
    GestureRow {
        settingKey: "1_left_right";  title: tr("Swipe right from the left edge");  defaultAction: "niri-focus-right"
    }
    GestureRow {
        settingKey: "1_right_left";  title: tr("Swipe left from the right edge");  defaultAction: "niri-focus-left"
    }
    GestureRow {
        settingKey: "1_top-left_down";    title: tr("Swipe down from the top-left corner");     defaultAction: ""
    }
    GestureRow {
        settingKey: "1_top-right_down";   title: tr("Swipe down from the top-right corner");    defaultAction: ""
    }
    GestureRow {
        settingKey: "1_bottom-left_up";   title: tr("Swipe up from the bottom-left corner");    defaultAction: ""
    }
    GestureRow {
        settingKey: "1_bottom-right_up";  title: tr("Swipe up from the bottom-right corner");   defaultAction: ""
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
        settingKey: "3_center_up";    title: tr("Three fingers up");    defaultAction: "niri-ws-up"
    }
    GestureRow {
        settingKey: "3_center_down";  title: tr("Three fingers down");  defaultAction: "niri-ws-down"
    }
    GestureRow {
        settingKey: "3_center_left";  title: tr("Three fingers left");  defaultAction: "niri-focus-right"
    }
    GestureRow {
        settingKey: "3_center_right"; title: tr("Three fingers right"); defaultAction: "niri-focus-left"
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
        settingKey: "4_center_up";    title: tr("Four fingers up");    defaultAction: "toggle-overview"
    }
    GestureRow {
        settingKey: "4_center_down";  title: tr("Four fingers down");  defaultAction: "niri-fullscreen"
    }
    GestureRow {
        settingKey: "4_center_left";  title: tr("Four fingers left");  defaultAction: "niri-move-left"
    }
    GestureRow {
        settingKey: "4_center_right"; title: tr("Four fingers right"); defaultAction: "niri-move-right"
    }
}
