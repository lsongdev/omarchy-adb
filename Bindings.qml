import QtQuick

// Every key binding, once. What a key does, the hint on the button that does
// the same thing, and the line in the shortcut list are all read from `keyMap`,
// so a key cannot end up doing one thing and being advertised as another --
// which had already happened: "+" worked as volume up and appeared in no list.
//
// The actions call back into the Panel, which owns the shim and the pad.
Item {
  property var panel: null

  // `mods` is matched exactly, so Shift+S and S, or Alt+1 and 1, are separate
  // entries and order does not matter.
  readonly property var keyMap: [
    { id: "dpadUp",    keys: [Qt.Key_W, Qt.Key_Up],          hint: "W or Up",        label: "Up",           act: function() { panel.key("KEYCODE_DPAD_UP") } },
    { id: "dpadDown",  keys: [Qt.Key_S, Qt.Key_Down],        hint: "S or Down",      label: "Down",         act: function() { panel.key("KEYCODE_DPAD_DOWN") } },
    { id: "dpadLeft",  keys: [Qt.Key_A, Qt.Key_Left],        hint: "A or Left",      label: "Left",         act: function() { panel.key("KEYCODE_DPAD_LEFT") } },
    { id: "dpadRight", keys: [Qt.Key_D, Qt.Key_Right],       hint: "D or Right",     label: "Right",        act: function() { panel.key("KEYCODE_DPAD_RIGHT") } },
    { id: "ok",        keys: [Qt.Key_Return, Qt.Key_Enter],  hint: "Enter",          label: "Select / OK",  act: function() { panel.key("KEYCODE_DPAD_CENTER") } },
    { id: "back",      keys: [Qt.Key_B, Qt.Key_Backspace],   hint: "B or Backspace", label: "Back",         act: function() { panel.key("KEYCODE_BACK") } },
    { id: "home",      keys: [Qt.Key_H],                     hint: "H",              label: "Home",         act: function() { panel.key("KEYCODE_HOME") } },
    { id: "menu",      keys: [Qt.Key_M],                     hint: "M",              label: "Menu",         act: function() { panel.key("KEYCODE_MENU") } },
    { id: "inputs",    keys: [Qt.Key_I],                     hint: "I",              label: "Inputs",       act: function() { panel.sh("inputs") } },
    { id: "clear",     keys: [Qt.Key_C],                     hint: "C",              label: "Clear the field", act: function() { panel.sh("clear") } },
    { id: "playPause", keys: [Qt.Key_P],                     hint: "P",              label: "Play / pause", act: function() { panel.key("KEYCODE_MEDIA_PLAY_PAUSE") } },
    { id: "rewind",    keys: [Qt.Key_R],                     hint: "R",              label: "Rewind",       act: function() { panel.key("KEYCODE_MEDIA_REWIND") } },
    { id: "forward",   keys: [Qt.Key_F],                     hint: "F",              label: "Fast-forward", act: function() { panel.key("KEYCODE_MEDIA_FAST_FORWARD") } },
    { id: "previous",  keys: [Qt.Key_BracketLeft],           hint: "[",              label: "Previous",     act: function() { panel.key("KEYCODE_MEDIA_PREVIOUS") } },
    { id: "next",      keys: [Qt.Key_BracketRight],          hint: "]",              label: "Next",         act: function() { panel.key("KEYCODE_MEDIA_NEXT") } },
    { id: "volDown",   keys: [Qt.Key_Minus],                 hint: "-",              label: "Volume down",  act: function() { panel.key("KEYCODE_VOLUME_DOWN") } },
    { id: "volUp",     keys: [Qt.Key_Equal, Qt.Key_Plus],    hint: "= or +",         label: "Volume up",    act: function() { panel.key("KEYCODE_VOLUME_UP") } },
    { id: "mute",      keys: [Qt.Key_X],                     hint: "X",              label: "Mute",         act: function() { panel.key("KEYCODE_VOLUME_MUTE") } },
    { id: "wake",      keys: [Qt.Key_W], mods: Qt.ShiftModifier, hint: "Shift+W",    label: "Wake",         act: function() { panel.key("KEYCODE_WAKEUP") } },
    { id: "power",     keys: [Qt.Key_S], mods: Qt.ShiftModifier, hint: "Shift+S",    label: "Power",        act: function() { panel.key("KEYCODE_POWER") } },
    { id: "app1",      keys: [Qt.Key_1],                     hint: "1",              label: "App shortcut 1", act: function() { panel.launchApp(1) } },
    { id: "app2",      keys: [Qt.Key_2],                     hint: "2",              label: "App shortcut 2", act: function() { panel.launchApp(2) } },
    { id: "app3",      keys: [Qt.Key_3],                     hint: "3",              label: "App shortcut 3", act: function() { panel.launchApp(3) } },
    { id: "type",      keys: [Qt.Key_T, Qt.Key_Slash],       hint: "T or /",         label: "Type at the TV", act: function() { panel.startTyping() } },
    { id: "nextTv",    keys: [Qt.Key_Tab],                   hint: "Tab",            label: "Next TV",      act: function() { panel.cycleTv() } },
    { id: "tv1",       keys: [Qt.Key_1], mods: Qt.AltModifier, hint: "Alt+1",        label: "Jump to TV 1", act: function() { panel.selectTv(0) } },
    { id: "tv2",       keys: [Qt.Key_2], mods: Qt.AltModifier, hint: "Alt+2",        label: "Jump to TV 2", act: function() { panel.selectTv(1) } },
    { id: "tv3",       keys: [Qt.Key_3], mods: Qt.AltModifier, hint: "Alt+3",        label: "Jump to TV 3", act: function() { panel.selectTv(2) } },
    { id: "close",     keys: [Qt.Key_Escape, Qt.Key_Q],      hint: "Esc or Q",       label: "Close",         act: function() { panel.close() } }
  ]

  function entryFor(id) {
    for (var i = 0; i < keyMap.length; i++) if (keyMap[i].id === id) return keyMap[i]
    return null
  }
  function hintFor(id)  { var e = entryFor(id); return e ? e.hint  : "" }
  function labelFor(id) { var e = entryFor(id); return e ? e.label : "" }
  function runAction(id) { var e = entryFor(id); if (e) e.act() }

  // The shortcut list, written once by the same table.
  readonly property var keyHelp: keyMap.map(function (e) { return e.hint + "  " + e.label })

  // Control mode. Returns true when the key was ours, so the caller can accept
  // it -- anything unclaimed falls through rather than being swallowed.
  function handleKey(ev) {
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
}
