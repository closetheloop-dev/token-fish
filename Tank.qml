import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Ui

// A transparent, click-through overlay covering a single monitor, rendered on
// the Wlr "Bottom" layer: above the wallpaper, below normal windows.
PanelWindow {
  id: tank
  required property var modelData

  screen: modelData

  // ScreenMoveRemap forces an unmap/remap when the monitor moves in the layout,
  // so the surface follows its screen instead of stranding at the old origin.
  visible: !remapGuard.remapping

  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"

  // Keep the committed buffer alive; parking a background-layer surface with
  // updatesEnabled=false has been observed to black out the desktop.
  updatesEnabled: true

  WlrLayershell.namespace: "io.github.closetheloop-dev.token-fish"
  WlrLayershell.layer: WlrLayer.Bottom
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
  exclusionMode: ExclusionMode.Ignore

  // Empty input region -> fully click-through: pointer events reach the windows
  // and desktop beneath the aquarium.
  mask: Region {}

  ScreenMoveRemap {
    id: remapGuard
    window: tank
  }

  // Persisted, live-editable settings written by the bar-widget controls panel.
  Settings { id: settings }

  // The living aquarium: fish + food pellets + Life sim, driven by one frame
  // clock. FoodSource feeds it from real token usage. Tunables bind to Settings
  // so panel changes apply the instant settings.json is rewritten.
  AquariumScene {
    id: scene
    anchors.fill: parent
    startCount: 5
    frozen: settings.frozen
    speedScale: settings.speedScale
    sizeScale: settings.sizeScale
    popMax: settings.popMax
    densityMax: settings.densityMax
    food: settings.food
    fps: settings.fps
    foodLively: settings.foodLively
    feedNonce: settings.feedNonce
    feedReady: settings.loaded
  }

  FoodSource {
    scene: scene
  }

  // Counter overlay: live fish + cumulative sushi (deaths), bottom-right corner.
  // Same process as the scene → bind directly (no IPC). Visual only (window is
  // click-through), toggled by the panel's "Show counter" setting.
  Text {
    anchors { right: parent.right; bottom: parent.bottom; margins: 18 * scene.resScale }
    visible: settings.showCounter
    text: "🐟 " + scene.living + "    🍣 " + scene.sushiCount
    color: "#99ffffff"
    font.pixelSize: 18 * scene.resScale
    font.family: "monospace"
  }
}
