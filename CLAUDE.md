# Android TV Remote

An Omarchy shell plugin that drives an Android TV over ADB from the bar: D-pad, volume,
input picker, app shortcuts, and a text field for typing into TV search boxes.

- `Panel.qml` — the bar widget and its pad. Plugin id `atv.remote`, `kinds: ["bar-widget"]`.
- `tv-remote` — a plain bash ADB shim: `key` / `text` / `clear` / `app` / `inputs` / `status` /
  `reauth`.
- `manifest.json` — declares the widget and its settings **schema**. Values live in the
  user's `~/.config/omarchy/shell.json`, never here.

The widget shells out to the script; the script owns all ADB. That split keeps the remote
usable from a terminal without the shell running, and makes the ADB half testable alone.

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

**Never commit a personal identifier — including in commit metadata.** Checking file
contents is not enough: `git config user.email` has leaked a real name and address into an
author field here before. Verify with
`git log --format='%an <%ae>' | sort -u` before pushing, and check screenshots for desktop
content before adding them to `docs/`.

## TV-side behaviour worth knowing

- **`KEYCODE_TV_INPUT` is a no-op on Hisense.** Its source panel (`com.hisense.mixbar`,
  `com.hisense.kpad`) exposes only broadcast receivers, and the relevant broadcasts are
  protected — ADB cannot send them. `am start -a android.media.tv.action.SETUP_INPUTS` opens
  the MediaTek picker instead. The shim tries the keycode first, then falls back, because
  other brands may behave the opposite way. **This is the least portable part of the plugin
  and has only been tested on one TV.**
- **`input text` treats `%s` as a space** with no escape for a literal `%`.
- **Power is one-way** — a TV that is off does not answer ADB.
- **ADB over wifi drops when the TV sleeps.** Every shim action reconnects on demand.
