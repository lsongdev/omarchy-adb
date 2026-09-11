# Android TV Remote — an Omarchy bar widget

Drive an Android TV from the Omarchy bar over ADB. D-pad, volume, input
picker, app shortcuts, and a text field so you can type into TV search boxes
with a real keyboard instead of pecking at an on-screen grid.

![bar widget](docs/screenshot.png)

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- `adb` — on Arch: `sudo pacman -S android-tools`
- An Android TV with **Developer options → USB/Wireless debugging** enabled,
  reachable on your network

## Install

```bash
omarchy plugin add https://github.com/<you>/omarchy-tv-remote --enable
```

Then set your TV's address (Settings → Network → Status on the TV):

```jsonc
// ~/.config/omarchy/shell.json  → bar.layout.<section>
{ "id": "atv.remote", "tvAddress": "192.168.1.50:5555" }
```

The first connection prompts **"Allow USB debugging?"** on the TV. Tick
"Always allow from this computer".

## Use

| Interaction | Does |
|---|---|
| Left click / `SUPER+SHIFT+T` | Open the remote pad |
| Right click | Input / source picker |
| Middle click | Home |
| Scroll over the icon | TV volume |

In the pad: a D-pad with OK, power, inputs, home, back, volume, mute,
play/pause, rewind, three app shortcuts, a text field, and **CLR** (wipes the
TV's focused field).

**Typing**: click the field, type, press Enter — the string is sent and
submitted. **Up/Down** walks the last 10 things you typed.

**The icon turns your theme's urgent colour when the TV is unreachable**, and
the tooltip distinguishes "TV unreachable" from "adb not installed".

### Optional hotkey

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + SHIFT + T", "TV remote", "omarchy-shell shell toggle atv.remote")
```

## Settings

Every key goes in the widget's entry in `shell.json`.

| Key | Default | What |
|---|---|---|
| `tvAddress` | *(empty)* | `host:port` of the TV. Empty = use the first connected adb device |
| `pollSec` | `60` | How often to check reachability |
| `app1Label` / `app1Package` | `APP1` | First shortcut button (e.g. `NFLX` / `com.netflix.ninja`) |
| `app2Label` / `app2Package` | `APP2` | Second shortcut |
| `app3Label` / `app3Package` | `APP3` | Third shortcut |

Find package names with `adb shell pm list packages -3`.

## Known quirks

- **`%` in typed text is lossy.** Android's `input text` treats `%s` as a space
  with no escape for a literal `%`, so "100%sure" types as "100 ure". This is a
  framework limitation, not something the plugin can work around.
- **Input picker varies by brand.** The plugin sends `KEYCODE_TV_INPUT` and then
  falls back to `android.media.tv.action.SETUP_INPUTS`. On Hisense the keycode is
  a no-op and the vendor source panel is only reachable through protected
  broadcasts ADB cannot send, so the fallback is what opens a picker there.
  Other brands may behave differently.
- **Power is one-way.** A TV that is off does not answer ADB, so the power key
  can turn it off but not on.
- **ADB over wifi drops when the TV sleeps.** Every action reconnects on demand,
  so this is usually invisible.

## Using the shim directly

`tv-remote` is a plain script and works on its own:

```bash
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote key KEYCODE_DPAD_DOWN
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote text "jazz piano" enter
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote clear 30
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status     # up | down | noadb
```

## Licence

MIT — see [LICENSE](LICENSE).
