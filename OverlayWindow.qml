import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Model.js" as Model

PanelWindow {
  id: win
  property var host: null

  visible: host && host.opened
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  WlrLayershell.namespace: "omatv"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
  exclusionMode: ExclusionMode.Ignore

  Rectangle {
    id: stage
    anchors.fill: parent
    color: host ? Qt.rgba(host.background.r, host.background.g, host.background.b, 0.97) : "#101014"
  }

  Rectangle {
    id: searchBar
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: 26
    width: Math.min(parent.width - 72, 720)
    height: 48
    radius: 24
    color: Qt.rgba(0, 0, 0, 0.45)
    border.width: 1
    border.color: (host && searchField.activeFocus) ? host.accent : Qt.rgba(1, 1, 1, 0.16)
    z: 4

    Text {
      anchors.fill: parent
      leftPadding: 20
      rightPadding: 20
      text: "Search channels…"
      visible: searchField.text.length === 0
      color: Qt.rgba(1, 1, 1, 0.38)
      font.pixelSize: 15
      font.family: host ? host.fontFamily : Style.font.family
      verticalAlignment: Text.AlignVCenter
      elide: Text.ElideRight
    }

    TextInput {
      id: searchField
      anchors.fill: parent
      leftPadding: 20
      rightPadding: 20
      verticalAlignment: TextInput.AlignVCenter
      color: "white"
      font.pixelSize: 15
      font.family: host ? host.fontFamily : Style.font.family
      clip: true
      selectByMouse: true
      focus: true

      Keys.priority: Keys.BeforeItem
      Keys.onPressed: function(event) {
        if (!host) return
        if (event.key === Qt.Key_Escape) {
          if (text.length > 0) { text = ""; host.queryText = "" }
          else host.close()
          event.accepted = true
        } else if (event.key === Qt.Key_Down) { host.moveSelection(0, 1); event.accepted = true }
        else if (event.key === Qt.Key_Up) { host.moveSelection(0, -1); event.accepted = true }
        else if (event.key === Qt.Key_Right && cursorPosition === text.length && selectedText.length === 0) { host.moveSelection(1, 0); event.accepted = true }
        else if (event.key === Qt.Key_Left && cursorPosition === 0 && selectedText.length === 0) { host.moveSelection(-1, 0); event.accepted = true }
        else if (event.key === Qt.Key_Tab) {
          host.tab = host.tab === "favorites" ? "all" : "favorites"
          event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) { host.playSelected(); event.accepted = true }
      }
      onTextChanged: { if (host) host.queryText = text }
    }
  }

  Row {
    id: tabRow
    anchors.top: searchBar.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: 14
    spacing: 10
    z: 4

    Rectangle {
      width: favLabel.implicitWidth + 28
      height: 30
      radius: 15
      color: host && host.tab === "favorites" ? host.accent : Qt.rgba(1, 1, 1, 0.08)

      Text {
        id: favLabel
        anchors.centerIn: parent
        text: "★ Favorites"
        color: host && host.tab === "favorites"
          ? (host ? host.background : "#101014")
          : Qt.rgba(1, 1, 1, 0.75)
        font.pixelSize: 13
        font.bold: host && host.tab === "favorites"
        font.family: host ? host.fontFamily : Style.font.family
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (host) host.tab = "favorites" }
      }
    }

    Rectangle {
      width: allLabel.implicitWidth + 28
      height: 30
      radius: 15
      color: host && host.tab === "all" ? host.accent : Qt.rgba(1, 1, 1, 0.08)

      Text {
        id: allLabel
        anchors.centerIn: parent
        text: "All channels"
        color: host && host.tab === "all"
          ? (host ? host.background : "#101014")
          : Qt.rgba(1, 1, 1, 0.75)
        font.pixelSize: 13
        font.bold: host && host.tab === "all"
        font.family: host ? host.fontFamily : Style.font.family
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: { if (host) host.tab = "all" }
      }
    }
  }

  Text {
    anchors.right: searchBar.right
    anchors.verticalCenter: tabRow.verticalCenter
    text: host ? host.statusText() : ""
    visible: host && host.opened
    color: host && host.service && host.service.lastError !== "" ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.4)
    font.pixelSize: 12
    font.family: host ? host.fontFamily : Style.font.family
  }

  Item {
    id: filterBar
    anchors.top: tabRow.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.topMargin: 10
    width: Math.min(parent.width - 72, 900)
    height: visible ? 30 : 0
    visible: host && host.tab === "all" && host.service && host.service.playlists.length > 0
    z: 4

    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: 8

      Rectangle {
        width: allChipLabel.implicitWidth + 24
        height: 26
        radius: 13
        color: !host || host.playlistFilter === "" ? (host ? host.accent : "#8ab4f8") : Qt.rgba(1, 1, 1, 0.08)

        Text {
          id: allChipLabel
          anchors.centerIn: parent
          text: "all playlists"
          color: !host || host.playlistFilter === ""
            ? (host ? host.background : "#101014")
            : Qt.rgba(1, 1, 1, 0.75)
          font.pixelSize: 11
          font.bold: !host || host.playlistFilter === ""
          font.family: host ? host.fontFamily : Style.font.family
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { if (host) host.playlistFilter = "" }
        }
      }

      Repeater {
        model: host && host.service ? host.service.playlists : []

        delegate: Rectangle {
          required property string modelData
          required property int index

          readonly property bool active: host && host.playlistFilter === modelData
          readonly property bool hovered: chipMouse.containsMouse

          width: chipLabel.implicitWidth + chipRemove.width + 22
          height: 26
          radius: 13
          color: active ? (host ? host.accent : "#8ab4f8")
                : hovered ? Qt.rgba(1, 1, 1, 0.14) : Qt.rgba(1, 1, 1, 0.08)

          Text {
            id: chipLabel
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            text: Model.shortPlaylistLabel(modelData)
            color: active
              ? (host ? host.background : "#101014")
              : Qt.rgba(1, 1, 1, 0.75)
            font.pixelSize: 11
            font.bold: active
            font.family: host ? host.fontFamily : Style.font.family
          }

          Text {
            id: chipRemove
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            visible: hovered && (host && host.service && host.service.playlists.length > 1)
            text: "󰅖"
            color: chipRemoveMouse.containsMouse ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.55)
            font.pixelSize: 11
            font.family: host ? host.fontFamily : Style.font.family

            MouseArea {
              id: chipRemoveMouse
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (!host || !host.service) return
                if (host.playlistFilter === modelData) host.playlistFilter = ""
                host.service.removePlaylist(modelData)
              }
            }
          }

          MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: { if (host) host.playlistFilter = modelData }
          }
        }
      }
    }
  }
  GridView {
    id: grid
    anchors.top: filterBar.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    anchors.leftMargin: 32
    anchors.rightMargin: 32
    anchors.topMargin: 14
    anchors.bottomMargin: 40
    clip: true
    cellWidth: Math.floor(width / (host ? host.columns : 6))
    cellHeight: Math.round(cellWidth * 0.62)
    model: host ? host.results : []
    currentIndex: host ? host.selectedIndex : 0
    boundsBehavior: Flickable.StopAtBounds
    interactive: !(host && host.dragLock)
    pressDelay: 0

    onCurrentIndexChanged: {
      if (host) {
        host.selectedIndex = currentIndex
        if (!host.dragging) positionViewAtIndex(currentIndex, ListView.Contain)
      }
    }

    delegate: Item {
      required property int index
      required property var modelData

      width: grid.cellWidth
      height: grid.cellHeight

      Rectangle {
        id: card
        anchors.fill: parent
        anchors.margins: 8
        radius: 14
        opacity: host && host.dragging && index === host.dragSourceIndex ? 0.25 : 1
        color: index === host.selectedIndex
          ? Qt.rgba(1, 1, 1, 0.14)
          : cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.1) : Qt.rgba(1, 1, 1, 0.05)
        border.width: index === host.selectedIndex ? 2 : 1
        border.color: index === host.selectedIndex ? host.accent : Qt.rgba(1, 1, 1, 0.08)

        Rectangle {
          visible: host && host.dragging && index !== host.dragSourceIndex
                   && host.insertIndex !== host.dragSourceIndex
                   && host.insertIndex !== host.dragSourceIndex + 1
                   && (index === host.insertIndex || (index === host.results.length - 1 && host.insertIndex === host.results.length))
          width: 4
          radius: 2
          color: host.accent
          height: parent.height - 12
          anchors.verticalCenter: parent.verticalCenter
          anchors.left: parent.left
          anchors.leftMargin: index === host.insertIndex ? -10 : parent.width + 6
        }

        Column {
          anchors.fill: parent
          anchors.margins: 12
          spacing: 8

          Item {
            width: parent.width
            height: parent.height - nameLabel.height - 8 - parent.spacing

            Image {
              id: logoImage
              anchors.centerIn: parent
              width: Math.min(parent.width, parent.height * 1.6)
              height: Math.min(parent.height, width * 0.625)
              visible: modelData.logo !== "" && logoImage.status === Image.Ready
              asynchronous: true
              source: modelData.logo
              sourceSize.width: width * 2
              sourceSize.height: height * 2
              fillMode: Image.PreserveAspectFit
            }

            Text {
              anchors.centerIn: parent
              visible: !(modelData.logo !== "" && logoImage.status === Image.Ready)
              text: "󰔂"
              color: Qt.rgba(1, 1, 1, 0.25)
              font.pixelSize: Math.min(parent.height * 0.5, 42)
              font.family: host ? host.fontFamily : Style.font.family
            }
          }

          Text {
            id: nameLabel
            width: parent.width
            height: 18
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            text: modelData.name
            color: Qt.rgba(1, 1, 1, 0.9)
            font.pixelSize: 13
            font.family: host ? host.fontFamily : Style.font.family
          }
        }

        MouseArea {
          id: cardMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          property bool dragArmed: false
          property bool isDragging: false
          property real pressX: 0
          property real pressY: 0

          onPressed: function(mouse) {
            pressX = mouse.x
            pressY = mouse.y
            dragArmed = host && host.tab === "favorites"
            isDragging = false
            if (host) host.dragLock = dragArmed
          }

          onPositionChanged: function(mouse) {
            if (host && host.selectedIndex !== index && !isDragging) host.selectIndex(index)

            if (!dragArmed || !pressed) return

            if (!isDragging) {
              if (Math.abs(mouse.x - pressX) < 10 && Math.abs(mouse.y - pressY) < 10) return
              isDragging = true
              host.beginDrag(index)
              if (!host.dragging) { dragArmed = false; return }
            }
            var sp = mapToItem(stage, mouse.x, mouse.y)
            host.updateDragGhost(sp.x, sp.y)
            var gp = mapToItem(grid, mouse.x, mouse.y)
            host.updateDropTarget(dropBoundaryForPoint(gp.x, gp.y))
          }

          onReleased: function(mouse) {
            var wasDragging = isDragging
            var boundary = -1
            if (wasDragging && host && host.dragging) {
              var gp = mapToItem(grid, mouse.x, mouse.y)
              boundary = dropBoundaryForPoint(gp.x, gp.y)
            }
            isDragging = false
            if (host) host.dragLock = false

            if (wasDragging && host) {
              if (boundary >= 0) host.updateDropTarget(boundary)
              host.endDrag()
              return
            }
            if (host) { host.selectIndex(index); host.playSelected() }
          }

          onCanceled: {
            isDragging = false
            if (host) {
              host.dragLock = false
              if (host.dragging) host.cancelDrag()
            }
          }

          function dropBoundaryForPoint(viewX, viewY) {
            var count = host ? host.results.length : 0
            var cols = Math.max(1, Math.floor(grid.width / grid.cellWidth))
            if (count === 0) return -1

            var col = Math.floor(viewX / grid.cellWidth)
            if (col < 0) col = 0
            if (col >= cols) col = cols - 1
            var row = Math.floor((viewY + grid.contentY) / grid.cellHeight)
            if (row < 0) row = 0

            var cellIndex = row * cols + col
            var leftHalf = (viewX - col * grid.cellWidth) < grid.cellWidth / 2
            var boundary = leftHalf ? cellIndex : cellIndex + 1

            if (boundary > count) boundary = count
            return boundary
          }

          function dropIndexForPoint(viewX, viewY) {
            var cols = Math.max(1, Math.floor(grid.width / grid.cellWidth))
            var col = Math.floor(viewX / grid.cellWidth)
            if (col < 0) col = 0
            if (col >= cols) col = cols - 1
            var row = Math.floor((viewY + grid.contentY + grid.cellHeight / 2) / grid.cellHeight)
            if (row < 0) row = 0
            var dropIndex = row * cols + col
            if (dropIndex >= (host ? host.results.length : 0)) dropIndex = host.results.length - 1
            return dropIndex
          }
        }

        Text {
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: 10
          text: host && host.favoriteUrls[modelData.url] ? "󰓎" : "󰋆"
          color: host && host.favoriteUrls[modelData.url] ? host.accent : Qt.rgba(1, 1, 1, 0.3)
          font.pixelSize: 16
          font.family: host ? host.fontFamily : Style.font.family

          MouseArea {
            anchors.fill: parent
            anchors.margins: -8
            cursorShape: Qt.PointingHandCursor
            onClicked: function(mouse) {
              if (!host || !host.service) return
              mouse.accepted = true
              host.service.toggleFavorite(modelData)
            }
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: grid
    visible: host && host.results.length === 0 && host.queryText.length > 0
    text: "no matches"
    color: Qt.rgba(1, 1, 1, 0.45)
    font.pixelSize: Style.font.title
    font.family: host ? host.fontFamily : Style.font.family
    z: 2
  }

  Text {
    anchors.centerIn: grid
    visible: host && host.results.length === 0 && host.queryText.length === 0
             && ((host.service && (host.service.loading || host.service.channels.length === 0)) || !host.service)
    text: {
      if (!host || !host.service) return "service unavailable"
      if (host.service.loading) return "loading playlists…"
      return "no channels — add an m3u playlist below"
    }
    color: Qt.rgba(1, 1, 1, 0.45)
    font.pixelSize: Style.font.title
    font.family: host ? host.fontFamily : Style.font.family
    z: 2
  }

  Item {
    id: playlistBar
    anchors.bottom: parent.bottom
    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottomMargin: 18
    width: Math.min(parent.width - 72, 560)
    height: 36
    z: 4

    Rectangle {
      anchors.fill: parent
      radius: 18
      color: Qt.rgba(0, 0, 0, 0.35)
      border.width: 1
      border.color: playlistField.activeFocus ? (host ? host.accent : "#8ab4f8") : Qt.rgba(1, 1, 1, 0.12)

      TextInput {
        id: playlistField
        anchors.fill: parent
        leftPadding: 16
        rightPadding: 44
        verticalAlignment: TextInput.AlignVCenter
        color: "white"
        font.pixelSize: 13
        font.family: host ? host.fontFamily : Style.font.family
        clip: true
        selectByMouse: true

        Text {
          anchors.fill: parent
          leftPadding: 16
          rightPadding: 44
          text: "add m3u playlist url…"
          visible: playlistField.text.length === 0
          color: Qt.rgba(1, 1, 1, 0.3)
          font.pixelSize: 13
          font.family: host ? host.fontFamily : Style.font.family
          verticalAlignment: Text.AlignVCenter
        }

        Keys.onPressed: function(event) {
          if (!host) return
          if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (host.service && text.trim().length > 0) host.service.addPlaylist(text.trim())
            text = ""
            host.tab = "all"
            event.accepted = true
          } else if (event.key === Qt.Key_Escape) {
            text = ""
            win.focusSearch()
            event.accepted = true
          }
        }
      }

      Text {
        anchors.right: parent.right
        anchors.rightMargin: 14
        anchors.verticalCenter: parent.verticalCenter
        text: "󰐕"
        color: playlistAddMouse.containsMouse ? (host ? host.accent : "#8ab4f8") : Qt.rgba(1, 1, 1, 0.5)
        font.pixelSize: 16
        font.family: host ? host.fontFamily : Style.font.family

        MouseArea {
          id: playlistAddMouse
          anchors.fill: parent
          anchors.margins: -8
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            if (!host || !host.service) return
            if (playlistField.text.trim().length > 0) host.service.addPlaylist(playlistField.text.trim())
            playlistField.text = ""
            win.focusSearch()
          }
        }
      }
    }
  }

  Text {
    anchors.bottom: parent.bottom
    anchors.bottomMargin: 62
    anchors.horizontalCenter: parent.horizontalCenter
    text: "type to search · ↑↓ navigate · enter play · tab favorites/all · esc close"
    color: Qt.rgba(1, 1, 1, 0.28)
    font.pixelSize: 11
    font.family: host ? host.fontFamily : Style.font.family
    z: 4
  }

  function focusSearch() { searchField.forceActiveFocus() }
  function clearSearch() { searchField.text = ""; if (host) host.queryText = "" }

  Rectangle {
    id: dragGhost
    visible: host && host.dragging
    width: grid.cellWidth - 16
    height: grid.cellHeight - 16
    radius: 14
    x: host ? host.dragX - width / 2 : 0
    y: host ? host.dragY - height / 2 : 0
    color: Qt.rgba(1, 1, 1, 0.16)
    border.width: 2
    border.color: host ? host.accent : "#8ab4f8"
    opacity: 0.9
    z: 50

    Column {
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      Item {
        width: parent.width
        height: parent.height - ghostLabel.height - parent.spacing

        Image {
          anchors.centerIn: parent
          width: Math.min(parent.width, parent.height * 1.6)
          height: Math.min(parent.height, width * 0.625)
          visible: host && host.dragGhostLogo !== ""
          source: host ? host.dragGhostLogo : ""
          fillMode: Image.PreserveAspectFit
        }
      }

      Text {
        id: ghostLabel
        width: parent.width
        height: 18
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        text: host ? host.dragGhostName : ""
        color: Qt.rgba(1, 1, 1, 0.9)
        font.pixelSize: 13
        font.family: host ? host.fontFamily : Style.font.family
      }
    }
  }
}
