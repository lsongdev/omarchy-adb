# Android TV Remote for Omarchy

Control one or more Android TVs from the Omarchy bar over ADB. The widget
provides a refreshable screen preview, D-pad, volume and media controls,
input selection, app shortcuts, text entry, and keyboard shortcuts.

> This repository is a personal fork of the original Android TV Remote plugin.
> The plugin ID is `org.lsong.atv-remote`, so it can be installed alongside the
> original `io.github.swey-l1.atv-remote` plugin.

![The remote pad with the screen preview open](docs/pad.png)

The remote pad as it opens: the TV screen preview at the top, then the D-pad,
volume and playback keys, the app shortcuts and the TV picker.

## Requirements

- Omarchy with the Quickshell-based `omarchy-shell`
- Arch package `android-tools`
- An Android TV with Developer options → USB/Wireless debugging enabled
- The TV reachable from this computer

Install ADB if needed:

```bash
sudo pacman -S android-tools
```

## Install from GitHub

```bash
omarchy plugin add https://github.com/lsongdev/omarchy-adb --enable
```

The `--enable` option places the widget in the bar. Open the widget, choose
the picker at the bottom, and select **+ Add TV**. Enter a name and the TV's
address. A bare IP address automatically uses port `5555`.

On the first connection, accept **Allow USB debugging?** on the TV and select
**Always allow from this computer**.

## Local development

From this repository's root, create a symlink in Omarchy's plugin directory:

```bash
PLUGIN_DIR="$HOME/.config/omarchy/plugins/org.lsong.atv-remote"
rm -rf "$PLUGIN_DIR"
ln -s "$PWD" "$PLUGIN_DIR"
omarchy plugin validate .
omarchy-shell shell rescanPlugins
omarchy plugin enable org.lsong.atv-remote right
omarchy restart shell
```

Because the plugin directory points directly at this checkout, source changes
are immediately available. Restart the shell after changing QML:

```bash
omarchy restart shell
```

The local install has its own plugin ID and does not replace the original
author's plugin. The symlink is intended for development; do not use
`omarchy plugin update` on it.

## Configuration

TVs can be added from the widget. Configuration is stored in the plugin entry
in `~/.config/omarchy/shell.json`. A minimal entry looks like this:

```json
{
  "id": "org.lsong.atv-remote",
  "tv1Label": "Living room",
  "tv1Address": "192.168.1.50:5555"
}
```

Supported settings include:

| Setting | Description |
|---|---|
| `tv1Label` / `tv1Address` | First TV name and `host:port` |
| `tv2Label` / `tv2Address` | Second TV |
| `tv3Label` / `tv3Address` | Third TV |
| `activeSlot` | Currently selected TV |
| `pollSec` | Reachability polling interval |
| `showScreen` | Show the screen preview; default `true`, set `false` to hide it |
| `screenRefreshSec` | Screen preview interval, from 1 to 30 seconds; default `2` |
| `app1..3Label` / `app1..3Package` | App shortcut labels and packages |

## Screen preview

The preview is always part of the remote pad. The plugin captures the current
TV screen over ADB and refreshes it every two seconds by default; click it to
refresh immediately.

To hide it, set `showScreen` to `false` in the plugin's entry in
`~/.config/omarchy/shell.json`, then restart the shell:

```json
{
  "id": "org.lsong.atv-remote",
  "tv1Label": "Living room",
  "tv1Address": "192.168.1.50:5555",
  "showScreen": false
}
```

`screenRefreshSec` adjusts the interval, from 1 to 30 seconds. Nothing is
captured while the preview is hidden.

The preview uses Android's `screencap` command. It is intended for checking the
current screen while using the remote; it is not a real-time video or audio
stream. Some DRM-protected video may appear black even though menus and other
apps remain visible.

## Keyboard controls

With the pad open:

| Key | Action |
|---|---|
| Arrow keys or `WASD` | D-pad |
| `Enter` | Select / OK |
| `B` or `Backspace` | Back |
| `H` | Home |
| `M` | Menu |
| `I` | Input picker |
| `P` | Play / pause |
| `R` / `F` | Rewind / fast-forward |
| `-` / `=` | Volume down / up |
| `X` | Mute |
| `1`, `2`, `3` | App shortcuts |
| `T` or `/` | Type text on the TV |
| `Tab` | Next configured TV |
| `Alt+1`, `Alt+2`, `Alt+3` | Select a TV directly |
| `Esc` or `Q` | Close the pad |
| `Shift+W` / `Shift+S` | Wake / power |

Optional Hyprland shortcut:

```lua
o.bind("SUPER + SHIFT + T", "TV remote", "omarchy-shell shell toggle org.lsong.atv-remote")
```

## Command-line shim

The `tv-remote` script can be used without the bar:

```bash
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote key KEYCODE_DPAD_DOWN
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote text "hello world" enter
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote apps
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote screenshot /tmp/tv-screen.png
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote reauth
```

Status values are `up`, `down`, `unauth`, and `noadb`.

## Planned features

The fork is intended for experimental features such as a higher-frame-rate
screen stream, improved device management, and additional TV controls. The
current screen feature is a two-second screenshot preview rather than video.

## Development checks

Run the ADB shim tests before committing:

```bash
./test/tv-remote.sh
```

The plugin is plain QML plus Bash; no build step is required. Restart
`omarchy-shell` after changing QML. Run `omarchy plugin validate .` to verify
the manifest.

## License

MIT. See [LICENSE](LICENSE).
