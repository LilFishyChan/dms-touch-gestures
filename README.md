# Touch Gestures

Touchscreen swipe gestures for [niri](https://github.com/YaLTeR/niri), packaged as a
[DankMaterialShell](https://github.com/AvengeMedia/DankMaterialShell) plugin.

Reads the touch panel directly through `evdev`, recognises **finger count × region × direction**, and
runs one command per gesture — edge swipes, corner swipes, and three- or four-finger swipes.

## Why a daemon and not compositor binds

niri's native touchscreen gesture binds (`TouchSwipe`, `TouchTap`, `TouchEdge`, …) are gated behind
"since: next" upstream — they are not in the 26.04 release. Until a release ships them, reading the
panel from userspace is the only way to get edge and corner gestures. Re-check before assuming this
plugin is permanent:

```sh
printf 'binds {\n    TouchSwipe fingers=3 direction="up" { toggle-overview; }\n}\n' > /tmp/t.kdl
niri validate -c /tmp/t.kdl 2>&1 | grep -i 'invalid key'
```

If that stops reporting `invalid key: TouchSwipe`, native binds are available and this plugin can be
retired.

## Requirements

- `python-evdev` (`pacman -S python-evdev`)
- the user in the `input` group (`usermod -aG input $USER`, then re-login)
- a compositor exposing `niri msg` on `NIRI_SOCKET` — the plugin looks it up from the systemd user
  environment, so no manual export is needed

## Install

```sh
git clone https://github.com/LilFishyChan/dms-touch-gestures \
  ~/.config/dms/plugins/nabuTouchGestures
dms ipc call plugins reload nabuTouchGestures
```

The directory **must** be named `nabuTouchGestures` — DMS requires the folder name to match the
plugin id.

## Gesture model

A gesture key is `<fingers>_<region>_<direction>`:

| part | values |
|---|---|
| fingers | `1`, `3`, `4` |
| region | `top`, `bottom`, `left`, `right`, `center`, `top-left`, `top-right`, `bottom-left`, `bottom-right` |
| direction | `up`, `down`, `left`, `right` |

Examples: `1_bottom_up`, `1_top-left_down`, `3_center_left`, `4_center_up`.

- **Corners are tested before edges** and claim a wider band, otherwise the corner overlap swallows
  every corner swipe.
- **Multi-finger touches always use `center`** — an edge band only means something for one finger.
- **A touch shorter than the swipe minimum is a tap and is ignored**, so tapping an on-screen button
  that happens to sit on a gesture strip does not fire a gesture.
- Only `1_bottom_up` has a default action. Everything else ships empty on purpose: see the
  limitation below.

## Rotation

`evdev` reports **physical** coordinates that never rotate. With the display turned, an on-screen
up-swipe arrives on a different physical axis, so the plugin reads `logical.transform` from
`niri msg --json outputs` and rotates both the touch origin (for the region) and the delta (for the
direction) in normalised space. It re-reads the transform every two seconds, so gestures stay
correct after the screen rotates.

`niri`'s transform semantics are **opposite to what the wlroots documentation implies** — on real
hardware `transform 90` maps physical `+x` to logical `-x`. The mapping in `to_logical()` is what was
verified on a device; if direction keys feel swapped on yours, flip the `90` and `270` branches.

## Limitation: touch is not intercepted

`evdev` is an **observe-only** interface. The compositor and the focused app receive the same touch
that the gesture daemon sees, so a gesture cannot be swallowed — an edge swipe may also scroll the
app a little as it fires.

Swallowing would require `EVIOCGRAB` on the panel plus re-injecting the events through `uinput`, which
costs 5–20 ms per touch and (because fingers land one after another) still leaks the first frames of
a multi-finger gesture. This plugin deliberately does not do that.

The practical consequence: **configure gestures where apps rarely react** — the very edges and
three-plus fingers — and leave the rest empty.

## Settings

| Setting | Meaning |
|---|---|
| Edge band width | Percent of the short side counted as an edge |
| Corner size | Percent of the short side counted as a corner (wider than the edge band) |
| Minimum swipe distance | Below this a touch is a tap and ignored |
| One finger | 4 edge swipes + 4 corner swipes |
| Three fingers | up / down / left / right |
| Four fingers | up / down / left / right |

Each gesture picks an action — niri operations, DMS panels (control center, launcher, notifications,
clipboard, volume, brightness) — or `Custom command`, which runs the command you type via `sh -c`.

Settings are re-read from `plugin_settings.json` within a second, so changes apply without
restarting the plugin.

## Layout

```
plugin.json                  manifest (id, composite daemon + widget, settings)
Daemon.qml                   daemon surface: runs and supervises the worker
TouchGestures.qml            control-center toggle + bar pill
TouchGesturesSettings.qml    settings page
scripts/touch-gestures.py    evdev recogniser → action dispatcher
translations/zh_CN.json      Chinese translation
```

## License

MIT — see [LICENSE](LICENSE).
