import QtQuick
import qs.Commons

// A full-width, left-aligned line in the picker: reads as a menu entry
// rather than a key, which is what separates "+ Add TV" from the D-pad.
Rectangle {
  // The Panel this belongs to: everything it draws is themed from
  // panel.bar, and hovering reports through panel.setHint.
  property var panel: null
  id: ac
  property string label: ""
  property string tip: ""
  property var onPress: null

  width: panel.padWidth
  height: panel.rowHeight
  radius: Style.cornerRadius
  color: acMa.pressed ? Color.popups.border
       : acMa.containsMouse ? panel.surfaceHover : "transparent"
  Behavior on color { ColorAnimation { duration: 90 } }

  Text {
    anchors.left: parent.left
    anchors.leftMargin: panel.inset
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - panel.inset * 2
    elide: Text.ElideRight
    text: ac.label
    color: panel.bar ? panel.bar.foreground : "white"
    opacity: 0.72
    font.family: panel.bar ? panel.bar.fontFamily : "monospace"
    font.pixelSize: 10
  }

  MouseArea {
    id: acMa
    anchors.fill: parent
    hoverEnabled: true
    onEntered: panel.setHint(ac.tip)
    onExited: panel.clearHint(ac.tip)
    onClicked: if (ac.onPress) ac.onPress()
  }
}
