# Wireless Battery — Noctalia plugin

A Noctalia bar widget that adds the battery levels of **wireless mice, keyboards,
headsets, gamepads and phones** right next to the built-in battery widget. The
stock battery widget, its tooltip and the Control Center Power tab are left
untouched — this plugin only appends the peripheral devices.

```
[⌁ 100%]   [🖱 85%]   [🎧 40% ⚡]
 built-in     └──── this plugin ────┘
```

* **Bar** — one `glyph + percentage` row per device, in the same style as the
  built-in battery widget. Charging devices get the same cyan bolt; devices at
  or below 15% turn red.
* **Tooltip** — device name and level, with `charging` / `asleep` markers.
* **Left click** — a panel styled like Noctalia's Power tab: a header with a
  close button and one bordered card per device (connection, detail breakdown,
  charge bar).
* **Right click** — poll the devices immediately.
* A sleeping mouse that is still reported by its receiver keeps its last known
  level for `grace` seconds. When a device disappears from a poll (receiver
  unplugged or switched off), its cached level is dropped immediately.

Plugin id: `hphuc25/wireless-battery` · `plugin_api = 24` · current version `1.5.1`.

## Requirements / dependencies

| Requirement | Notes |
| --- | --- |
| Noctalia 5.x with Luau plugin support | The manifest targets `plugin_api = 24`. Older QML-only plugin builds are not supported. |
| `wireless-battery` CLI with `--json` | The plugin runs `wireless-battery --json` and parses its JSON output. Builds without this flag will not work; see below. |
| HID read access | The CLI reads `/dev/hidraw*`. Install the `99-wireless-battery.rules` udev rule from the CLI repo's `linux/` folder and reload udev. |
| No root for the plugin | The plugin itself runs unprivileged; only the udev rule is needed. |

Check the CLI dependency with:

```sh
wireless-battery --json
# [{"key":"...","name":"...","kind":"mouse","percent":85,...}]
```

## Install — build the CLI from source

Install a C++17 compiler, `make`, `pkg-config`, and the GTK4 and cairo development
headers first (package names vary by distribution), then:

```sh
git clone https://github.com/hphuc25/Wireless-Device-Battery-Monitor.git
cd Wireless-Device-Battery-Monitor
./build-linux.sh
sudo install -Dm755 wireless-battery /usr/local/bin/wireless-battery
sudo install -Dm644 linux/99-wireless-battery.rules /usr/lib/udev/rules.d/
sudo udevadm control --reload-rules && sudo udevadm trigger
wireless-battery --json
```

## Install — the plugin

```sh
git clone https://github.com/hphuc25/noctalia-plugin-wireless-battery.git
mkdir -p ~/.local/share/noctalia/plugins
cp -r noctalia-plugin-wireless-battery ~/.local/share/noctalia/plugins/wireless-battery
noctalia msg plugins enable hphuc25/wireless-battery
```

Add the widget to your bar, right after the built-in `battery` widget:

```sh
noctalia msg config-set bar.default.end \
  "['tray', 'network', 'volume', 'brightness', 'battery', 'hphuc25/wireless-battery:status']"
noctalia msg config-reload
```

Or drag *Wireless Battery* next to *Battery* in **Settings → Bar**.

### Upgrade

```sh
cd noctalia-plugin-wireless-battery && git pull
cp -r . ~/.local/share/noctalia/plugins/wireless-battery/
noctalia msg config-reload
```

## Settings

All settings are in **Settings → Plugins → Wireless Battery**, or under
`[plugin_settings."hphuc25/wireless-battery"]` in the Noctalia config.

| Key | Type | Default | Description |
| --- | --- | --- | --- |
| `command` | string | `wireless-battery` | Path to the CLI executable. Set this if it is not on `PATH`. |
| `interval` | int | `60` | Check rate in seconds (5–3600). Each poll briefly opens every supported receiver; a longer interval uses less power. |
| `visibility` | select | `dynamic` | `dynamic` hides the widget when nothing is connected. `static` keeps it visible and shows `mouse ?` instead. |
| `device_filters` | string list | `[]` (all) | Select which devices appear on the bar. Each entry matches a kind (`mouse`, `headset`, `keyboard`, `gamepad`, `phone`, `other`) or part of a device name/key/connection. Multiple entries show multiple devices at once. |
| `grace` | int | `1800` | Seconds to keep the last known level while a device is asleep. `0` disables it. |
| `mode` | select | `all` | `all` shows every selected device; `lowest` shows only the one with the lowest charge. |

Examples:

```sh
# Show only the headset and a specific mouse
noctalia msg config-set 'plugin_settings."hphuc25/wireless-battery".device_filters' \
  '["headset", "CX Wireless"]'

# Poll every 15 seconds, keep the last level for 10 minutes
noctalia msg config-set 'plugin_settings."hphuc25/wireless-battery".interval' 15
noctalia msg config-set 'plugin_settings."hphuc25/wireless-battery".grace' 600
```

## Troubleshooting

* **Nothing appears** — run `wireless-battery --json`. It must print a JSON
  array. If it prints `Unknown option --json`, install a newer CLI (see above).
* **Device shows `?` / disappears** — the device is off or out of range. If its
  receiver still sees it as asleep, increase `grace`; otherwise the level was
  dropped because the device is no longer reported. `visibility = static` always
  shows a `?` placeholder.
* **No HID access** — install the udev rule from the CLI repo and re-plug the
  receiver. `ls /dev/hidraw*` should list the receiver.
* **Panel opens behind a window** — set
  `plugin_settings."hphuc25/wireless-battery".devices_placement` to `"floating"`.
* **Logs** — `tail -f ~/.cache/noctalia/noctalia.log`.

## Files

```
plugin.toml          manifest + settings
widget.luau          bar widget, tooltip, refresh and last-known cache
panel.luau           detail panel
translations/en.json English strings
```

## License

GPL-3.0-or-later. See [LICENSE](LICENSE).
