# Android TV Remote: an Omarchy bar widget

Drive an Android TV from the Omarchy bar over ADB. D-pad, volume, input
picker, app shortcuts, and a text field so you can type into TV search boxes
with a real keyboard instead of pecking at an on-screen grid.

![bar widget](docs/screenshot.png)

## Requirements

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- `adb` (on Arch: `sudo pacman -S android-tools`)
- An Android TV with **Developer options → USB/Wireless debugging** enabled,
  reachable on your network

## Install

```bash
omarchy plugin add https://github.com/swey-l1/omarchy-android-tv-remote --enable
```

`--enable` is what puts the widget into the bar; without it the plugin installs
and nothing appears.

Everything else is done from the pad. Open it, click the picker along its foot,
and use **+ Add TV**: it takes a name and the TV's address (Settings → Network →
Status on the TV), and a bare IP gets `:5555` appended for you. Up to three sets
can be configured and the pad drives one at a time, though one TV is the normal
case, and with a single set the picker stays one status line.

**Edit / remove** in the same list renames or deletes a set, and turns the three
shortcut buttons into app choosers, so no part of setup needs a package name
looked up by hand.

Nothing stops you writing it out instead, if you prefer configuration in a file:

```jsonc
// ~/.config/omarchy/shell.json  → bar.layout.<section>
{
  "id": "atv.remote",
  "tv1Label": "Living room", "tv1Address": "192.168.1.50:5555",
  "tv2Label": "Bedroom",     "tv2Address": "192.168.1.51:5555"
}
```

The first connection prompts **"Allow USB debugging?"** on the TV. Tick
"Always allow from this computer". If that prompt is dismissed the set is stuck
in `unauth`, which the picker shows with an **AUTH** button to put the prompt
back on screen. See [Re-authorising a TV](#re-authorising-a-tv).

## Use

| Interaction | Does |
|---|---|
| Left click / `SUPER+SHIFT+T` | Open the remote pad |
| Right click | Input / source picker |
| Middle click | Home |
| Scroll over the icon | TV volume |

### Keyboard

With the pad open the keyboard drives the TV. It is modal, the way a real remote
is: typing at the TV is something you enter deliberately with `T`, because
otherwise every letter would be text bound for the search box and none of them
could be a control.

| Key | Does |
|---|---|
| Arrows or `W` `A` `S` `D` | D-pad |
| `Enter` | Select / OK |
| `B` or `Backspace` | Back |
| `H` | Home |
| `M` | Menu |
| `I` | Input / source picker |
| `C` | Clear the field on the TV |
| `P` | Play / pause |
| `R` / `F` | Rewind / fast-forward |
| `[` / `]` | Previous / next |
| `-` / `=` or `+` | Volume down / up |
| `X` | Mute |
| `Shift+W` / `Shift+S` | Wake / power |
| `1` `2` `3` | The three app shortcuts |
| `T` or `/` | Type at the TV. `Esc` hands the keyboard back |
| `Tab` | Switch to the next configured TV |
| `Alt+1` / `Alt+2` / `Alt+3` | Jump straight to that TV |
| `Esc` or `Q` | Close the pad |

Hovering anything in the pad names it, and its key, along the bottom of the
pad. **Keyboard shortcuts** in the picker lists the lot, including the keys with
no button of their own.

Both power-state keys sit behind `Shift`, since `W` and `S` are D-pad directions.
Power especially: it cannot be undone from this side, because a TV that is off
does not answer ADB, so a stray press by someone who forgot to hit `T` first
would end the session.

Clicking the text field enters typing mode too, and the placeholder reads
**T to type…** as a reminder that the pad is modal.

In the pad: a D-pad with OK, power, inputs, home, back, volume, mute,
play/pause, rewind, three app shortcuts, a text field, **CLR** (wipes the TV's
focused field), and the set picker along the bottom.

The picker is one line showing the TV being driven and whether it is reachable.
Click it to list every configured set with its own status, and click a set to
switch to it. **+ Add TV** at the foot of that list takes a name and an address
and saves them; a bare IP gets `:5555` appended. The row disappears once all
three slots are used.

**Edit / remove** below it flips the list into edit mode, where a click opens a
set for rename or deletion rather than switching to it. Deleting the set you are
currently driving moves you to the first one left.

Edit mode also outlines the three shortcut buttons, and clicking one then sets
what it launches rather than launching it: the pad reads the launchable apps off
the TV and lists them to choose from.

![edit mode](docs/edit-mode.png)

Which TV you are on is remembered across restarts. The other sets only have
their reachability refreshed while the list is open, so three configured TVs do
not mean three times the adb traffic on every poll.

**Typing**: press `T` (or click the field), type, press Enter, and the string is
sent and submitted. `Esc` hands the keyboard back to the controls. **Up/Down**
walks the last 10 things you typed.

**The icon turns your theme's urgent colour when the TV is unreachable**, and
the tooltip distinguishes "TV unreachable", "adb not installed" and a TV that
needs authorising.

### Re-authorising a TV

A set whose debugging prompt was dismissed (or that was reset, or had this
machine's key revoked) sits in `unauth` forever. Reconnecting does not help:
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
| `activeSlot` | `0` | Which slot the pad is driving. Written by the picker; you should not need to set it |
| `tvAddress` | *(empty)* | Deprecated single-TV key, still read as `tv1Address` when that is unset. Empty everywhere = use the first connected adb device |
| `pollSec` | `60` | How often to check reachability |
| `app1Label` / `app1Package` | `APP1` | First shortcut button (e.g. `NFLX` / `com.netflix.ninja`). Settable from the pad, see **Edit / remove** |
| `app2Label` / `app2Package` | `APP2` | Second shortcut |
| `app3Label` / `app3Package` | `APP3` | Third shortcut |

The pad can list them for you, and `tv-remote apps` prints the same list from a
terminal. Android exposes app labels to other apps but not to `adb`, so the
picker shows a name derived from the package and leaves the button label yours
to set.

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
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote apps       # launchable packages
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status     # up | down | unauth | noadb
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote reauth     # re-show the debugging prompt
```

## Licence

MIT. See [LICENSE](LICENSE).

## Development

![architecture](docs/architecture.png)

How a key press reaches the TV. The second diagram is the file map: every QML
file once, and what each is built from.

![components](docs/components.png)

[`docs/architecture.html`](docs/architecture.html) and
[`docs/components.html`](docs/components.html) are the same diagrams as
interactive pages: open them in a browser for guided views, search and export.
They are generated from the `.json` beside each with
[Archify](https://github.com/tt-a1i/archify); see `CLAUDE.md` for the command.

The plugin is plain QML plus a shell script, so edits apply without a rebuild:

```bash
$EDITOR ~/.config/omarchy/plugins/atv.remote/Panel.qml
omarchy restart shell
```

Files under `~/.config/omarchy/plugins/` hot-reload on save, but the bar widget
is mounted at startup, so a restart is the reliable way to see a change. The
`tv-remote` script needs no restart at all, and `./test/tv-remote.sh` checks it
against a fake `adb` without a TV in the room.

If you installed with `omarchy plugin add`, the directory is a git checkout, so
`omarchy plugin update atv.remote` pulls new commits.
