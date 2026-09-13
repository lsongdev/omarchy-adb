import QtQuick
import qs.Commons

// ---- which set the pad is driving ---------------------------------
// Bottom of the pad, so it reads as context for everything above it
// rather than as another control. Collapsed it is a single line; expanded
// it lists every configured set with its own reachability.
Column {
  // The Panel this belongs to: the sets, the settings writer, the shim and the
  // hint line all live there.
  property var panel: null

  // Which input the pad should send keys to while a form is open. The pad takes
  // keyboard focus on demand, so it forwards rather than relying on focus, and
  // it cannot reach these ids from outside this file.
  readonly property var activeInput: appFormOpen ? appLabelField.input
                                   : !tvFormOpen ? null
                                   : formField === 0 ? nameField.input : addrField.input

  id: picker
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
  spacing: Style.space(4)

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
  // DELETE only exists when editing, and the row has to divide evenly.
  readonly property int buttonCount: editSlot !== 0 ? 3 : 2
  readonly property real buttonWidth:
    (panel.padWidth - Style.space(6) * (buttonCount - 1)) / buttonCount

  // Which field of the open form the keys should reach. Focus is not
  // dependable inside a panel that takes keyboard focus on demand, so the
  // form navigates from the key catcher instead of from the fields.
  property int formField: 0

  function handleFormKey(ev) {
    if (ev.key === Qt.Key_Escape) {
      if (appFormOpen) closeAppForm()
      else closeForm()
      return true
    }
    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) {
      if (appFormOpen) { commitAppForm(); return true }
      if (formField === 0) { formField = 1; return true }
      commitForm()
      return true
    }
    return false
  }

  function startAdd() {
    editSlot = 0
    nameField.text = ""
    addrField.text = ""
    adding = true
    formField = 0
    nameField.focusMe()
  }
  function startAppEdit(slot) {
    adding = false
    editSlot = 0
    appSlot = slot
    appPkg = panel.setting("app" + slot + "Package", "")
    appLabelField.text = panel.setting("app" + slot + "Label", "")
    panel.loadApps()
    appLabelField.focusMe()
  }
  function closeAppForm() {
    appSlot = 0
    appPkg = ""
    panel.stopTyping()
  }
  function commitAppForm() {
    if (appPkg === "") return
    panel.writeApp(appSlot, appLabelField.text, appPkg)
    closeAppForm()
  }

  function startEdit(i) {
    if (i < 0 || i >= panel.tvs.length) return
    adding = false
    nameField.text = panel.tvs[i].label
    addrField.text = panel.tvs[i].addr
    editSlot = panel.tvs[i].slot
    formField = 0
    nameField.focusMe()
  }
  function closeForm() {
    adding = false
    editSlot = 0
    appSlot = 0
    panel.stopTyping()
  }
  function commitForm() {
    var ok = editSlot !== 0
      ? panel.writeTv(editSlot, nameField.text, addrField.text)
      : panel.addTv(nameField.text, addrField.text)
    if (!ok) return
    closeForm()
    Qt.callLater(panel.reprobeAll)
  }
  function deleteForm() {
    if (editSlot === 0) return
    panel.removeTv(editSlot)
    closeForm()
    editing = false
    Qt.callLater(panel.reprobeAll)
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
    height: Style.space(120)
    clip: true
    model: panel.keyHelp
    boundsBehavior: Flickable.StopAtBounds
    // Reopening kept whatever scroll position it was left at, which shows
    // the list starting halfway down its own contents.
    onVisibleChanged: if (visible) positionViewAtBeginning()

    delegate: Text {
      width: panel.padWidth
      height: Style.space(16)
      verticalAlignment: Text.AlignVCenter
      leftPadding: Style.space(6)
      elide: Text.ElideRight
      text: modelData
      color: panel.bar ? panel.bar.foreground : "white"
      opacity: 0.72
      font.family: panel.bar ? panel.bar.fontFamily : "monospace"
      font.pixelSize: 9
    }
  }

  Field {
    panel: picker.panel
    id: nameField
    visible: picker.tvFormOpen
    placeholder: "name (e.g. Bedroom)"
    Keys.onReturnPressed: addrField.focusMe()
    Keys.onEnterPressed: addrField.focusMe()
    Keys.onEscapePressed: picker.closeForm()
  }
  Field {
    panel: picker.panel
    id: addrField
    visible: picker.tvFormOpen
    placeholder: "192.168.1.50  (:5555 assumed)"
    Keys.onReturnPressed: picker.commitForm()
    Keys.onEnterPressed: picker.commitForm()
    Keys.onEscapePressed: picker.closeForm()
  }
  Row {
    visible: picker.tvFormOpen
    spacing: Style.space(6)

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
    Keys.onEscapePressed: picker.closeAppForm()
    Keys.onReturnPressed: picker.commitAppForm()
    Keys.onEnterPressed: picker.commitAppForm()
  }

  Text {
    visible: picker.appFormOpen
    width: panel.padWidth
    elide: Text.ElideMiddle
    text: picker.appPkg === ""
          ? (panel.appsLoading ? "reading apps from the TV\u2026" : "pick an app below")
          : picker.appPkg
    color: panel.bar ? panel.bar.foreground : "white"
    opacity: 0.45
    font.family: panel.bar ? panel.bar.fontFamily : "monospace"
    font.pixelSize: 9
  }

  // Bounded and scrolling rather than a plain Column: a TV can carry
  // dozens of launchable packages, and the pad would run off the screen.
  ListView {
    visible: picker.appFormOpen
    width: panel.padWidth
    height: Style.space(150)
    clip: true
    model: panel.appList
    boundsBehavior: Flickable.StopAtBounds

    delegate: Rectangle {
      width: panel.padWidth
      height: Style.space(22)
      radius: Style.cornerRadius
      color: appMa.pressed ? Color.popups.border
           : appMa.containsMouse ? Qt.rgba(1, 1, 1, 0.10)
           : modelData === picker.appPkg ? Qt.rgba(1, 1, 1, 0.06)
           : "transparent"

      Text {
        anchors.left: parent.left
        anchors.leftMargin: Style.space(6)
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - Style.space(12)
        elide: Text.ElideRight
        text: panel.appName(modelData)
        color: panel.bar ? panel.bar.foreground : "white"
        opacity: modelData === picker.appPkg ? 1.0 : 0.72
        font.family: panel.bar ? panel.bar.fontFamily : "monospace"
        font.pixelSize: 10
      }

      MouseArea {
        id: appMa
        anchors.fill: parent
        hoverEnabled: true
        // The derived name is a guess, so the real package is one hover away.
        onEntered: panel.setHint(modelData)
        onExited: panel.clearHint(modelData)
        onClicked: {
          picker.appPkg = modelData
          if (appLabelField.text.trim() === "")
            appLabelField.text = panel.appName(modelData).substring(0, 4).toUpperCase()
        }
      }
    }
  }

  Row {
    visible: picker.appFormOpen
    spacing: Style.space(6)

    FormButton {
      panel: picker.panel
      width: (picker.panel.padWidth - Style.space(6)) / 2
      label: "SAVE"
      active: picker.appPkg !== ""
      onPress: function() { picker.commitAppForm() }
    }
    FormButton {
      panel: picker.panel
      width: (picker.panel.padWidth - Style.space(6)) / 2
      label: "CANCEL"
      onPress: function() { picker.closeAppForm() }
    }
  }
}
