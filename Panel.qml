import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// The bar icon and the remote pad. Up to three Android TVs, one driven at a
// time; ADB itself lives in Service.qml and the strip along the foot of the pad
// in SetPicker.qml.
//
//   left   = open the remote pad
//   right  = Inputs / source picker
//   middle = Home
//   scroll = volume
//
// With the pad open the keyboard drives the TV, modally: `keyMap` below is the
// single definition of every binding, and typing at the TV is entered
// deliberately so that single letters are free to be controls.
//
// The icon takes the theme's urgent colour when the set is unreachable.
// adb-over-wifi drops whenever a TV sleeps, and the shim reconnects on demand,
// so "unreachable" usually means asleep rather than broken.
//
// Glyphs are literal UTF-8, not \u escapes — these are 5-hex-digit codepoints
// and QML's \u takes exactly four.
Item {
  id: root

  property var bar
  property string moduleName: "atv.remote"
  property var settings

  // ---- the configured sets -------------------------------------------------
  //
  // Everything read from or written back to the widget's shell.json entry
  // lives in Config.qml. What follows re-exports the parts the pad and its
  // components use, the way tvState and reprobe() front Service below.
  Config {
    id: cfg
    bar: root.bar
    moduleName: root.moduleName
    settings: root.settings
  }

  readonly property int    maxSets:     cfg.maxSets
  readonly property var    tvs:         cfg.tvs
  readonly property int    activeIndex: cfg.activeIndex
  readonly property string tvAddress:   cfg.tvAddress
  readonly property int    pollSec:     cfg.setting("pollSec", 60)

  function setting(key, fallback)     { return cfg.setting(key, fallback) }
  function appKey(slot, part)         { return cfg.appKey(slot, part) }
  function freeSlot()                 { return cfg.freeSlot() }
  function selectTv(i)                { cfg.selectTv(i) }
  function cycleTv()                  { cfg.cycleTv() }
  function writeTv(slot, label, addr) { return cfg.writeTv(slot, label, addr) }
  function addTv(label, addr)         { return cfg.addTv(label, addr) }
  function removeTv(slot)             { return cfg.removeTv(slot) }
  function writeApp(slot, label, pkg) { return cfg.writeApp(slot, label, pkg) }
  function appName(pkg)               { return cfg.appName(pkg) }
  function appNiceName(pkg)           { return cfg.appNiceName(pkg) }
  function defaultAppLabel(pkg)       { return cfg.defaultAppLabel(pkg) }

  // ---- palette -------------------------------------------------------------

  // The pad's surfaces and status colours, named once. Every component file
  // draws with these, and a literal repeated across five files is one that
  // drifts the first time somebody adjusts it -- the AUTH button had already
  // ended up a shade brighter on hover than every other button.
  readonly property color surfaceIdle:        Qt.rgba(1, 1, 1, 0.04)
  readonly property color surfaceRaised:      Qt.rgba(1, 1, 1, 0.06)
  readonly property color surfaceButton:      Qt.rgba(1, 1, 1, 0.08)
  readonly property color surfaceHover:       Qt.rgba(1, 1, 1, 0.10)
  readonly property color surfaceButtonHover: Qt.rgba(1, 1, 1, 0.16)

  readonly property color okColour:   "#98c379"
  readonly property color warnColour: "#e5c07b"
  // Urgent comes from the theme; the literal is only a fallback for when the
  // bar has not handed one over yet.
  readonly property color badColour:  bar && bar.urgent ? bar.urgent : "#e06c75"

  // Text and its face come from the bar's theme; the literals are only for the
  // moment before the bar has handed itself over.
  readonly property color  textColour: bar ? bar.foreground : "white"
  readonly property string fontFamily: bar ? bar.fontFamily : "monospace"

  // The colour of anything clickable, so a row, a key and a list entry all
  // answer the pointer the same way. `rest` is what it shows when left alone;
  // the caller decides whether that is transparent, raised or marked.
  function surfaceFor(pressed, hovered, rest) {
    return pressed ? Color.popups.border
         : hovered ? surfaceHover
         : rest
  }

  // ---- metrics -------------------------------------------------------------
  //
  // Named once here rather than as Style.space(N) scattered over seven files,
  // where the same number means a key in one place and a list row in another and
  // nothing says which is which.
  readonly property int gap:        Style.space(6)    // between anything and its neighbour
  readonly property int tightGap:   Style.space(4)    // between the picker's own rows
  readonly property int inset:      Style.space(6)    // text away from an edge

  readonly property int keyWidth:   Style.space(38)   // one button of the D-pad grid
  readonly property int keyHeight:  Style.space(34)

  readonly property int rowHeight:     Style.space(24)  // a picker row, a form button
  readonly property int listRowHeight: Style.space(22)  // a row of the app list
  readonly property int helpRowHeight: Style.space(16)  // a line of the shortcut list
  readonly property int fieldHeight:   Style.space(26)  // a text field
  readonly property int hintHeight:    Style.space(14)  // the hover line along the foot

  readonly property int badgeWidth:  Style.space(30)   // the AUTH button on a row
  readonly property int badgeHeight: Style.space(18)

  // Both lists scroll; these bound the pad rather than letting it run off-screen.
  readonly property int appListHeight:  Style.space(150)
  readonly property int helpListHeight: Style.space(120)

  readonly property int padWidth: keyWidth * 3 + gap * 2

  property bool opened: false
  // "up" | "down" | "unauth" | "noadb" — noadb means adb isn't installed and
  // unauth means the set answered but nobody accepted its debugging prompt.
  // Both are distinct from a sleeping TV and each deserves its own message.
  // Not `state`: Item already has one, driving QML's own state machine. Naming
  // this one after it worked only because nothing here declares states or
  // transitions, and would collide confusingly the moment something did.
  readonly property string tvState: svc.state
  // Re-exposed so the component files can compare against names rather than
  // spell the shim's strings themselves.
  readonly property var stateName: svc.stateName
  readonly property bool online: tvState === stateName.up

  // Per-slot states, parallel to `tvs`. Only refreshed when the picker is open:
  // the poll timer probes the active set alone, so three configured TVs do not
  // mean three times the adb traffic on every tick.
  readonly property var tvStates: svc.states

  Service {
    id: svc
    address: root.tvAddress
    addresses: root.tvs.map(function (t) { return t.addr })
    pollSec: root.pollSec
  }

  // Last few typed strings, newest first. Up/Down in the field walks them.
  property var history: []
  property int historyIndex: -1

  function remember(t) {
    var h = history.slice()
    var at = h.indexOf(t)
    if (at !== -1) h.splice(at, 1)
    h.unshift(t)
    if (h.length > 10) h = h.slice(0, 10)
    history = h
    historyIndex = -1
  }

  implicitWidth: bar ? (bar.vertical ? bar.barSize : 24) : 24
  implicitHeight: bar ? bar.barSize : 26

  // ---- talking to the TV ---------------------------------------------------

  function sh(args) {
    if (!bar || typeof bar.run !== "function") return
    bar.run(svc.shimCmd(tvAddress, args))
  }
  function key(code) { sh("key " + code) }

  // The pad is modal, like a real remote: keys drive the TV, and typing at it is
  // something you enter deliberately. Without that, every letter would be text
  // bound for the TV's search box and none of them could be a control.
  property bool typing: false

  function startTyping() { typing = true; entry.focusMe() }
  function stopTyping()  { typing = false; keyCatcher.forceActiveFocus() }

  // Every binding, once. Behaviour, the hover hint on a button and the line in
  // the shortcut list all read from here, so a key cannot end up doing one thing
  // and being advertised as another -- which had already happened: "+" worked as
  // volume up and appeared in no list.
  //
  // `mods` is matched exactly, so Shift+S and S, or Alt+1 and 1, are separate
  // entries and order does not matter.
  readonly property var keyMap: [
    { id: "dpadUp",    keys: [Qt.Key_W, Qt.Key_Up],          hint: "W or Up",        label: "Up",           act: function() { key("KEYCODE_DPAD_UP") } },
    { id: "dpadDown",  keys: [Qt.Key_S, Qt.Key_Down],        hint: "S or Down",      label: "Down",         act: function() { key("KEYCODE_DPAD_DOWN") } },
    { id: "dpadLeft",  keys: [Qt.Key_A, Qt.Key_Left],        hint: "A or Left",      label: "Left",         act: function() { key("KEYCODE_DPAD_LEFT") } },
    { id: "dpadRight", keys: [Qt.Key_D, Qt.Key_Right],       hint: "D or Right",     label: "Right",        act: function() { key("KEYCODE_DPAD_RIGHT") } },
    { id: "ok",        keys: [Qt.Key_Return, Qt.Key_Enter],  hint: "Enter",          label: "Select / OK",  act: function() { key("KEYCODE_DPAD_CENTER") } },
    { id: "back",      keys: [Qt.Key_B, Qt.Key_Backspace],   hint: "B or Backspace", label: "Back",         act: function() { key("KEYCODE_BACK") } },
    { id: "home",      keys: [Qt.Key_H],                     hint: "H",              label: "Home",         act: function() { key("KEYCODE_HOME") } },
    { id: "menu",      keys: [Qt.Key_M],                     hint: "M",              label: "Menu",         act: function() { key("KEYCODE_MENU") } },
    { id: "inputs",    keys: [Qt.Key_I],                     hint: "I",              label: "Inputs",       act: function() { sh("inputs") } },
    { id: "clear",     keys: [Qt.Key_C],                     hint: "C",              label: "Clear the field", act: function() { sh("clear") } },
    { id: "playPause", keys: [Qt.Key_P],                     hint: "P",              label: "Play / pause", act: function() { key("KEYCODE_MEDIA_PLAY_PAUSE") } },
    { id: "rewind",    keys: [Qt.Key_R],                     hint: "R",              label: "Rewind",       act: function() { key("KEYCODE_MEDIA_REWIND") } },
    { id: "forward",   keys: [Qt.Key_F],                     hint: "F",              label: "Fast-forward", act: function() { key("KEYCODE_MEDIA_FAST_FORWARD") } },
    { id: "previous",  keys: [Qt.Key_BracketLeft],           hint: "[",              label: "Previous",     act: function() { key("KEYCODE_MEDIA_PREVIOUS") } },
    { id: "next",      keys: [Qt.Key_BracketRight],          hint: "]",              label: "Next",         act: function() { key("KEYCODE_MEDIA_NEXT") } },
    { id: "volDown",   keys: [Qt.Key_Minus],                 hint: "-",              label: "Volume down",  act: function() { key("KEYCODE_VOLUME_DOWN") } },
    { id: "volUp",     keys: [Qt.Key_Equal, Qt.Key_Plus],    hint: "= or +",         label: "Volume up",    act: function() { key("KEYCODE_VOLUME_UP") } },
    { id: "mute",      keys: [Qt.Key_X],                     hint: "X",              label: "Mute",         act: function() { key("KEYCODE_VOLUME_MUTE") } },
    { id: "wake",      keys: [Qt.Key_W], mods: Qt.ShiftModifier, hint: "Shift+W",    label: "Wake",         act: function() { key("KEYCODE_WAKEUP") } },
    { id: "power",     keys: [Qt.Key_S], mods: Qt.ShiftModifier, hint: "Shift+S",    label: "Power",        act: function() { key("KEYCODE_POWER") } },
    { id: "app1",      keys: [Qt.Key_1],                     hint: "1",              label: "App shortcut 1", act: function() { launchApp(1) } },
    { id: "app2",      keys: [Qt.Key_2],                     hint: "2",              label: "App shortcut 2", act: function() { launchApp(2) } },
    { id: "app3",      keys: [Qt.Key_3],                     hint: "3",              label: "App shortcut 3", act: function() { launchApp(3) } },
    { id: "type",      keys: [Qt.Key_T, Qt.Key_Slash],       hint: "T or /",         label: "Type at the TV", act: function() { startTyping() } },
    { id: "nextTv",    keys: [Qt.Key_Tab],                   hint: "Tab",            label: "Next TV",      act: function() { cycleTv() } },
    { id: "tv1",       keys: [Qt.Key_1], mods: Qt.AltModifier, hint: "Alt+1",        label: "Jump to TV 1", act: function() { selectTv(0) } },
    { id: "tv2",       keys: [Qt.Key_2], mods: Qt.AltModifier, hint: "Alt+2",        label: "Jump to TV 2", act: function() { selectTv(1) } },
    { id: "tv3",       keys: [Qt.Key_3], mods: Qt.AltModifier, hint: "Alt+3",        label: "Jump to TV 3", act: function() { selectTv(2) } },
    { id: "close",     keys: [Qt.Key_Escape, Qt.Key_Q],      hint: "Esc or Q",       label: "Close",         act: function() { close() } }
  ]

  function entryFor(id) {
    for (var i = 0; i < keyMap.length; i++) if (keyMap[i].id === id) return keyMap[i]
    return null
  }
  function hintFor(id)  { var e = entryFor(id); return e ? e.hint  : "" }
  function labelFor(id) { var e = entryFor(id); return e ? e.label : "" }
  function runAction(id) { var e = entryFor(id); if (e) e.act() }

  function launchApp(n) { sh("app " + Util.shellQuote(setting(appKey(n, "Package"), ""))) }

  // The shortcut list, written once by the same table.
  readonly property var keyHelp: keyMap.map(function (e) { return e.hint + "  " + e.label })

  // Control mode. Returns true when the key was ours, so the caller can accept
  // it -- anything unclaimed falls through rather than being swallowed.
  function handleKey(ev) {
    // A form open means the keyboard belongs to it. Without this, typing a name
    // fires controls at the TV: "Kitchen" sends Inputs on the i and flips into
    // typing mode on the t.
    if (picker.formOpen) return picker.handleFormKey(ev)

    var mods = ev.modifiers & (Qt.ShiftModifier | Qt.ControlModifier
                               | Qt.AltModifier | Qt.MetaModifier)
    for (var i = 0; i < keyMap.length; i++) {
      var e = keyMap[i]
      if (mods !== (e.mods || 0)) continue
      if (e.keys.indexOf(ev.key) === -1) continue
      e.act()
      return true
    }
    return false
  }

  // Opening always lands in control mode, so the pad behaves the same way every
  // time rather than depending on how it was left.
  onOpenedChanged: if (opened) { typing = false; Qt.callLater(keyCatcher.forceActiveFocus) }

  function open()  { opened = true }
  function close() { opened = false }
  function toggle() { opened = !opened }

  function reprobe()    { svc.reprobe() }
  function reprobeAll() { svc.reprobeAll() }

  // ---- apps ----------------------------------------------------------------

  // Launchable packages on the active set, filled in on demand.
  readonly property var appList: svc.appList
  readonly property bool appsLoading: svc.appsLoading

  function loadApps() { svc.loadApps() }

  // The bar's tooltip PopupWindow only draws when the hovered target belongs to
  // the bar window (targetBelongsToWindow in Bar.qml), and the pad is its own
  // layer-shell window -- so every bar.showTooltip call from in here was a
  // no-op. The pad carries its own hint line instead, which has the side
  // benefit of fitting a narrow column better than a floating bubble.
  property string hoverHint: ""
  function setHint(t) { if (t !== "") hoverHint = t }
  function clearHint(t) { if (hoverHint === t) hoverHint = "" }

  function reauth(i) { if (i >= 0 && i < tvs.length) svc.reauth(tvs[i].addr) }

  PadText {
    panel: root
    anchors.centerIn: parent
    text: "󰠹"
    // Colour, not just opacity: a dimmed icon on a dark bar is easy to miss.
    color: root.online ? root.textColour : root.badColour
    opacity: root.online ? (root.opened ? 1.0 : 0.85) : 0.9
    font.pixelSize: 14
    Behavior on opacity { NumberAnimation { duration: 120 } }
  }

  // The bar lays its own MouseArea (acceptedButtons: LeftButton) over every
  // module slot for drag-to-reorder. A MouseArea of ours claiming Right/Middle
  // competes with that for the grab, so left stays a MouseArea and the other
  // buttons use TapHandlers, which take passive grabs and are delivered
  // independently of the overlying area.
  MouseArea {
    anchors.fill: parent
    acceptedButtons: Qt.LeftButton
    hoverEnabled: true
    onEntered: if (root.bar && root.bar.showTooltip) root.bar.showTooltip(root, svc.stateMessage[root.tvState])
    onExited: if (root.bar && root.bar.hideTooltip) root.bar.hideTooltip(root)
    onClicked: root.toggle()
  }

  TapHandler {
    acceptedButtons: Qt.RightButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.sh("inputs")
  }

  // Scroll over the icon changes TV volume, matching how the audio widget
  // behaves. WheelHandler rather than MouseArea.onWheel so it composes with
  // the bar's own drag overlay the same way the TapHandlers do.
  WheelHandler {
    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
    onWheel: function(ev) {
      if (ev.angleDelta.y === 0) return
      root.key(ev.angleDelta.y > 0 ? "KEYCODE_VOLUME_UP" : "KEYCODE_VOLUME_DOWN")
    }
  }

  TapHandler {
    acceptedButtons: Qt.MiddleButton
    gesturePolicy: TapHandler.ReleaseWithinBounds
    onTapped: root.key("KEYCODE_HOME")
  }

  component Key: Rectangle {
    id: k
    property string glyph: ""
    property string label: ""
    // Naming the action is enough: the description, the shortcut shown on hover
    // and what pressing it does all come from the one table.
    property string action: ""
    property string tip: action !== "" ? root.labelFor(action) : ""
    property string keyHint: action !== "" ? root.hintFor(action) : ""
    property var onPress: null
    // Outlined while the key does something other than what its face says --
    // the shortcut buttons configure rather than launch in edit mode, and
    // nothing else on them would show that.
    property bool marked: false
    // Nothing configured behind it. Still pressable, so the hint can say why.
    property bool unset: false
    readonly property string hintText: tip === "" ? ""
      : (keyHint === "" ? tip : tip + "  [" + keyHint + "]")

    implicitWidth: root.keyWidth
    implicitHeight: root.keyHeight
    radius: Style.cornerRadius
    border.width: k.marked ? 1 : 0
    border.color: root.textColour
    opacity: k.unset ? 0.45 : 1.0
    color: root.surfaceFor(ma.pressed, ma.containsMouse,
                           k.marked ? root.surfaceHover : root.surfaceIdle)
    Behavior on color { ColorAnimation { duration: 90 } }

    PadText {
      panel: root
      anchors.centerIn: parent
      text: k.glyph !== "" ? k.glyph : k.label
      font.pixelSize: k.glyph !== "" ? 15 : 10
    }

    HintArea {
      id: ma
      panel: root
      anchors.fill: parent
      hint: k.hintText
      onClicked: { if (k.onPress) k.onPress(); else if (k.action !== "") root.runAction(k.action) }
    }
  }

  // KeyboardPanel, not PopupCard: PopupCard is an xdg-popup and only receives
  // keys after a click routes focus through its parent surface, so a text
  // field inside one never sees typing. KeyboardPanel is a layer-shell
  // PanelWindow with WlrKeyboardFocus and exposes the same subset of the
  // PopupCard API (anchorItem, owner, bar, open, padding, contentWidth/Height).
  KeyboardPanel {
    id: pad
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.opened
    // Layer-shell hands the surface keyboard focus, but Qt still needs an item
    // to make active, and it will not pick one on its own. Without this nothing
    // in the pad ever holds focus and forceActiveFocus has nothing to take it
    // from, which is why opening a form left the keyboard nowhere.
    focusTarget: keyCatcher
    contentWidth: pane.implicitWidth + padding * 2
    contentHeight: pane.implicitHeight + padding * 2

    // Zero-sized, and exists only to own the keyboard while the pad is in
    // control mode. A layer-shell panel still has to route keys to *something*,
    // and the text field cannot be it without swallowing every control.
    Item {
      id: keyCatcher
      width: 0
      height: 0
      // Whatever this does not claim goes to the open form's field. Focus alone
      // is not dependable here: the panel takes keyboard focus on demand, so
      // right after a form opens the keys can still arrive at this item.
      Keys.forwardTo: picker.activeInput ? [picker.activeInput] : []
      Keys.onPressed: function(ev) { if (root.handleKey(ev)) ev.accepted = true }
    }

    Column {
      id: pane
      spacing: root.gap

      Row {
        spacing: root.gap
        Key { glyph: "󰐥"; action: "power" }
        Key { label: "INPT"; action: "inputs" }
        Key { glyph: "󰋜"; action: "home" }
      }

      Row {
        spacing: root.gap
        Item { width: root.keyWidth; height: root.keyHeight }
        Key { glyph: "󰁝"; action: "dpadUp" }
        Item { width: root.keyWidth; height: root.keyHeight }
      }
      Row {
        spacing: root.gap
        Key { glyph: "󰁍"; action: "dpadLeft" }
        Key { label: "OK"; action: "ok" }
        Key { glyph: "󰁔"; action: "dpadRight" }
      }
      Row {
        spacing: root.gap
        Item { width: root.keyWidth; height: root.keyHeight }
        Key { glyph: "󰁅"; action: "dpadDown" }
        Item { width: root.keyWidth; height: root.keyHeight }
      }

      Row {
        spacing: root.gap
        Key { glyph: "󰁮"; action: "back" }
        Key { glyph: "󰕿"; action: "volDown" }
        Key { glyph: "󰕾"; action: "volUp" }
      }
      Row {
        spacing: root.gap
        Key { glyph: "󰝟"; action: "mute" }
        Key { glyph: "󰐊"; action: "playPause" }
        Key { glyph: "󰒫"; action: "rewind" }
      }

      Row {
        spacing: root.gap
        // One key per shortcut slot. The fallback label matches the manifest
        // default rather than naming an app nobody configured: a fresh install
        // used to show NFLX on a button with no package behind it.
        Repeater {
          model: root.maxSets
          Key {
            readonly property int slot: index + 1
            readonly property string pkg: root.setting(root.appKey(slot, "Package"), "")
            label: root.setting(root.appKey(slot, "Label"), "APP" + slot)
            action: "app" + slot
            marked: picker.editing
            unset: !picker.editing && pkg === ""
            tip: picker.editing ? "Choose the app for this button"
               : pkg === "" ? "Nothing set yet. Use Edit / remove to pick an app"
               : root.appNiceName(pkg)
            onPress: function() {
              if (picker.editing) { picker.startAppEdit(slot); return }
              root.launchApp(slot)
            }
          }
        }
      }

      // ---- type into whatever field has focus on the TV -----------------
      Row {
        spacing: root.gap

        Field {
          id: entry
          panel: root
          width: root.keyWidth * 2 + root.gap
          height: root.keyHeight
          fontSize: 11
          // Doubles as the only on-screen hint that the pad is modal.
          placeholder: "T to type\u2026"
          // Clicking into the field is the other way in to typing mode.
          onFocusedChanged: if (focused) root.typing = true

          onKey: function(ev) {
            switch (ev.key) {
            case Qt.Key_Return:
            case Qt.Key_Enter:  entry.send();      return true
            case Qt.Key_Up:     entry.recall(1);   return true
            case Qt.Key_Down:   entry.recall(-1);  return true
            // Escape hands the keyboard back to control mode rather than
            // closing the pad, so a mistyped search does not cost the session.
            case Qt.Key_Escape: root.stopTyping(); return true
            }
            return false
          }

          // Walk the history: Up goes further back, Down returns toward the
          // empty field. -1 means "not browsing".
          function recall(step) {
            if (root.history.length === 0) return
            var i = root.historyIndex + step
            if (i < -1) i = -1
            if (i > root.history.length - 1) i = root.history.length - 1
            root.historyIndex = i
            text = i === -1 ? "" : root.history[i]
            input.cursorPosition = text.length
          }

          // One shim call, not two. bar.run() is fire-and-forget, so sending
          // the text and the ENTER as separate calls races them — the ENTER
          // landed mid-string and submitted after the first character. The
          // trailing "enter" arg makes the shim sequence them in-process.
          function send() {
            var t = text
            if (t.length === 0) return
            root.sh("text " + Util.shellQuote(t) + " enter")
            root.remember(t)
            text = ""
          }
        }

        Key { label: "CLR"; action: "clear" }
      }

      SetPicker {
        id: picker
        panel: root
      }

      // Whatever the pointer is on, and the key that does the same thing.
      // Fixed height, so hovering never makes the pad jump about.
      PadText {
        panel: root
        width: root.padWidth
        height: root.hintHeight
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.hoverHint
        opacity: 0.55
        font.pixelSize: 9
      }
    }
  }
}
