# Android TV Remote: developing it

Contributor notes: the layout, the loop, and the hard rules. Kept under a neutral name
because the plugin marketplace refuses a tracked `CLAUDE.md` inside an installed plugin,
treating it as an instruction channel to agents on users' machines. For Claude Code in a
clone, an untracked one-line `CLAUDE.md` containing `@DEVELOPING.md` imports this file; it
is gitignored. Not a symlink: `omarchy plugin validate` refuses symlinks in a plugin folder.

An Omarchy shell plugin that drives an Android TV over ADB from the bar: D-pad, volume,
input picker, app shortcuts, and a text field for typing into TV search boxes.

- `Panel.qml`: the bar widget: the icon, the typing mode, and the model the rest reads
  through `panel`. Plugin id `io.github.swey-l1.atv-remote`, `kinds: ["bar-widget"]`. It *is* a `Theme.qml`,
  which holds the palette and metrics, so `panel.gap` and `panel.textColour` are inherited.
- `Pad.qml`: the popup: the key grid, the type-at-the-TV field, the picker and the hint
  line, and the focus plumbing (`keyCatcher`).
- `Bindings.qml`: `keyMap`, the single definition of every key binding, and its dispatcher.
- `Service.qml`: everything that shells out to `tv-remote`: reachability, the app list,
  re-authorising. Takes the active address and the full list, hands back state.
- `Config.qml`: everything read from or written back to the widget's `shell.json` entry:
  the sets, the active slot, the shortcut buttons, and `persist()`. Panel re-exports what
  the components use, the same way it fronts Service.
- `SetPicker.qml`: the strip along the foot of the pad: the sets, the shortcut list, and
  whichever of its two forms is open. `TvForm.qml` adds or renames a set; `AppChooser.qml`
  points a shortcut button at an app. Each owns its own state and key handling.
- `PadKey.qml`, `TvRow.qml`, `Field.qml`, `TypeField.qml`, `Action.qml`, `FormButton.qml`,
  `HintArea.qml`, `PadText.qml`: the pieces those are built from. Each takes `panel`,
  since a component in its own file cannot reach the Panel lexically the way an inline one
  can. Theme values (`textColour`,
  `fontFamily`, the `surface*` colours, `surfaceFor()`) and metrics all come from the
  Panel, never as literals in a component; anything readable on the pad is a `PadText`,
  and any small filled button is a `FormButton`.
- `tv-remote`: a plain bash ADB shim: `key` / `text` / `clear` / `app` / `inputs` /
  `apps` / `status` / `reauth`. `test/tv-remote.sh` runs it against a fake `adb`.
- `manifest.json`: declares the widget and its settings **schema**. Values live in the
  user's `~/.config/omarchy/shell.json`, never here.
