import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 操作者登录(启动第一屏)。身份分层:这里登录的是"操作者"(工号+角色,本地离线库),
// 与软件连云的腾达后台账号无关(那是软件级凭证,超级用户在设置页配置)。
//
// mock:账户在 MockData.users 明文比对,仅供演示。真实实现(docs/plan P5):
// SQLite 账户库 + PBKDF2-HMAC-SHA256 加盐哈希 + 失败节流(5次/30s) +
// 记住工号(QSettings) + 首启强制创建超级用户。
Item {
    id: root

    // 开发用:--autoselect 以超级用户直接登录(ProductGate 的同名参数接力跳过产品门)
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--autoselect") >= 0)
            Session.user = MockData.users[0]
    }

    property string error: ""

    function tryLogin() {
        const id = userField.text.trim();
        const hit = MockData.users.find(u => u.id === id && u.pwd === pwdField.text);
        if (hit) {
            root.error = "";
            pwdField.text = "";
            // 登录成功才记工号：输错的不该被记住
            LocalSettings.setRememberedUserId(id, rememberBox.checked);
            Session.user = hit;    // 真实实现:此处还要记审计(登录事件)
        } else {
            root.error = "工号或密码不正确";
        }
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.centerIn: parent
        width: 400
        spacing: Theme.s4

        Image {
            source: "logo.png"
            sourceSize.height: 34
            fillMode: Image.PreserveAspectFit
            smooth: true
            Layout.alignment: Qt.AlignHCenter
        }

        Text {
            text: "产测工具"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.display
            font.weight: TypeScale.weightBold
            Layout.alignment: Qt.AlignHCenter
        }

        Item { Layout.preferredHeight: Theme.s3 }

        Card {
            fitContent: true
            Layout.fillWidth: true
            pad: Theme.s5

            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s3

                TextField {
                    id: userField
                    Layout.fillWidth: true
                    placeholderText: "工号"
                    // 上次登录的工号，来自本机 QSettings（当前用户注册表）。
                    // ⚠️ 早先这里写死 MockData.users[0].id —— 于是**谁打开都是那个
                    //    工号**，把软件包发给别人也一样（2026-08-21 反馈）。那不是
                    //    "记住工号"泄露，是它从来就没实现过、只是个写死的假值。
                    text: LocalSettings.rememberedUserId()
                    font.family: "Consolas"
                    font.pointSize: TypeScale.body
                }

                TextField {
                    id: pwdField
                    Layout.fillWidth: true
                    placeholderText: "密码"
                    echoMode: TextInput.Password
                    font.pointSize: TypeScale.body
                    onAccepted: root.tryLogin()
                }

                Text {
                    visible: root.error.length > 0
                    text: root.error
                    color: Theme.fail
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                }

                RowLayout {
                    Layout.fillWidth: true
                    CheckBox {
                        id: rememberBox
                        text: "记住工号"
                        // 读本机设置，不再恒 true。取消勾选会把已存的工号抹掉
                        // （见 LocalSettings::setRememberedUserId）——"取消"就该是
                        // "别在这台机器上留我的工号"，只停止写入等于没取消。
                        checked: LocalSettings.rememberEnabled()
                        onToggled: LocalSettings.setRememberedUserId(
                                       userField.text.trim(), checked)
                    }
                    Item { Layout.fillWidth: true }
                }

                AppButton {
                    text: "登录"
                    glyph: Icons.person
                    kind: "primary"
                    Layout.fillWidth: true
                    onClicked: root.tryLogin()
                }
            }
        }

        Text {
            text: "工具 " + (typeof appVersion !== "undefined" ? "v" + appVersion : "dev")
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.s4
        }
    }
}
