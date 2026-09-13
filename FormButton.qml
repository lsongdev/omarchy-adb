import QtQuick
import qs.Commons


Rectangle {
  // The Panel this belongs to, for theming off panel.bar.
  property var panel: null
  id: fb
  property string label: ""
  property bool active: true
  property var onPress: null

  height: Style.space(24)
  radius: Style.cornerRadius
  opacity: fb.active ? 1.0 : 0.4
  color: fbMa.containsMouse && fb.active ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.08)

  Text {
    anchors.centerIn: parent
    text: fb.label
    color: panel.bar ? panel.bar.foreground : "white"
    font.family: panel.bar ? panel.bar.fontFamily : "monospace"
    font.pixelSize: 9
  }

  MouseArea {
    id: fbMa
    anchors.fill: parent
    hoverEnabled: true
    onClicked: if (fb.active && fb.onPress) fb.onPress()
  }
}