- `docs/architecture.json`, `docs/components.json`, `docs/plugin.json`: the flow map
  (how a key press reaches the TV), the file map (every QML file, once) and the merged
  map, as [Archify](https://github.com/tt-a1i/archify) specs. The `.html` and `.png`
  beside each are generated from it: change the spec, never the outputs. The PNGs come
  from `docs/diagram-shot.sh <name>`: a headless-chromium screenshot of the HTML with
  `docs/diagram-theme.css` injected, which hides the viewer chrome and maps Archify's
  theme variables onto the README palette, trimmed to the diagram panel. A new QML file
  is a new node in `components.json` and `plugin.json`.
  Regions are drawn as the bounding box of what they wrap plus `pad` on every side, so set
  `pad: 10` on each boundary, keep neighbouring columns at least 24 px apart, and keep a
  region's files in columns no other region uses on the same rows, or the boxes overlap.
- `assets/readme/`: the README's visual layer, all pure SVG in the pad's palette
  (`#111C18` / `#B8C497` / `#98C379`, from `Theme.qml`): the hero, the how-it-works strip,
  the section and sub-section banners, the keyboard, bar-icon and settings boards, the
  code cards, and the made-with signature. See **The README is a designed page** below.

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
(`~/.config/omarchy/plugins/io.github.swey-l1.atv-remote`) is itself a git checkout, so
`omarchy plugin update io.github.swey-l1.atv-remote` pulls new commits straight into the running plugin.

Add a TV from the pad rather than by hand: open it, click the picker along the foot, then
**+ Add TV**. It writes the `tv1Label` / `tv1Address` pair into the widget's `shell.json`
entry, appending `:5555` to a bare IP. The TV shows **"Allow USB debugging?"** on the first
connection. Accept it and tick "Always allow from this computer", or the set sits in
`unauth` and the picker offers an **AUTH** button to put the prompt back.

Confirm the shim can reach it before touching anything else, since every other symptom
looks the same when it cannot:

```sh
TV_ADB_ADDR=<host:port> ~/.config/omarchy/plugins/io.github.swey-l1.atv-remote/tv-remote status   # want: up
```

### Working from a clone instead

Editing the installed checkout directly is the shortest loop. Working in a clone elsewhere
is fine, but the files still have to reach `~/.config/omarchy/plugins/io.github.swey-l1.atv-remote` to run at
all, and copying over that directory leaves it dirty, at which point
`omarchy plugin update` refuses to fast-forward and reports "local changes" even though
nothing was edited there. Push first, `git checkout -- .` in the installed copy, then
update. Otherwise the two drift and it is not obvious which one the bar is running.

## Commands

```sh
# The shim is directly runnable: test ADB behaviour without the shell.
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote status          # up | down | unauth | noadb
TV_ADB_ADDR=192.168.1.50:5555 ./tv-remote text "hi" enter

./test/tv-remote.sh                # the shim against a fake adb, ~12 s

# Regenerate the architecture diagram after moving or renaming a file. Archify
# is not installed here; a clone runs in place with no npm install.
git clone --depth 1 https://github.com/tt-a1i/archify /tmp/archify
node /tmp/archify/archify/bin/archify.mjs deliver architecture docs/architecture.json \
  docs/architecture.html --quality showcase --repo-root .   # want: ok, 0 errors
node /tmp/archify/archify/bin/archify.mjs deliver architecture docs/components.json \
  docs/components.html --quality showcase --repo-root .
node /tmp/archify/archify/bin/archify.mjs deliver architecture docs/plugin.json \
  docs/plugin.html --quality showcase --repo-root .
for d in architecture components plugin; do docs/diagram-shot.sh $d; done   # the PNGs
omarchy plugin validate .          # manifest against the plugin schema
omarchy restart shell              # apply a Panel.qml change
omarchy plugin update io.github.swey-l1.atv-remote   # pull commits into an installed checkout
```

## Only the shim has tests; verify the rest by looking

`./test/tv-remote.sh` runs the shim against a fake `adb` (`test/fake-adb/adb`) and checks
what it prints and exactly what it asks the device shell to do: every reachability state,
reauth, and the quoting and sequencing of `text`, `clear` and `inputs`. Change the shim,
run it; add a verb, add a case.

Everything else is QML in a live compositor driving real hardware and is not
unit-testable, so **verify visually and never infer success from the absence of errors**:

```sh
grim -g "1150,0 450x30" /tmp/bar.png        # the bar icon (logical coords)
adb exec-out screencap -p > /tmp/tv.png     # what the TV actually shows
journalctl --user --since "30 seconds ago" | grep -i io.github.swey-l1.atv-remote
```

A clean log only proves nothing crashed. It does **not** prove an edit loaded: a silently
failed string replacement, or a file in the wrong directory, both log nothing.

Two traps worth knowing:

- **A QML syntax error makes the widget vanish from the bar**, and the only sign is
  `WARN qml: Plugin widget io.github.swey-l1.atv-remote failed: … Unexpected token`, with no "Error:" and no
  stack. Grep for `WARN qml` or `Plugin widget .* failed`, not for `Error`.
- **Saving into `~/.config/omarchy/plugins/` does not reliably re-render an open pad.**
  The log says `Local plugin changed, reloading`, and the pad keeps drawing the previous
  instance, so a change appears not to work when it simply has not loaded. `omarchy
  restart shell`, then reopen the pad, is the only dependable way to see an edit.

## Hard rules

**Never write nerd-font glyphs as `\u` escapes.** QML's `\u` takes exactly four hex digits
and Material icons are five (`U+F0839`), so `"9"` silently becomes `U+F083` followed
by a literal `9`. Put the literal UTF-8 character in the file. Confirm a codepoint exists
before using it: `fc-list ":charset=F0839" family | grep -i "JetBrainsMono Nerd Font"`.

**Never chain two `bar.run()` calls that depend on order.** It is fire-and-forget: each
call is an independent detached process. Sending text and then ENTER as two calls makes the
TV submit after roughly the first character. Anything ordered must be one shim invocation.

**Never call `bar.shellQuote()`.** The bar README documents it; it does not exist anywhere
in the shell. Use `Util.shellQuote` from `qs.Commons`. Always quote anything reaching a
shell: user-typed text reaches two of them (local bash, then the device shell).

**`bar.showTooltip` does nothing from inside the pad.** The bar's tooltip window is
gated on `targetBelongsToWindow(target, barWindow)` (see `Bar.qml`), and the pad is its
own layer-shell window, so the call is accepted and silently draws nothing. Every `tip:`
on a pad button was dead for months before this was noticed. The pad shows hover text on
its own hint line instead: use a `HintArea` rather than a bare `MouseArea`, which reports
through `panel.setHint()` / `clearHint()` for you. Only the bar icon itself, which really
is in the bar window, can use `bar.showTooltip`.

**Every key binding lives in `keyMap` in `Bindings.qml`, and only there.** What a key does,
the shortcut shown when hovering a button, and the line in the shortcut list are all read
from it. Adding a binding anywhere else puts the pad's behaviour and its own documentation
out of step, which is how `+` ended up working as volume up while appearing in no list.
Buttons name an action (`action: "volUp"`) rather than repeating the keycode.

The README holds two copies that cannot read from `keyMap`: the keyboard board
(`assets/readme/keyboard.svg`, the bound keys drawn on keycaps) and the table folded under
it. Both drift: the table was still missing `+` after the code stopped being wrong. Change a
binding, change both.

**The text field must not hold focus by default.** The pad is modal: `keyCatcher` in
`Pad.qml` owns the keyboard in control mode so single letters can be remote keys, and the
`TypeField` only takes it while the Panel's `typing` is on. Binding `focus:` on the field instead means every control
key is swallowed as text bound for the TV's search box. A layer-shell panel still has to
route keys somewhere, which is why `keyCatcher` exists as a zero-sized item rather than
nothing at all.

**A field's keys go through `Field`'s `onKey`, never `Keys.on*` on the field.** Keys reach
a field by two routes: directly while it holds focus, and forwarded from `keyCatcher` when
the panel has not granted focus yet. `onKey` sees both, and returning `true` claims the key.
Handling Return or Escape with a `Keys.onReturnPressed` on the field instead only covers
the focused route, and the forwarded one silently does something else, which is how the
add-TV form once advanced its forwarding target without moving focus. The forms hand every
key to `handleFormKey` in `SetPicker.qml`; the type-at-the-TV entry has its own `onKey`.

**Never use `PopupCard` for anything that needs typing.** It is an xdg-popup and only
receives keys after a click routes focus through its parent surface. `KeyboardPanel`
(layer-shell + `WlrKeyboardFocus`) is the drop-in with a compatible API subset.

**Never put a real TV address, hostname or IP in `manifest.json`.** The manifest ships to
every user and `omarchy plugin update` overwrites it. Addresses belong in the user's
`shell.json`. Note that `entrySettings` does **not** merge manifest defaults at runtime, so
the widget must carry its own fallbacks; see `setting()` in `Config.qml`.

**`updateEntryInline` REPLACES the entry, it does not merge.** The widget can
persist its own settings via `bar.shell.updateEntryInline(moduleName, settings)` --
the capability-scoped facade in `services/PluginShellApi.qml` allows it for the
plugin's own id. But the shell rebuilds the entry as `{ id }` plus exactly what it
is handed, so any key left out is dropped from `shell.json`. Adding a TV this way
would silently wipe the app shortcuts. Always send current settings merged with the
change; see `persist()` in `Config.qml`.

**Never assume settings exist at `Component.onCompleted`.** The bar injects them afterwards,
so the first reachability probe runs with an empty address and falls back to "first
connected device". `onTvAddressChanged` re-probes; without it the widget reports `up` for a
TV it is not addressing.

## The README is a designed page

Built with the [beautify-github-readme](https://github.com/oil-oil/beautify-github-readme)
skill (a clone under `/tmp` works; `npx skills add` is blocked here). Its rules, as applied:

- **Every heading is a banner SVG**, numbered `01`..`04` for sections and `01.1`.. for
  sub-sections; there are no Markdown headings left. Internal links therefore point at
  `<a name="…">` anchors placed above the banner. A new section needs a banner drawn in the
  same style: 1200×150 (sections) or 1200×84 (sub-sections).
- **Every table and code block has a visual above it and stays in Markdown beneath it**, in
  `<details markdown="1">` (the install command stays visible). Commands are never only in
  an image. A new code block gets a card: header line `language · where it runs`, `$`
  prompt for shell lines, `xml:space="preserve"` on lines with aligned comments.
- **The bar icon in the mouse board is the real glyph**: the outline of Material
  `md-television_box` (U+F0839) taken from the Nerd Font with fontTools, not a drawing.
- **Preview before committing.** GitHub is not available offline, so: python-markdown with
  `tables`, `fenced_code`, `md_in_html` (needed for the details blocks), a GitHub-like
  stylesheet at 900 px, headless chromium, then look at every changed region. Run the
  skill's `scripts/audit_readme.py README.md` too. Type sizes: essential text ≥ 20 SVG
  units on a 1200 canvas, labels ≥ 18.
- Screenshots of the pad: `docs/pad.png` (as it opens), `docs/screenshot.png` (picker
  expanded), `docs/edit-mode.png`. Retake all three when the pad's look changes; the
  no-click method is in the project log in the vault.

## TV-side behaviour worth knowing

- **`KEYCODE_TV_INPUT` is a no-op on Hisense.** Its source panel (`com.hisense.mixbar`,
  `com.hisense.kpad`) exposes only broadcast receivers, and the relevant broadcasts are
  protected, so ADB cannot send them. `am start -a android.media.tv.action.SETUP_INPUTS` opens
  the MediaTek picker instead. The shim tries the keycode first, then falls back, because
  other brands may behave the opposite way. **This is the least portable part of the plugin
  and has only been tested on one TV.**
- **There are no app display names over ADB.** `PackageManager` hands labels to apps,
  not to `cmd package`, so `dumpsys package <pkg>` gives the package name back and nothing
  friendlier. `apps` returns packages and `appName()` in `Config.qml` guesses a readable
  name from one; treat it as a suggestion, never as the app's real name.
- **`input text` treats `%s` as a space** with no escape for a literal `%`.
- **Power is one-way.** A TV that is off does not answer ADB.
- **ADB over wifi drops when the TV sleeps.** Every shim action reconnects on demand.
