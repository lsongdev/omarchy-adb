<p align="center">
  <img src="./assets/readme/hero.svg" width="100%" alt="Android TV Remote: an Omarchy bar widget that drives an Android TV over ADB, with a D-pad, volume, inputs, app shortcuts and a real keyboard for the TV's search box">
</p>

<p align="center">
  <img src="./docs/pad.png" width="246" align="top" alt="The remote pad as it opens: D-pad, media keys, three app shortcuts, a text field, and one line naming the TV being driven and that it is up">
  &nbsp;&nbsp;
  <img src="./docs/screenshot.png" width="246" align="top" alt="The pad with the picker expanded: every configured TV with its own state, plus Add TV, Edit / remove and Keyboard shortcuts">
  &nbsp;&nbsp;
  <img src="./docs/edit-mode.png" width="246" align="top" alt="The pad in edit mode: the three app shortcut buttons outlined for choosing an app, and each TV row marked edit">
</p>

<p align="center"><sub>As it opens &nbsp;·&nbsp; with the picker expanded &nbsp;·&nbsp; in edit mode. Everything here is configured from the pad itself.</sub></p>

The bar icon opens a remote pad. With the pad open the keyboard drives the TV:
arrows and letters are remote keys, and `T` switches to typing into whatever
field the TV has focused. Up to three TVs, switched from the picker along the
foot of the pad. The widget shells out to a small bash script that owns all of
ADB, so the same script works from a terminal without the shell running.

<p align="center">
  <img src="./assets/readme/how-it-works.svg" width="100%" alt="How a key press reaches the TV: the bar icon opens the pad, a key on the pad becomes one tv-remote call, which runs one adb shell command that sends a keyevent to the TV">
</p>

<p align="center">
  <img src="./assets/readme/section-install.svg" width="100%" alt="01 Install: get it into the bar">
</p>

<a name="requirements"></a>
<p align="center">
  <img src="./assets/readme/sub-requirements.svg" width="100%" alt="01.1 Requirements">
</p>

- Omarchy with the Quickshell-based shell (`omarchy-shell`)
- `adb`
- An Android TV with **Developer options → USB/Wireless debugging** enabled,
  reachable on your network

<p align="center">
  <img src="./assets/readme/code-adb.svg" width="100%" alt="On Arch, adb comes from: sudo pacman -S android-tools">
</p>

```bash
sudo pacman -S android-tools
```

<a name="one-command"></a>
<p align="center">
  <img src="./assets/readme/sub-one-command.svg" width="100%" alt="01.2 One command">
</p>

<p align="center">
  <img src="./assets/readme/code-install.svg" width="100%" alt="In a terminal: omarchy plugin add https://github.com/swey-l1/omarchy-android-tv-remote --enable. The --enable flag is what puts the widget into the bar.">
</p>

```bash
omarchy plugin add https://github.com/swey-l1/omarchy-android-tv-remote --enable
```

