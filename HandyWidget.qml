import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "blizl.handy"

  readonly property var source: Pipewire.defaultAudioSource
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property bool microphonePresent: !!(source && source.audio)
  readonly property bool microphoneMuted: microphonePresent && source.audio.muted
  readonly property bool handyRecording: hasHandyCaptureStream(nodes)
  readonly property bool microphoneInUse: hasActiveCaptureStream(nodes)
  readonly property string state: {
    if (!microphonePresent) return "missing"
    if (microphoneMuted) return "muted"
    if (handyRecording) return "recording"
    if (microphoneInUse) return "in-use"
    return "available"
  }
  readonly property string icon: state === "missing" || state === "muted" ? "󰍭" : "󰍬"
  readonly property string pluginRoot: Quickshell.env("HOME") + "/.config/omarchy/plugins/blizl.handy"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function isActiveCaptureStream(node) {
    return !!(node && node.isStream && node.isSink === false && node.audio && !node.audio.muted)
  }

  function streamLabel(node) {
    if (!node) return ""
    return [node.name, node.description, node.appName, node.applicationName]
      .filter(function(value) { return value !== undefined && value !== null })
      .join(" ").toLowerCase()
  }

  function isHandyStream(node) {
    if (!isActiveCaptureStream(node)) return false
    var label = streamLabel(node)
    return label.indexOf("handy") !== -1 || label.indexOf("com.pais.handy") !== -1
  }

  function hasHandyCaptureStream(list) {
    for (var i = 0; i < list.length; i++) if (isHandyStream(list[i])) return true
    return false
  }

  function hasActiveCaptureStream(list) {
    for (var i = 0; i < list.length; i++) if (isActiveCaptureStream(list[i])) return true
    return false
  }

  function tooltipFor(value) {
    if (value === "missing") return "Microphone not detected"
    if (value === "muted") return "Microphone muted"
    if (value === "recording") return "Handy is recording"
    if (value === "in-use") return "Microphone in use"
    return "Microphone available"
  }

  function triggerCommand(action) {
    return Util.shellQuote(pluginRoot + "/bin/handy-trigger") + " " + action
  }

  PwObjectTracker {
    objects: root.source ? [root.source].concat(root.nodes) : root.nodes
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.icon
    active: root.state === "recording" || root.state === "in-use"
    tooltipText: root.tooltipFor(root.state)

    onPressed: function(button) {
      if (!root.bar) return
      if (button === Qt.MiddleButton)
        root.bar.run("omarchy-shell shell toggle omarchy.audio")
      else if (root.state === "missing")
        root.bar.run(root.triggerCommand("notify-missing-mic"))
      else
        root.bar.run("uwsm-app -- handy")
    }
  }
}
