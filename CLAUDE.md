# Android TV Remote

An Omarchy shell plugin that drives an Android TV over ADB from the bar: D-pad, volume,
input picker, app shortcuts, and a text field for typing into TV search boxes.

- `Panel.qml` — the bar widget and its pad. Plugin id `atv.remote`, `kinds: ["bar-widget"]`.
- `tv-remote` — a plain bash ADB shim: `key` / `text` / `clear` / `app` / `inputs` /
  `apps` / `status` / `reauth`.
- `manifest.json` — declares the widget and its settings **schema**. Values live in the
  user's `~/.config/omarchy/shell.json`, never here.

The widget shells out to the script; the script owns all ADB. That split keeps the remote
usable from a terminal without the shell running, and makes the ADB half testable alone.

## Setup

Needs omarchy with the Quickshell shell (`omarchy-shell`) and `adb`
(`pacman -S android-tools`). The TV needs **Developer options -> USB/Wireless debugging**
switched on and has to be reachable on the network.

```sh
omarchy plugin add https://github.com/swey-l1/omarchy-android-tv-remote --enable
```

`--enable` is what puts the widget into the bar layout in `shell.json`; without it the
plugin is installed but nothing appears. The installed directory
(`~/.config/omarchy/plugins/atv.remote`) is itself a git checkout, so
`omarchy plugin update atv.remote` pulls new commits straight into the running plugin.

Add a TV from the pad rather than by hand: open it, click the picker along the foot, then
**+ Add TV**. It writes the `tv1Label` / `tv1Address` pair into the widget's `shell.json`
entry, appending `:5555` to a bare IP. The TV shows **"Allow USB debugging?"** on the first
connection -- accept it and tick "Always allow from this computer", or the set sits in
`unauth` and the picker offers an **AUTH** button to put the prompt back.

Confirm the shim can reach it before touching anything else, since every other symptom
looks the same when it cannot:

```sh
TV_ADB_ADDR=<host:port> ~/.config/omarchy/plugins/atv.remote/tv-remote status   # want: up
```

### Working from a clone instead

Editing the installed checkout directly is the shortest loop. Working in a clone elsewhere
is fine, but the files still have to reach `~/.config/omarchy/plugins/atv.remote` to run at
all -- and copying over that directory leaves it dirty, at which point
`omarchy plugin update` refuses to fast-forward and reports "local changes" even though
nothing was edited there. Push first, `git checkout -- .` in the installed copy, then
update. Otherwise the two drift and it is not obvious which one the bar is running.

## Commands

```sh
# The shim is directly runnable — test ADB behaviour without the shell.
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status          # up | down | unauth | noadb
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote text "hi" enter

omarchy plugin validate .          # manifest against the plugin schema
omarchy restart shell              # apply a Panel.qml change
omarchy plugin update atv.remote   # pull commits into an installed checkout
```

## There are no unit tests — verify by looking

This is QML in a live compositor driving real hardware. Nothing here is unit-testable, so
**verify visually and never infer success from the absence of errors**:

```sh
grim -g "1150,0 450x30" /tmp/bar.png        # the bar icon (logical coords)
adb exec-out screencap -p > /tmp/tv.png     # what the TV actually shows
journalctl --user --since "30 seconds ago" | grep -i atv.remote
```

A clean log only proves nothing crashed. It does **not** prove an edit loaded — a silently
failed string replacement, or a file in the wrong directory, both log nothing.

Two traps worth knowing:

- **A QML syntax error makes the widget vanish from the bar**, and the only sign is
  `WARN qml: Plugin widget atv.remote failed: … Unexpected token` — no "Error:" and no
  stack. Grep for `WARN qml` or `Plugin widget .* failed`, not for `Error`.
- **Saving into `~/.config/omarchy/plugins/` does not reliably re-render an open pad.**
  The log says `Local plugin changed, reloading`, and the pad keeps drawing the previous
  instance — so a change appears not to work when it simply has not loaded. `omarchy
  restart shell`, then reopen the pad, is the only dependable way to see an edit.

## Hard rules

