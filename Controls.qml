import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

// Bar widget for token-fish: a clownfish glyph in the bar that toggles a controls
// panel. Every control writes settings.json (via Settings.save()); the running
// aquarium service watches that file and applies changes live. This entry point
// owns only the UI — no simulation. Host injects `bar`.
Panel {
  id: root
  moduleName: "io.github.closetheloop-dev.token-fish"
  ipcTarget: "io.github.closetheloop-dev.token-fish"

  // The bar sizes each widget slot from the root's implicit size; without this
  // the slot is zero-wide and the icon never draws (matches menu/BarWidget.qml).
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  readonly property color foreground: Color.foreground
  readonly property color dim: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.6)
  readonly property string fontFamily: Style.font.family

  Settings { id: settings }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // The bar font has no usable fish glyph, so render the clownfish art itself.
    iconComponent: Component {
      Image {
        anchors.fill: parent
        source: Qt.resolvedUrl("assets/fish.svg")
        fillMode: Image.PreserveAspectFit
        sourceSize.width: 64
        sourceSize.height: 48
        smooth: true
      }
    }
    onPressed: function(buttonCode) { root.toggle(); }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(900))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        padding: Style.space(16)
        spacing: Style.space(14)

        // Header: title on the left, the primary Feed action on the right.
        Item {
          width: parent.width - Style.space(32)
          height: Math.max(titleText.implicitHeight, feedButton.implicitHeight)

          Text {
            id: titleText
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "Token Fish"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.title
            font.bold: true
          }

          // Manual feed: drops a handful of pellets now, on top of the automatic
          // token feeding described in the tooltip.
          Button {
            id: feedButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "Feed"
            bordered: true
            enabled: !settings.frozen
            opacity: settings.frozen ? 0.4 : 1.0
            tooltipText: "The fish are also fed when you use your coding agents, like Claude Code, Codex, and more."
            onClicked: { settings.feedNonce = settings.feedNonce + 1; settings.save(); }
          }
        }

        // ---------- Freeze ----------
        Toggle {
          width: parent.width - Style.space(32)
          label: "Freeze aquarium"
          description: "Fully pause the aquarium — no motion and no feeding — to save CPU."
          checked: settings.frozen
          onClicked: { settings.frozen = !settings.frozen; settings.save(); }
        }

        PanelSeparator { width: parent.width - Style.space(32) }

        // ---------- Swim speed (disabled while frozen) ----------
        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          Text {
            text: "Swim speed · " + settings.speedScale.toFixed(1) + "×"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 0.3; maximum: 2.5; step: 0.1
            value: settings.speedScale
            onMoved: function(v) { settings.speedScale = v; settings.save(); }
          }
        }

        // ---------- Frame rate (disabled while frozen) ----------
        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          Text {
            text: settings.fps <= 0
                  ? "Frame rate · uncapped (vsync)"
                  : "Frame rate · " + settings.fps + " fps  (lower = less CPU)"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 0; maximum: 60; step: 1; integer: true
            value: settings.fps
            onMoved: function(v) { settings.fps = Math.round(v); settings.save(); }
          }
        }

        PanelSeparator { width: parent.width - Style.space(32) }

        // ---------- Fish size ----------
        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          Text {
            text: "Fish size · " + settings.sizeScale.toFixed(2) + "×"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 0.5; maximum: 1.8; step: 0.05
            value: settings.sizeScale
            onMoved: function(v) { settings.sizeScale = v; settings.save(); }
          }
        }

        // ---------- Population (only affects the running sim) ----------
        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          Text {
            text: "Max fish · " + settings.popMax
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 4; maximum: 24; step: 1; integer: true
            value: settings.popMax
            onMoved: function(v) { settings.popMax = Math.round(v); settings.save(); }
          }
        }

        Column {
          width: parent.width - Style.space(32)
          spacing: Style.space(6)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          Text {
            text: "Crowding before deaths · " + settings.densityMax
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
          PanelSlider {
            width: parent.width
            bar: root.bar
            minimum: 1; maximum: 6; step: 1; integer: true
            value: settings.densityMax
            onMoved: function(v) { settings.densityMax = Math.round(v); settings.save(); }
          }
        }

        PanelSeparator { width: parent.width - Style.space(32) }

        // ---------- Food (= your AI tokens) ----------
        Toggle {
          width: parent.width - Style.space(32)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          label: "Falling food"
          description: "Your AI token usage feeds the fish. Turn off to hide it."
          checked: settings.food
          onClicked: { settings.food = !settings.food; settings.save(); }
        }

        Toggle {
          width: parent.width - Style.space(32)
          enabled: !settings.frozen
          opacity: settings.frozen ? 0.4 : 1.0
          label: "Lively when fed"
          description: "Fish speed up and animate harder while there's food."
          checked: settings.foodLively
          onClicked: { settings.foodLively = !settings.foodLively; settings.save(); }
        }

        Toggle {
          width: parent.width - Style.space(32)
          label: "Show counter"
          description: "🐟 live · 🍣 eaten, in the corner of the wallpaper."
          checked: settings.showCounter
          onClicked: { settings.showCounter = !settings.showCounter; settings.save(); }
        }

        PanelSeparator { width: parent.width - Style.space(32) }

        // ---------- Reset ----------
        Button {
          text: "Reset to defaults"
          bordered: true
          onClicked: settings.reset()
        }
      }
    }
  }
}
