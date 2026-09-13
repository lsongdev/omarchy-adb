import QtQuick
import qs.Commons

// The strip along the foot of the pad. Four things share it, one at a time:
// the configured sets and their reachability, the add/rename form, the app
// chooser for the three shortcut buttons, and the list of keyboard shortcuts.
//
// It sits at the bottom so it reads as context for the remote above it rather
// than as more controls. Collapsed it is a single line naming the set being
// driven; expanded it lists every set, and edit mode turns a click on a row
// into a rename rather than a switch.
//
// Keys arrive from the Panel rather than through focus: the pad is a
// layer-shell surface that takes keyboard focus on demand, so `activeInput`
// says where they should go.
Column {
  id: picker

  // The Panel this belongs to: the sets, the settings writer, the shim and the
  // hint line all live there.
  property var panel: null

  // Which input the pad should send keys to while a form is open. The pad takes
  // keyboard focus on demand, so it forwards rather than relying on focus, and
  // it cannot reach these ids from outside this file.
  readonly property var activeInput: appFormOpen ? appLabelField.input
                                   : !tvFormOpen ? null
                                   : formField === 0 ? nameField.input : addrField.input

  property bool expanded: false
  property bool adding: false
  // While on, clicking a row opens it for rename/remove instead of
  // switching to it. A mode rather than per-row buttons because the pad
  // is three keys wide and the rows already collide at that width.
  property bool editing: false
  property bool showKeys: false
  // Expandable when there is something to expand to: another set, or a
  // free slot to add one into.
  readonly property bool hasMore: panel.tvs.length > 1 || panel.freeSlot() !== 0
  spacing: panel.tightGap

  // Probing three TVs costs three adb round-trips, so it happens when the
  // list is actually being looked at rather than on every poll tick.
  onExpandedChanged: if (expanded) panel.reprobeAll()

  // 0 while adding, otherwise the slot being renamed. The form is the
  // same either way; only where it writes differs.
  property int editSlot: 0
  // 0 while closed, else which shortcut button is being pointed at an app.
  property int appSlot: 0
  property string appPkg: ""
  readonly property bool appFormOpen: appSlot !== 0
  readonly property bool tvFormOpen: adding || editSlot !== 0
  // Union: used for releasing the type-at-the-TV field's focus, not for
  // deciding which form to draw.
  readonly property bool formOpen: tvFormOpen || appFormOpen
  // Whatever form is open has to divide its row evenly, and only the rename
  // form has three buttons: DELETE exists nowhere else.
  readonly property int buttonCount: (tvFormOpen && editSlot !== 0) ? 3 : 2
  readonly property real buttonWidth:
    (panel.padWidth - panel.gap * (buttonCount - 1)) / buttonCount

  // Which field of the open form the keys should reach. Focus is not
  // dependable inside a panel that takes keyboard focus on demand, so the
  // form navigates from the key catcher instead of from the fields.
  property int formField: 0

  // Every key a form sees comes through here, whether the field holds focus or
  // keyCatcher forwards it. Returns true when the key was the form's.
  function handleFormKey(ev) {
    if (ev.key === Qt.Key_Escape) { closeForm(); return true }
    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
      if (appFormOpen) commitAppForm()
      else if (formField === 0) focusField(1)
      else commitForm()
      return true
    }
    return false
  }

  // Both the forwarding target and the visible focus move together, so it
  // does not matter which route the next key takes.
  function focusField(n) {
    formField = n
    var f = n === 0 ? nameField : addrField
    f.focusMe()
  }

  // The add and rename forms are the same form; slot 0 means adding.
  function openTvForm(slot, label, addr) {
    appSlot = 0
    appPkg = ""
    editSlot = slot
    adding = slot === 0
    nameField.text = label
    addrField.text = addr
    focusField(0)
  }
  function startAdd() { openTvForm(0, "", "") }
  function startEdit(i) {
    if (i < 0 || i >= panel.tvs.length) return
    openTvForm(panel.tvs[i].slot, panel.tvs[i].label, panel.tvs[i].addr)
  }
  function startAppEdit(slot) {
    adding = false
    editSlot = 0
    appSlot = slot
    appPkg = panel.setting(panel.appKey(slot, "Package"), "")
    appLabelField.text = panel.setting(panel.appKey(slot, "Label"), "")
    panel.loadApps()
    appLabelField.focusMe()
  }

  // Closes whichever form is open. Only one ever is, so there is nothing to
  // gain from knowing which.
  function closeForm() {
    adding = false
    editSlot = 0
    appSlot = 0
    appPkg = ""
    panel.stopTyping()
  }
  // After a write that changed the sets: the states are stale until re-probed.
  function closeAndReprobe() {
    closeForm()
    Qt.callLater(panel.reprobeAll)
  }

  function commitAppForm() {
    if (appPkg === "") return
    panel.writeApp(appSlot, appLabelField.text, appPkg)
    closeForm()
  }
  function commitForm() {
    var ok = editSlot !== 0
      ? panel.writeTv(editSlot, nameField.text, addrField.text)
      : panel.addTv(nameField.text, addrField.text)
    if (ok) closeAndReprobe()
  }
  function deleteForm() {
    if (editSlot === 0) return
    panel.removeTv(editSlot)
    editing = false
    closeAndReprobe()
  }

  TvRow {
    panel: picker.panel
    visible: !picker.expanded && panel.tvs.length > 0
    idx: panel.activeIndex
    trailing: picker.hasMore ? "▸" : ""
    onActivate: function() { if (picker.hasMore) picker.expanded = true }
  }

  Repeater {
    model: picker.expanded ? panel.tvs.length : 0
    TvRow {
      panel: picker.panel
      idx: index
      editMode: picker.editing
      trailing: picker.editing ? "edit" : (index === panel.activeIndex ? "▾" : "")
      onActivate: function() {
        if (picker.editing) { picker.startEdit(index); return }
        panel.selectTv(index)
        picker.expanded = false
      }
    }
  }

  // With no sets configured at all there is nothing to expand, so the add
  // row stands in for the picker entirely -- otherwise the only way to
  // get a first TV in would be to hand-edit shell.json.
  Action {
    panel: picker.panel
    visible: !picker.formOpen && panel.freeSlot() !== 0
             && (picker.expanded || panel.tvs.length === 0)
    label: "+ Add TV"
    onPress: function() { picker.startAdd() }
  }

  Action {
    panel: picker.panel
    visible: !picker.formOpen && picker.expanded && panel.tvs.length > 0
    label: picker.editing ? "Done" : "Edit / remove"
    onPress: function() { picker.editing = !picker.editing }
  }

  // Hover-only: there is nothing to click, it is just where the bindings
  // that have no button of their own are written down.
  Action {
    panel: picker.panel
    visible: !picker.formOpen && picker.expanded
    label: picker.showKeys ? "Hide shortcuts" : "Keyboard shortcuts"
    tip: picker.showKeys ? "Hide the list" : "Show every key"
    onPress: function() { picker.showKeys = !picker.showKeys }
  }

  ListView {
    visible: picker.showKeys && picker.expanded && !picker.formOpen
    width: panel.padWidth
    height: panel.helpListHeight
    clip: true
    model: panel.keyHelp
    boundsBehavior: Flickable.StopAtBounds
    // Reopening kept whatever scroll position it was left at, which shows
    // the list starting halfway down its own contents.
    onVisibleChanged: if (visible) positionViewAtBeginning()

    delegate: PadText {
      panel: picker.panel
      width: panel.padWidth
      height: panel.helpRowHeight
      verticalAlignment: Text.AlignVCenter
      leftPadding: panel.inset
      elide: Text.ElideRight
      text: modelData
      opacity: 0.72
      font.pixelSize: 9
    }
  }

  Field {
    panel: picker.panel
    id: nameField
    visible: picker.tvFormOpen
    placeholder: "name (e.g. Bedroom)"
    onKey: function(ev) { return picker.handleFormKey(ev) }
  }
  Field {
    panel: picker.panel
    id: addrField
    visible: picker.tvFormOpen
    placeholder: "192.168.1.50  (:5555 assumed)"
    onKey: function(ev) { return picker.handleFormKey(ev) }
  }
  Row {
    visible: picker.tvFormOpen
    spacing: panel.gap

    FormButton {
      panel: picker.panel
      width: picker.buttonWidth
      label: "SAVE"
      // Nothing to save without an address, and going flat says so more
      // clearly than writing a half-configured set into shell.json.
      active: addrField.text.trim() !== ""
      onPress: function() { picker.commitForm() }
    }
    FormButton {
      panel: picker.panel
      visible: picker.editSlot !== 0
      width: picker.buttonWidth
      label: "DELETE"
      onPress: function() { picker.deleteForm() }
    }
    FormButton {
      panel: picker.panel
      width: picker.buttonWidth
      label: "CANCEL"
      onPress: function() { picker.closeForm() }
    }
  }

  // ---- point a shortcut button at an app ---------------------------
  Field {
    panel: picker.panel
    id: appLabelField
    visible: picker.appFormOpen
    placeholder: "button label (e.g. NFLX)"
    onKey: function(ev) { return picker.handleFormKey(ev) }
  }

  PadText {
    panel: picker.panel
    visible: picker.appFormOpen
    width: panel.padWidth
    elide: Text.ElideMiddle
    text: picker.appPkg === ""
          ? (panel.appsLoading ? "reading apps from the TV\u2026" : "pick an app below")
          : picker.appPkg
    opacity: 0.45
    font.pixelSize: 9
  }

  // Bounded and scrolling rather than a plain Column: a TV can carry
  // dozens of launchable packages, and the pad would run off the screen.
  ListView {
    visible: picker.appFormOpen
    width: panel.padWidth
    height: panel.appListHeight
    clip: true
    model: panel.appList
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      width: panel.padWidth
      height: panel.listRowHeight
      radius: Style.cornerRadius
      color: panel.surfaceFor(appMa.pressed, appMa.containsMouse,
                              modelData === picker.appPkg ? panel.surfaceRaised : "transparent")
      Behavior on color { ColorAnimation { duration: 90 } }

      PadText {
        panel: picker.panel
        anchors.left: parent.left
        anchors.leftMargin: panel.inset
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - panel.inset * 2
        elide: Text.ElideRight
        text: panel.appName(modelData)
        opacity: modelData === picker.appPkg ? 1.0 : 0.72
        font.pixelSize: 10
      }

      HintArea {
        id: appMa
        panel: picker.panel
        anchors.fill: parent
        // The derived name is a guess, so the real package is one hover away.
        hint: modelData
        onClicked: {
          picker.appPkg = modelData
          if (appLabelField.text.trim() === "")
            appLabelField.text = panel.defaultAppLabel(modelData)
        }
      }
    }
  }

  Row {
    visible: picker.appFormOpen
    spacing: panel.gap

    FormButton {
      panel: picker.panel
      width: picker.buttonWidth
      label: "SAVE"
      active: picker.appPkg !== ""
      onPress: function() { picker.commitAppForm() }
    }
    FormButton {
      panel: picker.panel
      width: picker.buttonWidth
      label: "CANCEL"
      onPress: function() { picker.closeForm() }
    }
  }
}