**Never write nerd-font glyphs as `\u` escapes.** QML's `\u` takes exactly four hex digits
and Material icons are five (`U+F0839`), so `"9"` silently becomes `U+F083` followed
by a literal `9`. Put the literal UTF-8 character in the file. Confirm a codepoint exists
before using it: `fc-list ":charset=F0839" family | grep -i "JetBrainsMono Nerd Font"`.

**Never chain two `bar.run()` calls that depend on order.** It is fire-and-forget — each
call is an independent detached process. Sending text and then ENTER as two calls makes the
TV submit after roughly the first character. Anything ordered must be one shim invocation.

**Never call `bar.shellQuote()`.** The bar README documents it; it does not exist anywhere
in the shell. Use `Util.shellQuote` from `qs.Commons`. Always quote anything reaching a
shell — user-typed text reaches two of them (local bash, then the device shell).

**`bar.showTooltip` does nothing from inside the pad.** The bar's tooltip window is
gated on `targetBelongsToWindow(target, barWindow)` (see `Bar.qml`), and the pad is its
own layer-shell window, so the call is accepted and silently draws nothing. Every `tip:`
on a pad button was dead for months before this was noticed. The pad shows hover text on
its own hint line instead, via `setHint()` / `clearHint()`. Only the bar icon itself, which
really is in the bar window, can use `bar.showTooltip`.

**The text field must not hold focus by default.** The pad is modal: `keyCatcher`
owns the keyboard in control mode so single letters can be remote keys, and `entry` only
takes it while `root.typing`. Binding `focus:` on the field instead means every control
key is swallowed as text bound for the TV's search box. A layer-shell panel still has to
route keys somewhere, which is why `keyCatcher` exists as a zero-sized item rather than
nothing at all.

**Never use `PopupCard` for anything that needs typing.** It is an xdg-popup and only
receives keys after a click routes focus through its parent surface. `KeyboardPanel`
(layer-shell + `WlrKeyboardFocus`) is the drop-in with a compatible API subset.

**Never put a real TV address, hostname or IP in `manifest.json`.** The manifest ships to
every user and `omarchy plugin update` overwrites it. Addresses belong in the user's
`shell.json`. Note that `entrySettings` does **not** merge manifest defaults at runtime, so
the widget must carry its own fallbacks — see `setting()` in `Panel.qml`.

**`updateEntryInline` REPLACES the entry, it does not merge.** The widget can
persist its own settings via `bar.shell.updateEntryInline(moduleName, settings)` --
the capability-scoped facade in `services/PluginShellApi.qml` allows it for the
plugin's own id. But the shell rebuilds the entry as `{ id }` plus exactly what it
is handed, so any key left out is dropped from `shell.json`. Adding a TV this way
would silently wipe the app shortcuts. Always send current settings merged with the
change -- see `persist()` in `Panel.qml`.

**Never assume settings exist at `Component.onCompleted`.** The bar injects them afterwards,
so the first reachability probe runs with an empty address and falls back to "first
connected device". `onTvAddressChanged` re-probes; without it the widget reports `up` for a
TV it is not addressing.

## TV-side behaviour worth knowing

- **`KEYCODE_TV_INPUT` is a no-op on Hisense.** Its source panel (`com.hisense.mixbar`,
  `com.hisense.kpad`) exposes only broadcast receivers, and the relevant broadcasts are
  protected — ADB cannot send them. `am start -a android.media.tv.action.SETUP_INPUTS` opens
  the MediaTek picker instead. The shim tries the keycode first, then falls back, because
  other brands may behave the opposite way. **This is the least portable part of the plugin
  and has only been tested on one TV.**
- **There are no app display names over ADB.** `PackageManager` hands labels to apps,
  not to `cmd package`, so `dumpsys package <pkg>` gives the package name back and nothing
  friendlier. `apps` returns packages and `appName()` in `Panel.qml` guesses a readable
  name from one; treat it as a suggestion, never as the app's real name.
- **`input text` treats `%s` as a space** with no escape for a literal `%`.
- **Power is one-way** — a TV that is off does not answer ADB.
- **ADB over wifi drops when the TV sleeps.** Every shim action reconnects on demand.
