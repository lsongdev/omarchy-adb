import QtQuick
import qs.Commons

// Points one of the three shortcut buttons at an app: a label for the button,
// the launchable packages read off the TV to choose from, and SAVE / CANCEL.
//
// Keys reach it two ways, directly while the label field holds focus and
// forwarded from the pad's key catcher, so `handleKey` is the one place Return
// and Escape are interpreted.
Column {
  id: chooser

  // The Panel this belongs to: the app list, the settings writer and the
  // typing mode.
  property var panel: null

  // 0 while closed, else which shortcut button is being pointed at an app.
  property int slot: 0
  readonly property bool open: slot !== 0
  property string pkg: ""
  readonly property var activeInput: labelField.input
  readonly property real buttonWidth: (panel.padWidth - panel.gap) / 2

  visible: open
  spacing: panel.tightGap

  function start(slot) {
    pkg = panel.setting(panel.appKey(slot, "Package"), "")
    labelField.text = panel.setting(panel.appKey(slot, "Label"), "")
    panel.loadApps()
    chooser.slot = slot
    labelField.focusMe()
  }

  function handleKey(ev) {
    if (ev.key === Qt.Key_Escape) { close(); return true }
    if (ev.key === Qt.Key_Return || ev.key === Qt.Key_Enter) { commit(); return true }
    return false
  }

  function close() {
    slot = 0
    pkg = ""
    panel.stopTyping()
  }
  function commit() {
    if (pkg === "") return
    panel.writeApp(slot, labelField.text, pkg)
    close()
  }

  Field {
    id: labelField
    panel: chooser.panel
    placeholder: "button label (e.g. NFLX)"
    onKey: function(ev) { return chooser.handleKey(ev) }
  }

  PadText {
    panel: chooser.panel
    width: panel.padWidth
    elide: Text.ElideMiddle
    text: chooser.pkg === ""
          ? (panel.appsLoading ? "reading apps from the TV…" : "pick an app below")
          : chooser.pkg
    opacity: 0.45
    font.pixelSize: 9
  }

  // Bounded and scrolling rather than a plain Column: a TV can carry dozens
  // of launchable packages, and the pad would run off the screen.
  ListView {
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
                              modelData === chooser.pkg ? panel.surfaceRaised : "transparent")
      Behavior on color { ColorAnimation { duration: 90 } }

      PadText {
        panel: chooser.panel
        anchors.left: parent.left
        anchors.leftMargin: panel.inset
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width - panel.inset * 2
        elide: Text.ElideRight
        text: panel.appName(modelData)
        opacity: modelData === chooser.pkg ? 1.0 : 0.72
        font.pixelSize: 10
      }

      HintArea {
        id: appMa
        panel: chooser.panel
        anchors.fill: parent
        // The derived name is a guess, so the real package is one hover away.
        hint: modelData
        onClicked: {
          chooser.pkg = modelData
          if (labelField.text.trim() === "")
            labelField.text = panel.defaultAppLabel(modelData)
        }
      }
    }
  }

  Row {
    spacing: panel.gap

    FormButton {
      panel: chooser.panel
      width: chooser.buttonWidth
      label: "SAVE"
      active: chooser.pkg !== ""
      onPress: function() { chooser.commit() }
    }
    FormButton {
      panel: chooser.panel
      width: chooser.buttonWidth
      label: "CANCEL"
      onPress: function() { chooser.close() }
    }
  }
}
