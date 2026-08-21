import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 操作者登录（启动第一屏）。**用腾达安防云账号登录**（2026-08-21 定案）：
//
//   身份 —— 腾达云管。工人用自己的手机号+密码，人事已在维护这份数据，离职即失效，
//           全产线所有 PC 同时生效，不需要逐台删账号。
//   权限 —— 本地 accounts.json 管，只记"这个手机号是什么角色"，一个密码都不存。
//
// 登录成功后，这位登录者的 access_token 还会**供取 xp2p_info 用** ——
// 所以 cloud_config.json 里不再需要账号密码（实测 p2pToken 不校验设备归属）。
//
// 腾达账号只能在手机 App 上注册（用户确认），所以未注册时只能提示去 App 注册，
// 软件内做不了。
Item {
    id: root

    property string error: ""

    // 开发用:--autoselect 以超级用户直接登录(ProductGate 的同名参数接力跳过产品门)。
    // ⚠️ 一个对象只能有一个 Component.onCompleted —— 写两遍后者会**静默覆盖**前者
    //    且不报错。以后要加初始化就并进这里，别再写第二个。
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--autoselect") >= 0) {
            const list = AccountStore.accounts;
            for (let i = 0; i < list.length; ++i) {
                if (list[i].role === "super") {
                    Session.user = list[i];
                    break;
                }
            }
        }
    }

    function tryLogin() {
        root.error = "";
        // 异步：云端往返 1~3 秒。结果走 OperatorLogin 的 succeeded/failed 信号。
        OperatorLogin.login(userField.text.trim(), pwdField.text);
    }

    Connections {
        target: OperatorLogin
        function onSucceeded(user) {
            pwdField.text = "";
            // 登录成功才记手机号：输错的不该被记住
            LocalSettings.setRememberedUserId(userField.text.trim(),
                                              rememberBox.checked);
            Session.user = user;
        }
        function onFailed(reason) {
            root.error = reason;
            pwdField.text = "";   // 失败清密码，省得工人在错的基础上改
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
                    placeholderText: "手机号（腾达安防云账号）"
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
                    placeholderText: "腾达安防云密码"
                    // 按住眼睛看明文，松开回圆点。产线戴手套输密码容易错，
                    // 但"点一下切换"会让明文一直留在屏上（旁边就是别人的工位）——
                    // 按住才显示，手一松就没，不会忘记切回去。
                    echoMode: eyeHold.pressed ? TextInput.Normal : TextInput.Password
                    font.pointSize: TypeScale.body
                    // 给右侧眼睛让出位置，否则密码尾部会被图标压住
                    rightPadding: eyeIcon.width + Theme.s4
                    onAccepted: root.tryLogin()

                    Icon {
                        id: eyeIcon
                        anchors {
                            right: parent.right
                            rightMargin: Theme.s3
                            verticalCenter: parent.verticalCenter
                        }
                        // 两个码位都验过在 Segoe Fluent Icons(Win11) 与
                        // Segoe MDL2 Assets(Win10) 里都有真实字形（渲染比像素，
                        // 不是只看 MeasureString）—— 见 Icons.qml 的说明
                        text: eyeHold.pressed ? Icons.eyeOff : Icons.eye
                        size: 16
                        color: eyeHold.pressed ? Theme.brand
                               : eyeHold.containsMouse ? Theme.textPrimary
                               : Theme.textDim

                        MouseArea {
                            id: eyeHold
                            anchors.fill: parent
                            anchors.margins: -Theme.s2   // 命中区放大，戴手套也点得到
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                        }
                    }
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
                        text: "记住手机号"
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
                    text: OperatorLogin.busy ? "正在验证…" : "登录"
                    glyph: Icons.person
                    kind: "primary"
                    // 云端往返 1~3 秒，期间置灰防连点（OperatorLogin 内部也兜了一层）
                    enabled: !OperatorLogin.busy
                    Layout.fillWidth: true
                    onClicked: root.tryLogin()
                }

                // 腾达账号只能在手机 App 上注册（用户确认），软件内做不了 ——
                // 所以只给一句明确的指路，不做假的"注册"按钮。
                Text {
                    Layout.fillWidth: true
                    text: "没有账号？请先用「腾达安防」手机 App 注册，"
                          + "再让管理员把手机号加进本软件。"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WordWrap
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
