// Greeter SDDM calqué sur le splash Plymouth « hexa_retro » (common/plymouth.nix).
//
// Objectif : continuité visuelle boot -> login. Fond noir, animation hexagonale
// centrée (les mêmes images que Plymouth, assemblées en GIF au build), prompt
// texte blanc en bas de l'écran comme le prompt LUKS de systemd-ask-password.
import QtQuick

Rectangle {
    id: root

    color: "black"

    property int sessionIndex: sessionModel.lastIndex
    property string message: ""

    // Noms des sessions : sessionModel est un QAbstractItemModel, on matérialise
    // les libellés pour pouvoir afficher celui de sessionIndex.
    Repeater {
        id: sessionNames
        model: sessionModel
        Item { property string label: model.name }
    }

    function sessionLabel(i) {
        var item = sessionNames.itemAt(i);
        return item ? item.label : "";
    }

    function login() {
        root.message = "";
        sddm.login(userField.text, passwordField.text, root.sessionIndex);
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            root.message = "Identifiants incorrects";
            passwordField.text = "";
            passwordField.forceActiveFocus();
        }
        function onLoginSucceeded() {
            root.message = "";
        }
    }

    AnimatedImage {
        id: logo
        source: "hexa_retro.gif"
        playing: true
        smooth: true
        anchors.centerIn: parent
        anchors.verticalCenterOffset: -parent.height * 0.08
    }

    // Bloc de saisie, positionné bas d'écran comme le prompt Plymouth.
    Column {
        id: prompt
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.14
        spacing: 14

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Text {
                text: "Utilisateur"
                color: "#8a8a8a"
                font.family: "monospace"
                font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            TextInput {
                id: userField
                text: userModel.lastUser
                color: "white"
                font.family: "monospace"
                font.pixelSize: 18
                width: 220
                selectByMouse: true
                selectionColor: "#404040"
                onAccepted: passwordField.forceActiveFocus()
            }
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Text {
                text: "Mot de passe"
                color: "#8a8a8a"
                font.family: "monospace"
                font.pixelSize: 18
                anchors.verticalCenter: parent.verticalCenter
            }

            TextInput {
                id: passwordField
                echoMode: TextInput.Password
                passwordCharacter: "*"
                passwordMaskDelay: 0
                color: "white"
                font.family: "monospace"
                font.pixelSize: 18
                width: 220
                selectByMouse: true
                selectionColor: "#404040"
                onAccepted: root.login()
            }
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.message
            color: "#d05050"
            font.family: "monospace"
            font.pixelSize: 16
        }
    }

    // Sélecteur de session : clic pour passer à la suivante.
    Text {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        text: "Session : " + root.sessionLabel(root.sessionIndex)
        color: "#8a8a8a"
        font.family: "monospace"
        font.pixelSize: 15

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            // sessionNames.count plutôt que sessionModel.rowCount() : rowCount
            // n'est pas invocable depuis QML sur un QAbstractItemModel.
            onClicked: root.sessionIndex =
                (root.sessionIndex + 1) % sessionNames.count
        }
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 20

        Text {
            visible: sddm.canReboot
            text: "Redémarrer"
            color: "#8a8a8a"
            font.family: "monospace"
            font.pixelSize: 15
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.reboot()
            }
        }

        Text {
            visible: sddm.canPowerOff
            text: "Éteindre"
            color: "#8a8a8a"
            font.family: "monospace"
            font.pixelSize: 15
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: sddm.powerOff()
            }
        }
    }

    Component.onCompleted: {
        if (userField.text === "")
            userField.forceActiveFocus();
        else
            passwordField.forceActiveFocus();
    }
}