Then open the pad, click the picker along its foot, and use **+ Add TV**: a
name and the TV's address (Settings → Network → Status on the TV). A bare IP
gets `:5555` appended. Renaming, removing and choosing the shortcut apps all
happen in the same place; see [The picker](#the-picker).

If you would rather configure in a file:

<p align="center">
  <img src="./assets/readme/code-shell-json.svg" width="100%" alt="The widget's entry in ~/.config/omarchy/shell.json under bar.layout: id io.github.swey-l1.atv-remote, then tv1Label and tv1Address, tv2Label and tv2Address">
</p>

<details markdown="1">
<summary>Copy the snippet</summary>

```jsonc
// ~/.config/omarchy/shell.json  → bar.layout.<section>
{
  "id": "io.github.swey-l1.atv-remote",
  "tv1Label": "Living room", "tv1Address": "192.168.1.50:5555",
  "tv2Label": "Bedroom",     "tv2Address": "192.168.1.51:5555"
}
```

</details>

The first connection prompts **"Allow USB debugging?"** on the TV. Tick
"Always allow from this computer". If that prompt is dismissed the set is stuck
in `unauth`, which the picker shows with an **AUTH** button to put the prompt
back on screen. See [Re-authorising a TV](#re-authorising-a-tv).

<p align="center">
  <img src="./assets/readme/section-use.svg" width="100%" alt="02 Use: drive the TV from the pad">
</p>

<p align="center">
  <img src="./assets/readme/mouse.svg" width="100%" alt="The bar icon: left click or SUPER+SHIFT+T opens the pad, right click opens the input picker, middle click sends Home, and scrolling over the icon changes the TV volume">
</p>

<details markdown="1">
<summary>As a table</summary>

| Interaction | Does |
|---|---|
| Left click / `SUPER+SHIFT+T` | Open the remote pad |
| Right click | Input / source picker |
| Middle click | Home |
| Scroll over the icon | TV volume |

</details>

<a name="keyboard"></a>
<p align="center">
  <img src="./assets/readme/sub-keyboard.svg" width="100%" alt="02.1 Keyboard">
</p>

With the pad open the keyboard drives the TV. It is modal, the way a real remote
is: typing at the TV is something you enter deliberately with `T`, because
otherwise every letter would be text bound for the search box and none of them
could be a control.

<p align="center">
  <img src="./assets/readme/keyboard.svg" width="100%" alt="The keyboard while the pad is open, with the bound keys highlighted: W A S D and the arrows are the D-pad, Enter is OK, B or Backspace back, H home, M menu, I inputs, C clear, P play, R rewind, F forward, brackets previous and next, minus and equals volume, X mute, 1 2 3 the app shortcuts, T or slash to type, Tab next TV, Esc or Q close; Shift+W wake, Shift+S power, Alt+1 2 3 jump to a TV">
</p>

<details markdown="1">
<summary>Every key, as a table</summary>

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

</details>

Hovering anything in the pad names it, and its key, along the bottom of the
pad. **Keyboard shortcuts** in the picker lists the lot, including the keys with
no button of their own.

Both power-state keys sit behind `Shift`, since `W` and `S` are D-pad directions.
Power especially: it cannot be undone from this side, because a TV that is off
does not answer ADB, so a stray press by someone who forgot to hit `T` first
would end the session.

Clicking the text field enters typing mode too, and the placeholder reads
**T to type…** as a reminder that the pad is modal. **CLR** wipes whatever
field the TV has focused.

<a name="the-picker"></a>
<p align="center">
  <img src="./assets/readme/sub-the-picker.svg" width="100%" alt="02.2 The picker">
</p>

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

Which TV you are on is remembered across restarts. The other sets only have
their reachability refreshed while the list is open, so three configured TVs do
not mean three times the adb traffic on every poll.

To type, press `T` (or click the field), type, press Enter, and the string is
sent and submitted. `Esc` hands the keyboard back to the controls. **Up/Down**
walks the last 10 things you typed.

The icon turns your theme's urgent colour when the TV is unreachable, and
the tooltip distinguishes "TV unreachable", "adb not installed" and a TV that
needs authorising.

<a name="re-authorising-a-tv"></a>
<p align="center">
  <img src="./assets/readme/sub-re-authorising.svg" width="100%" alt="02.3 Re-authorising a TV">
</p>

A set whose debugging prompt was dismissed (or that was reset, or had this
machine's key revoked) sits in `unauth` forever. Reconnecting does not help:
`adb` remembers the refusal and fails the handshake silently, with nothing on
the TV's screen. The **AUTH** button beside an `unauth` entry bounces the local
adb server, which forces a fresh key exchange and puts the prompt back up.

Bouncing the server drops *every* connected device for a moment, including your
other TVs. They reconnect on their next action, so the drop is brief. It is also
why AUTH only appears when it is the fix.

<a name="optional-hotkey"></a>
<p align="center">
  <img src="./assets/readme/sub-optional-hotkey.svg" width="100%" alt="02.4 Optional hotkey">
</p>

<p align="center">
  <img src="./assets/readme/code-hotkey.svg" width="100%" alt="In ~/.config/hypr/bindings.lua: o.bind SUPER + SHIFT + T, TV remote, omarchy-shell shell toggle io.github.swey-l1.atv-remote">
</p>

<details markdown="1">
<summary>Copy the binding</summary>

```lua
-- ~/.config/hypr/bindings.lua
o.bind("SUPER + SHIFT + T", "TV remote", "omarchy-shell shell toggle io.github.swey-l1.atv-remote")
```

</details>

<p align="center">
  <img src="./assets/readme/section-settings.svg" width="100%" alt="03 Settings: what shell.json holds">
</p>

<p align="center">
  <img src="./assets/readme/settings.svg" width="100%" alt="An example entry in shell.json: id io.github.swey-l1.atv-remote, tv1Label and tv1Address, tv2Label and tv2Address, activeSlot, pollSec, app1Label and app1Package, with a note on what each is for">
</p>

<details markdown="1">
<summary>Every key, with its default</summary>

| Key | Default | What |
|---|---|---|
| `tv1Label` / `tv1Address` | — | Name and `host:port` of the first TV |
| `tv2Label` / `tv2Address` | — | Second TV |
| `tv3Label` / `tv3Address` | — | Third TV |
| `activeSlot` | `0` | The slot being driven; the picker writes it |
| `pollSec` | `60` | Seconds between reachability checks |
| `app1Label` / `app1Package` | `APP1` | First shortcut button, e.g. `NFLX` / `com.netflix.ninja` |
| `app2Label` / `app2Package` | `APP2` | Second shortcut |
| `app3Label` / `app3Package` | `APP3` | Third shortcut |

</details>

You should not need to set `activeSlot` by hand. With every address empty the
shim falls back to the first connected adb device. The shortcut buttons are
settable from the pad; see [The picker](#the-picker).

The pad can list them for you, and `tv-remote apps` prints the same list from a
terminal. Android exposes app labels to other apps but not to `adb`, so the
picker shows a name derived from the package and leaves the button label yours
to set.

<a name="known-quirks"></a>
<p align="center">
  <img src="./assets/readme/sub-known-quirks.svg" width="100%" alt="03.1 Known quirks">
</p>

- **`%` in typed text is lossy.** Android's `input text` treats `%s` as a space
  with no escape for a literal `%`, so "100%sure" types as "100 ure". This is a
  framework limitation; the plugin cannot work around it.
- **Input picker varies by brand.** The plugin sends `KEYCODE_TV_INPUT` and then
  falls back to `android.media.tv.action.SETUP_INPUTS`. On Hisense the keycode is
  a no-op and the vendor source panel is only reachable through protected
  broadcasts ADB cannot send, so the fallback is what opens a picker there.
  Other brands may behave differently.
- **Power is one-way.** A TV that is off does not answer ADB, so the power key
  can turn it off but not on.
- **ADB over wifi drops when the TV sleeps.** Every action reconnects on demand,
  so this is usually invisible.

<a name="using-the-shim-directly"></a>
<p align="center">
  <img src="./assets/readme/sub-shim.svg" width="100%" alt="03.2 Using the shim directly">
</p>

`tv-remote` is a plain script and works on its own:

<p align="center">
  <img src="./assets/readme/code-shim.svg" width="100%" alt="Six terminal commands: with TV_ADB_ADDR set, tv-remote key, text with enter, clear, apps, status which prints up, down, unauth or noadb, and reauth">
</p>

<details markdown="1">
<summary>Copy the commands</summary>

```bash
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote key KEYCODE_DPAD_DOWN
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote text "jazz piano" enter
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote clear 30
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote apps       # launchable packages
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status     # up | down | unauth | noadb
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote reauth     # re-show the debugging prompt
```

</details>

<p align="center">
  <img src="./assets/readme/section-development.svg" width="100%" alt="04 Development: how it is built">
</p>

![architecture](docs/architecture.png)

How a key press reaches the TV. The second diagram is the file map: every QML
file once, and what each is built from.

![components](docs/components.png)

The third merges the two: every file and the whole path to the TV on one page.

![whole plugin](docs/plugin.png)

[`docs/architecture.html`](docs/architecture.html),
[`docs/components.html`](docs/components.html) and
[`docs/plugin.html`](docs/plugin.html) are the same three as interactive
pages: open them in a browser for guided views, search and export. All are
generated from the `.json` beside each with
[Archify](https://github.com/tt-a1i/archify); see `DEVELOPING.md` for the command.

The plugin is plain QML plus a shell script, so edits apply without a rebuild:

<p align="center">
  <img src="./assets/readme/code-dev.svg" width="100%" alt="Four terminal commands: edit Panel.qml in the installed plugin, omarchy restart shell, run test/tv-remote.sh, and omarchy plugin update io.github.swey-l1.atv-remote to pull new commits">
</p>

<details markdown="1">
<summary>Copy the commands</summary>

```bash
$EDITOR ~/.config/omarchy/plugins/io.github.swey-l1.atv-remote/Panel.qml
omarchy restart shell
./test/tv-remote.sh                 # the shim against a fake adb
omarchy plugin update io.github.swey-l1.atv-remote    # pull new commits
```

</details>

Files under `~/.config/omarchy/plugins/` hot-reload on save, but the bar widget
is mounted at startup, so a restart is the reliable way to see a change. The
`tv-remote` script needs no restart at all, and `./test/tv-remote.sh` checks it
against a fake `adb` without a TV in the room.

If you installed with `omarchy plugin add`, the directory is a git checkout, so
`omarchy plugin update io.github.swey-l1.atv-remote` pulls new commits. To remove it:

```bash
omarchy plugin remove io.github.swey-l1.atv-remote
```

That deletes the checkout and the widget's entry in the bar layout. The plugin
writes only its own entry in `shell.json`, and only when you act in the pad, so
nothing else of yours is touched on the way in or out.

---

<p align="center">
  <a href="https://github.com/oil-oil/beautify-github-readme"><img src="./assets/readme/made-with-beautify.svg" width="300" alt="README made with beautify-github-readme"></a>
</p>

<p align="center"><sub>MIT. See <a href="LICENSE">LICENSE</a>.</sub></p>
