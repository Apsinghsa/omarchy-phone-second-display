import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "apsingh.phone-vnc"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null

  property bool vncRunning: false

  function onStatus(running) {
    vncRunning = running
  }

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function startService() {
    if (hostWidget && typeof hostWidget.startService === "function") hostWidget.startService()
  }

  function stopService() {
    if (hostWidget && typeof hostWidget.stopService === "function") hostWidget.stopService()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  readonly property string statusText: root.vncRunning
    ? "Phone second display is ON (workspace 10)"
    : "Phone second display is OFF (VNC stream not running)"

  readonly property color dimForeground: Util.alpha(root.barForeground, 0.4)

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        Text {
          width: parent.width
          text: root.statusText
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
          elide: Text.ElideRight
        }

        Button {
          id: startBtn
          width: parent.width
          text: "Start phone display"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.body
          foreground: startBtnEnabled ? root.barForeground : root.dimForeground
          accent: Color.accent
          onClicked: if (startBtnEnabled) root.startService()

          // Only tappable when the VNC stream is down.
          readonly property bool startBtnEnabled: !root.vncRunning
        }

        Button {
          id: stopBtn
          width: parent.width
          text: "Stop phone display"
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          fontSize: Style.font.body
          foreground: stopBtnEnabled ? root.barForeground : root.dimForeground
          onClicked: if (stopBtnEnabled) root.stopService()

          // Only tappable when the VNC stream is running.
          readonly property bool stopBtnEnabled: root.vncRunning
        }

        Text {
          width: parent.width
          text: "Start brings up the phone as a second screen on workspace 10\\n(The phone must be connected over USB with adb debugging on.)"
          color: Util.alpha(root.barForeground, 0.7)
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}