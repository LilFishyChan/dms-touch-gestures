#!/usr/bin/env python3
"""触摸屏手势守护进程。

读 evdev 的触摸事件，识别「起点区域 + 方向 + 手指数」，执行配置的动作。
动作来自 DMS 的 plugin_settings.json（nabuTouchGestures 节点）。

手势键的构造规则：
    <fingers>_<region>_<direction>
例如：
    1_bottom_up      单指从底部上滑
    1_top-left_down  单指从左上角下滑
    3_center_left    三指左滑
    4_center_up      四指上滑

区域：top / bottom / left / right / center / top-left / top-right / bottom-left / bottom-right
方向：up / down / left / right（单指 tap 不触发，留给应用）
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import evdev
from evdev import ecodes

PLUGIN_ID = "nabuTouchGestures"
SETTINGS = Path(os.path.expanduser("~/.config/dms/plugin_settings.json"))
STATE_DIR = Path(os.path.expanduser("~/.local/state/nabu-touch-gestures"))
LOG_FILE = STATE_DIR / "log"

DEFAULTS = {
    "active": True,
    "edge_width_px": 5,        # 边缘带粗细（逻辑像素）
    "edge_width_pct": 50,      # 边缘带长度，占中段（短边减去两端角落）的百分比
    "corner_size_pct": 22,     # 角落区域占屏幕短边的百分比
    "swipe_min_pct": 6,        # 最小滑动距离（屏幕短边百分比）
    "device": "",              # 空 = 自动探测
    # 全部默认 "none"：手势会同时被前台应用收到，任何预绑动作都会让那个方向
    # 出现「应用也在动 + 桌面也在动」的双重反应。由用户在设置页按需开启。
    # 用 "none" 而不是 ""：DMS 的 SelectionSetting 有
    #   root.value = labelToValue[newValue] || newValue
    # 空字符串是 falsy，会回退成选项的显示文字存进去。
    "1_bottom_up": "none",
    "1_top_down": "none",
    "1_left_right": "none",
    "1_right_left": "none",
    "1_top-left_down": "none",
    "1_top-right_down": "none",
    "1_bottom-left_up": "none",
    "1_bottom-right_up": "none",
    "3_center_up": "none",
    "3_center_down": "none",
    "3_center_left": "none",
    "3_center_right": "none",
    "4_center_up": "none",
    "4_center_down": "none",
    "4_center_left": "none",
    "4_center_right": "none",
    "custom_1_bottom_up": "",
    "custom_1_top_down": "",
    "custom_1_left_right": "",
    "custom_1_right_left": "",
    "custom_1_top-left_down": "",
    "custom_1_top-right_down": "",
    "custom_1_bottom-left_up": "",
    "custom_1_bottom-right_up": "",
    "custom_3_center_up": "",
    "custom_3_center_down": "",
    "custom_3_center_left": "",
    "custom_3_center_right": "",
    "custom_4_center_up": "",
    "custom_4_center_down": "",
    "custom_4_center_left": "",
    "custom_4_center_right": "",
}

# 动作表：键 -> 命令列表（None 表示忽略）
NIRI = ["niri", "msg", "action"]
DMS = ["dms", "ipc", "call"]

ACTIONS = {
    "toggle-overview": NIRI + ["toggle-overview"],
    "open-overview": NIRI + ["open-overview"],
    "close-overview": NIRI + ["close-overview"],
    "niri-focus-left": NIRI + ["focus-column-left"],
    "niri-focus-right": NIRI + ["focus-column-right"],
    "niri-focus-up": NIRI + ["focus-window-up"],
    "niri-focus-down": NIRI + ["focus-window-down"],
    "niri-move-left": NIRI + ["move-column-left"],
    "niri-move-right": NIRI + ["move-column-right"],
    "niri-close": NIRI + ["close-window"],
    "niri-fullscreen": NIRI + ["fullscreen-window"],
    "niri-float": NIRI + ["toggle-window-floating"],
    "niri-ws-up": NIRI + ["focus-workspace-up"],
    "niri-ws-down": NIRI + ["focus-workspace-down"],
    "control-center": DMS + ["control-center", "toggle"],
    "launcher": DMS + ["launcher", "toggle"],
    "notifications": DMS + ["notifications", "toggle"],
    "powermenu": DMS + ["powermenu", "toggle"],
    "clipboard": DMS + ["clipboard", "toggle"],
    "dms-dash": DMS + ["dash", "toggle"],
    "dms-vol-up": DMS + ["audio", "volumeUp"],
    "dms-vol-down": DMS + ["audio", "volumeDown"],
    "dms-mute": DMS + ["audio", "toggleMute"],
    "dms-bri-up": DMS + ["brightness", "increase"],
    "dms-bri-down": DMS + ["brightness", "decrease"],
}


def log(msg: str) -> None:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    line = f"[{time.strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    with open(LOG_FILE, "a", encoding="utf-8") as f:
        f.write(line + "\n")


def load_config() -> dict:
    cfg = dict(DEFAULTS)
    try:
        raw = json.loads(SETTINGS.read_text(encoding="utf-8"))
        node = raw.get(PLUGIN_ID, {})
        for k, v in node.items():
            if k in DEFAULTS:
                cfg[k] = v
    except Exception as exc:  # noqa: BLE001
        log(f"读配置失败，用默认值: {exc}")
    return cfg


def detect_output(dev) -> str:
    """猜这块触摸屏对应的 niri 输出。单屏设备直接取第一个。"""
    try:
        env = dict(os.environ)
        sock = env.get("NIRI_SOCKET")
        if not sock:
            out = subprocess.run(["systemctl", "--user", "show-environment"],
                                 capture_output=True, text=True, timeout=3).stdout
            for line in out.splitlines():
                if line.startswith("NIRI_SOCKET="):
                    env["NIRI_SOCKET"] = line.split("=", 1)[1]
                    break
        res = subprocess.run(["niri", "msg", "--json", "outputs"],
                             capture_output=True, text=True, timeout=3, env=env)
        data = json.loads(res.stdout)
        names = [n for n, o in data.items() if (o.get("logical") or {}).get("width", 0) > 0]
        return names[0] if names else ""
    except Exception:  # noqa: BLE001
        return ""


def pick_device(preferred: str):
    """返回触摸屏 InputDevice。"""
    if preferred:
        try:
            return evdev.InputDevice(preferred)
        except Exception as exc:  # noqa: BLE001
            log(f"指定设备 {preferred} 打不开（{exc}），改自动探测")

    candidates = []
    for path in sorted(evdev.list_devices()):
        try:
            dev = evdev.InputDevice(path)
        except Exception:  # noqa: BLE001
            continue
        caps = dev.capabilities()
        # capabilities() 里 EV_ABS 是 [(code, AbsInfo), ...]，EV_KEY 是 [code, ...]
        abs_items = caps.get(ecodes.EV_ABS, [])
        abs_codes = {code for code, _info in abs_items}
        key_codes = set(caps.get(ecodes.EV_KEY, []))
        if ecodes.ABS_MT_SLOT in abs_codes or ecodes.ABS_MT_POSITION_X in abs_codes:
            pass
        elif ecodes.BTN_TOUCH not in key_codes:
            continue
        candidates.append(dev)

    if not candidates:
        return None, None
    dev = candidates[0]

    # 尺寸从设备自身的坐标范围取
    abs_items = dev.capabilities().get(ecodes.EV_ABS, [])
    ranges = {code: info.max for code, info in abs_items}
    xmax = ranges.get(ecodes.ABS_MT_POSITION_X, 0)
    ymax = ranges.get(ecodes.ABS_MT_POSITION_Y, 0)
    return dev, (xmax or 1600, ymax or 2560)


def read_transform(output: str) -> str:
    """读 niri 当前输出变换。失败返回 normal。"""
    try:
        env = dict(os.environ)
        sock = env.get("NIRI_SOCKET")
        if not sock:
            out = subprocess.run(["systemctl", "--user", "show-environment"],
                                 capture_output=True, text=True, timeout=3).stdout
            for line in out.splitlines():
                if line.startswith("NIRI_SOCKET="):
                    env["NIRI_SOCKET"] = line.split("=", 1)[1]
                    break
        res = subprocess.run(["niri", "msg", "--json", "outputs"],
                             capture_output=True, text=True, timeout=3, env=env)
        data = json.loads(res.stdout)
        node = data.get(output) or next(iter(data.values()), {})
        return (node.get("logical") or {}).get("transform", "normal")
    except Exception:  # noqa: BLE001
        return "normal"


def to_logical(nx: float, ny: float, transform: str) -> tuple[float, float]:
    """物理归一化坐标 → 逻辑归一化坐标。

    niri/wlroots 的 transform 表示输出内容如何旋转：
      90  = 内容顺时针 90°，物理的 +y 变成逻辑的 +x
      270 = 逆时针 90°
    """
    # niri 的 transform 90 实测是逆时针语义（与 wlroots 文档相反），
    # 以设备实测为准：物理 +x 在 transform 90 下变成逻辑 -x。
    if transform in ("90", "clockwise"):
        return 1.0 - ny, nx
    if transform in ("270", "counterclockwise"):
        return ny, 1.0 - nx
    if transform == "180":
        return 1.0 - nx, 1.0 - ny
    if transform == "flipped":
        return 1.0 - nx, ny
    if transform == "flipped-90":
        return 1.0 - ny, 1.0 - nx
    if transform == "flipped-270":
        return ny, nx
    return nx, ny


def read_scale() -> float:
    """读 niri 输出缩放，把逻辑像素换算成 evdev 的物理像素。"""
    try:
        env = dict(os.environ)
        if not env.get("NIRI_SOCKET"):
            out = subprocess.run(["systemctl", "--user", "show-environment"],
                                 capture_output=True, text=True, timeout=3).stdout
            for line in out.splitlines():
                if line.startswith("NIRI_SOCKET="):
                    env["NIRI_SOCKET"] = line.split("=", 1)[1]
                    break
        res = subprocess.run(["niri", "msg", "--json", "outputs"],
                             capture_output=True, text=True, timeout=3, env=env)
        for node in json.loads(res.stdout).values():
            scale = (node.get("logical") or {}).get("scale")
            if scale:
                return float(scale)
    except Exception:  # noqa: BLE001
        pass
    return 1.0


def region_of(nx: float, ny: float, thickness: float,
              length_x: float, length_y: float,
              corner_x: float, corner_y: float) -> str:
    """归一化坐标 (0..1) → 9 区域。

    thickness  边带粗细（归一化）
    length_x   顶部/底部带沿屏幕宽度的覆盖长度（归一化，居中）
    length_y   左边/右边带沿屏幕高度的覆盖长度（归一化，居中）
    corner_x   角落沿水平边的臂长（归一化到屏幕宽）
    corner_y   角落沿垂直边的臂长（归一化到屏幕高）

    长度基准是**它自己那条边**，不是短边：顶部带看宽、左右带看高。
    角落是 L 形（两臂都只有 thickness 粗），不是方块。
    """
    t = thickness

    # 四角：L 形 = 沿水平边的横段 ∪ 沿垂直边的竖段
    if (nx < corner_x and ny < t) or (ny < corner_y and nx < t):
        return "top-left"
    if (nx > 1.0 - corner_x and ny < t) or (ny < corner_y and nx > 1.0 - t):
        return "top-right"
    if (nx < corner_x and ny > 1.0 - t) or (ny > 1.0 - corner_y and nx < t):
        return "bottom-left"
    if (nx > 1.0 - corner_x and ny > 1.0 - t) or (ny > 1.0 - corner_y and nx > 1.0 - t):
        return "bottom-right"

    # 四边：沿自己那条边居中覆盖
    half_x = length_x / 2.0
    half_y = length_y / 2.0
    if ny < t and abs(nx - 0.5) <= half_x:
        return "top"
    if ny > 1.0 - t and abs(nx - 0.5) <= half_x:
        return "bottom"
    if nx < t and abs(ny - 0.5) <= half_y:
        return "left"
    if nx > 1.0 - t and abs(ny - 0.5) <= half_y:
        return "right"
    return "center"


def direction_of(dx: float, dy: float, minimum: float) -> str:
    """归一化位移 → 方向。"""
    if abs(dx) < minimum and abs(dy) < minimum:
        return "tap"
    if abs(dx) > abs(dy):
        return "right" if dx > 0 else "left"
    return "down" if dy > 0 else "up"


def run_action(cfg: dict, key: str) -> None:
    if not cfg.get("active", True):
        return
    action = cfg.get(key, "")
    # "none" 是设置页的哨兵值；空串和旧版本存下来的中文标签也按无动作处理
    if not action or action == "none" or action.startswith("无"):
        return
    if action == "custom":
        cmd = cfg.get("custom_" + key, "").strip()
        if not cmd:
            log(f"{key}: 选了自定义但命令为空")
            return
        argv = ["sh", "-c", cmd]
    else:
        argv = ACTIONS.get(action)
        if not argv:
            log(f"{key}: 未知动作 {action!r}")
            return
    log(f"{key} → {' '.join(argv)}")
    try:
        subprocess.Popen(argv, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except Exception as exc:  # noqa: BLE001
        log(f"{key}: 执行失败 {exc}")


class Recognizer:
    """把 evdev 事件流折叠成一次一次的手势。"""

    def __init__(self, cfg: dict, size: tuple[int, int]):
        self.cfg = cfg
        self.w, self.h = size
        self.short = min(self.w, self.h)
        self.scale = read_scale()
        self.slots: dict[int, dict] = {}
        self.cur_slot = 0
        self.touching = False
        self.t0 = 0.0
        self.max_fingers = 0
        self.start = None
        self.last = None
        self.transform = "normal"
        self.output = ""

    def reload(self, cfg: dict) -> None:
        self.cfg = cfg
        self.cfg["_reloaded_at"] = time.monotonic()

    def handle(self, event):
        if event.type == ecodes.EV_ABS:
            code, val = event.code, event.value
            if code == ecodes.ABS_MT_SLOT:
                self.cur_slot = val
            elif code == ecodes.ABS_MT_TRACKING_ID:
                if val == -1:
                    self.slots.pop(self.cur_slot, None)
                else:
                    self.slots[self.cur_slot] = {"x": None, "y": None}
            elif code == ecodes.ABS_MT_POSITION_X:
                self.slots.setdefault(self.cur_slot, {"x": None, "y": None})["x"] = val
            elif code == ecodes.ABS_MT_POSITION_Y:
                self.slots.setdefault(self.cur_slot, {"x": None, "y": None})["y"] = val

        elif event.type == ecodes.EV_KEY and event.code == ecodes.BTN_TOUCH:
            if event.value == 1:
                self.touching = True
                self.t0 = time.monotonic()
                self.max_fingers, self.start, self.last = 0, None, None
            else:
                if self.touching:
                    self.finish()
                self.touching = False
                self.slots.clear()

        elif event.type == ecodes.EV_SYN and event.code == ecodes.SYN_REPORT:
            if not self.touching:
                return
            live = [s for s in self.slots.values()
                    if s.get("x") is not None and s.get("y") is not None]
            if not live:
                return
            self.max_fingers = max(self.max_fingers, len(live))
            if self.start is None:
                self.start = (live[0]["x"], live[0]["y"])
            self.last = (live[0]["x"], live[0]["y"])

    def finish(self) -> None:
        if not self.start or not self.last:
            return
        cfg = self.cfg
        # 粗细：像素（逻辑 px → 物理 px → 归一化到短边）
        thickness = (cfg.get("edge_width_px", 5) * self.scale) / self.short
        # 角落臂长是绝对长度（按短边百分比算），分别归一化到两条边
        corner_px = corner * self.short
        corner_x = corner_px / self.w
        corner_y = corner_px / self.h
        # 长度基准是该边自身：顶部/底部看宽，左/右看高
        pct = cfg.get("edge_width_pct", 50) / 100.0
        length_x = max(0.0, 1.0 - 2.0 * corner_x) * pct
        length_y = max(0.0, 1.0 - 2.0 * corner_y) * pct
        corner = cfg.get("corner_size_pct", 22) / 100.0
        minimum = cfg.get("swipe_min_pct", 6) / 100.0

        # 物理像素 → 归一化 → 按 niri 的 transform 转到逻辑方向
        n0 = (self.start[0] / self.w, self.start[1] / self.h)
        n1 = (self.last[0] / self.w, self.last[1] / self.h)
        l0 = to_logical(n0[0], n0[1], self.transform)
        l1 = to_logical(n1[0], n1[1], self.transform)

        region = region_of(l0[0], l0[1], thickness, length_x, length_y, corner_x, corner_y)
        dx, dy = l1[0] - l0[0], l1[1] - l0[1]

        # 归一化坐标下「短边」是 1.0，最小滑动距离直接用比例
        direction = direction_of(dx, dy, minimum)
        if direction == "tap":
            return  # 轻点不拦，留给应用

        fingers = self.max_fingers
        if fingers >= 3:
            # 多指手势只在中心区域响应，边缘留给单指
            region = "center"

        key = f"{fingers}_{region}_{direction}"
        if key in cfg:
            run_action(cfg, key)
        else:
            log(f"未配置: {key}（物理位移 {self.last[0]-self.start[0]},{self.last[1]-self.start[1]} "
                f"transform={self.transform}）")


def settings_mtime() -> float:
    try:
        return SETTINGS.stat().st_mtime
    except OSError:
        return 0.0


def main() -> int:
    STATE_DIR.mkdir(parents=True, exist_ok=True)
    cfg = load_config()
    dev, size = pick_device(cfg.get("device", ""))
    if dev is None:
        log("找不到触摸屏设备")
        return 1

    rec_scale = read_scale()
    log(f"启动：设备={dev.path} ({dev.name}) 尺寸={size} "
        f"边缘带 粗={cfg.get('edge_width_px')}px 长={cfg.get('edge_width_pct')}% "
        f"角落={cfg.get('corner_size_pct')}% scale={rec_scale}")

    rec = Recognizer(cfg, size)
    rec.output = detect_output(dev)
    rec.transform = read_transform(rec.output)
    log(f"输出={rec.output} transform={rec.transform}")

    mtime = settings_mtime()
    last_check = time.monotonic()
    last_transform = time.monotonic()

    for event in dev.read_loop():
        rec.handle(event)

        now = time.monotonic()
        # 配置改动：每秒最多查一次，设置页改完不用重启
        if now - last_check > 1.0:
            last_check = now
            new = settings_mtime()
            if new != mtime:
                mtime = new
                rec.reload(load_config())
                log(f"配置已更新 active={rec.cfg.get('active')}")
        # 屏幕方向：每 2 秒核对一次，旋转后手势立刻跟上
        if now - last_transform > 2.0:
            last_transform = now
            t = read_transform(rec.output)
            if t != rec.transform:
                rec.transform = t
                log(f"屏幕方向变化: transform={t}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        sys.exit(0)
