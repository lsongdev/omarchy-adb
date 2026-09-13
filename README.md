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
omarchy plugin add https://github.com/swey-l1/omarchy-android-tv-remote --enable
```

Then set your TV's address (Settings → Network → Status on the TV):

```jsonc
// ~/.config/omarchy/shell.json  → bar.layout.<section>
{
  "id": "atv.remote",
  "tv1Label": "Living room", "tv1Address": "192.168.1.50:5555",
  "tv2Label": "Bedroom",     "tv2Address": "192.168.1.51:5555"
}
```

Up to three sets can be configured; the pad drives one at a time and the picker
at its foot switches between them. You do not have to write that by hand — open
the picker and use **+ Add TV**, which writes the set into `shell.json` for you. One TV is the normal case — configure `tv1`
alone and the picker stays a single status line.

The first connection prompts **"Allow USB debugging?"** on the TV. Tick
"Always allow from this computer". If that prompt is dismissed the set is stuck
in `unauth`, which the picker shows with an **AUTH** button to put the prompt
back on screen — see [Re-authorising a TV](#re-authorising-a-tv).

## Use

| Interaction | Does |
|---|---|
| Left click / `SUPER+SHIFT+T` | Open the remote pad |
| Right click | Input / source picker |
| Middle click | Home |
| Scroll over the icon | TV volume |
| `Tab` (pad open) | Switch to the next configured TV |
| `Alt+1` / `Alt+2` / `Alt+3` (pad open) | Jump straight to that TV |

Plain digits are left alone so they still type into the text field, which is why
the jumps take `Alt`.

In the pad: a D-pad with OK, power, inputs, home, back, volume, mute,
play/pause, rewind, three app shortcuts, a text field, **CLR** (wipes the TV's
focused field), and the set picker along the bottom.

The picker is one line showing the TV being driven and whether it is reachable.
Click it to list every configured set with its own status, and click a set to
switch to it. **+ Add TV** at the foot of that list takes a name and an address
and saves them; a bare IP gets `:5555` appended. The row disappears once all
three slots are used. Removing or renaming a set is still a `shell.json` edit. Reachability for the other sets is only refreshed while that list
is open, so three configured TVs do not mean three times the adb traffic on
every poll.

**Typing**: click the field, type, press Enter — the string is sent and
submitted. **Up/Down** walks the last 10 things you typed.

**The icon turns your theme's urgent colour when the TV is unreachable**, and
the tooltip distinguishes "TV unreachable", "adb not installed" and a TV that
needs authorising.

### Re-authorising a TV

A set whose debugging prompt was dismissed — or that was reset, or had this
machine's key revoked — sits in `unauth` forever. Reconnecting does not help:
`adb` remembers the refusal and fails the handshake silently, with nothing on
the TV's screen. The **AUTH** button beside an `unauth` entry bounces the local
adb server, which forces a fresh key exchange and puts the prompt back up.

Bouncing the server drops *every* connected device for a moment, including your
other TVs. They reconnect on their next action, so this is a blip rather than a
problem, but it is why AUTH only appears when it is genuinely the fix.

### Optional hotkey

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + SHIFT + T", "TV remote", "omarchy-shell shell toggle atv.remote")
```

## Settings

Every key goes in the widget's entry in `shell.json`.

| Key | Default | What |
|---|---|---|
| `tv1Label` / `tv1Address` | *(empty)* | Name and `host:port` of the first TV |
| `tv2Label` / `tv2Address` | *(empty)* | Second TV, if you have one |
| `tv3Label` / `tv3Address` | *(empty)* | Third TV |
| `tvAddress` | *(empty)* | Deprecated single-TV key, still read as `tv1Address` when that is unset. Empty everywhere = use the first connected adb device |
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
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status     # up | down | unauth | noadb
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote reauth     # re-show the debugging prompt
```

## Licence

MIT — see [LICENSE](LICENSE).

## Development

The plugin is plain QML plus a shell script, so edits apply without a rebuild:

```bash
$EDITOR ~/.config/omarchy/plugins/atv.remote/Panel.qml
omarchy restart shell
```

Files under `~/.config/omarchy/plugins/` hot-reload on save, but the bar widget
is mounted at startup — a restart is the reliable way to see a change. The
`tv-remote` script needs no restart at all.

If you installed with `omarchy plugin add`, the directory is a git checkout, so
`omarchy plugin update atv.remote` pulls new commits.
