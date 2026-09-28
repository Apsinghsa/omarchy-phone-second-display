import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

BarWidget {
  id: root
  moduleName: "apsingh.phone-vnc"

  // ---- Status state ----
  // vncRunning == whether a wayvnc capture of the "phone" output is alive.
  property bool vncRunning: false

  readonly property int pollIntervalMs: 3000

  readonly property string stateLabel: root.vncRunning ? "Phone display: ON (workspace 10)" : "Phone display: OFF"

  // md-monitor-cellphone (U+F0989) when running, md-monitor-off (U+F0D90) when stopped.
  readonly property string displayText: root.vncRunning ? "\uDB82\uDD89" : "\uDB83\uDD90"

  // ---- Status polling ----
  component StatusProc: Process {
    readonly property string module: "apsingh.phone-vnc"
    stdout: StdioCollector {
      onStreamFinished: root.onStatusText(text.trim())
    }
  }
  property Component statusFactory: Component { StatusProc {} }

  function probe() {
    var p = statusFactory.createObject(root)
    p.command = ["sh", "-c",
      "if pgrep -f '[w]ayvnc -o phone ' >/dev/null 2>&1; then echo 1; else echo 0; fi"]
    p.running = true
  }

  function onStatusText(text) {
    vncRunning = text.trim() === "1"
    if (panelLoader.item && panelLoader.item.onStatus)
      panelLoader.item.onStatus(vncRunning)
  }

  Timer {
    interval: root.pollIntervalMs
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.probe()
  }

  // ---- Service control (called from the panel buttons) ----
  component ActionProc: Process {
    readonly property string module: "apsingh.phone-vnc"
    onExited: function(code) {
      if (code !== 0) console.warn("[phone-vnc] action exited", code)
    }
  }
  property Component actionFactory: Component { ActionProc {} }

  function runAction(cmd) {
    var p = actionFactory.createObject(root)
    p.command = ["sh", "-c", cmd]
    p.running = true
  }

  function startService() {
    runAction("nohup /home/apsingh/.local/bin/phone-vnc-start >> /tmp/phone-vnc-plugin.log 2>&1 &")
    Qt.callLater(root.probe)
  }

  function stopService() {
    runAction("/home/apsingh/.local/bin/phone-vnc-stop")
    Qt.callLater(root.probe)
  }

  // ---- Panel lifecycle (forward from entry point) ----
  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    visible: false
    source: Qt.resolvedUrl("Panel.qml")
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.displayText
    tooltipText: root.stateLabel + "\nClick: open phone display control"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
    }
  }
}