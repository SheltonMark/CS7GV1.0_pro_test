import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 关于。产线出问题时工人要能在 10 秒内找到联系人，所以联系人排在版本号之前。
Item {
    id: root

    Toast { id: upgradeToast }

    // 一键跳企业微信。wxwork:// 协议已注册(实测)，但"直接打开某人会话"
    // 没有稳定的公开 deep-link 格式，各版本行为不一致。
    // 所以：跳转是尽力而为，工号始终摆在旁边可复制 —— 兜底路径必须永远可用。
    function openWeCom(id) {
        Qt.openUrlExternally("wxwork://message?username=" + id);
    }

    // 复制到剪贴板。QML 没有剪贴板 API，标准做法是借隐藏 TextEdit 的 copy()。
    // ⚠️ 隐藏 TextEdit 的 id 不能叫 "clip"：clip 是 Item 自带属性，Repeater
    //    委托里未限定的 "clip" 会先命中按钮自身的 clip(bool) 而非外层 id，
    //    selectAll() 抛 TypeError 且 WIN32 无控制台看不到报错，
    //    表现就是"点了没反应"。委托里只调这个函数，不直接摸 TextEdit。
    function copyText(t) {
        copyHelper.text = t;
        copyHelper.selectAll();
        copyHelper.copy();
    }

    ScrollView {
        anchors.fill: parent
        contentWidth: availableWidth
        clip: true

        ColumnLayout {
            width: root.width
            spacing: Theme.s4

            Item { Layout.preferredHeight: Theme.s2 }

            // ---- 品牌头 ----
            Card {
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5
                pad: Theme.s6

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s4

                    Image {
                        source: "logo.png"
                        sourceSize.height: 38
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                    }

                    Text {
                        text: "产测工具"
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.display
                        font.weight: TypeScale.weightBold
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "低功耗电池 IPC 产线产测软件。覆盖调焦、准成品、成品三个工位，"
                            + "以及维修工位的信息存档与分区清除。"
                        color: Theme.textSecondary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- 当前产品(只读,规则3;profile 由管理员维护,此处不给编辑入口) ----
            Card {
                title: "当前产品"
                titleIcon: Icons.navProduct
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    GridLayout {
                        Layout.fillWidth: true
                        columns: 2
                        columnSpacing: Theme.s7
                        rowSpacing: Theme.s3

                        FieldRow {
                            Layout.fillWidth: true
                            label: "产品"
                            value: Session.profile ? Session.profile.name + "  " + Session.profile.desc : ""
                            mono: false
                        }
                        FieldRow {
                            Layout.fillWidth: true
                            label: "ProductId"
                            value: Session.profile ? Session.profile.productId : ""
                        }
                    }

                    // 固定测试项(profile 决定,只读展示)
                    Flow {
                        Layout.fillWidth: true
                        spacing: Theme.s2

                        Repeater {
                            model: Session.profile ? Session.profile.items : []
                            Rectangle {
                                required property var modelData
                                width: chipRow.implicitWidth + Theme.s3
                                height: 24; radius: 12
                                color: Qt.rgba(1, 1, 1, 0.04)
                                border.width: 1
                                border.color: Theme.borderSoft
                                Row {
                                    id: chipRow
                                    anchors.centerIn: parent
                                    spacing: Theme.s1
                                    Icon {
                                        text: Icons.forItem(modelData)
                                        size: 11
                                        color: Theme.textSecondary
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                    Text {
                                        text: {
                                            const it = MockData.itemByBit(modelData);
                                            return it ? it.name : ("bit" + modelData);
                                        }
                                        color: Theme.textSecondary
                                        font.family: TypeScale.family
                                        font.pointSize: TypeScale.caption
                                        anchors.verticalCenter: parent.verticalCenter
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        Layout.fillWidth: true
                        text: "测试项集合由产品 profile 固定（profiles/" 
                              + (Session.profile ? Session.profile.name : "") 
                              + ".json，管理员随软件发布维护）。切换产品用顶栏按钮。"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        wrapMode: Text.WordWrap
                    }
                }
            }

            // ---- 版本 ----
            Card {
                title: "版本"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                GridLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    columns: 2
                    columnSpacing: Theme.s7
                    rowSpacing: Theme.s3

                    FieldRow {
                        Layout.fillWidth: true
                        label: "工具版本"
                        value: typeof appVersion !== "undefined" ? "v" + appVersion : "dev"
                        valueColor: Theme.brand
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "构建日期"
                        value: typeof buildDate !== "undefined" ? buildDate : "—"
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "Qt 版本"
                        value: typeof qtVersion !== "undefined" ? qtVersion : "—"
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        label: "构建类型"
                        value: typeof buildType !== "undefined" ? buildType : "—"
                    }
                    FieldRow {
                        Layout.fillWidth: true
                        // 一台机器可能同时存在多个安装（开发 dist / 测试拷贝），
                        // 排"账号怎么不见了"这类问题第一步就是确认在哪个安装里
                        label: "安装目录"
                        value: typeof applicationDirPath !== "undefined"
                               ? applicationDirPath : "—"
                    }
                }
            }

            // ---- 在线升级（工厂需求 2026-08-21：不再逐台手工拷包）----
            // 源 = factory_config.json 的 updateSource（内网共享目录），
            // manifest 差分只拉变化的文件。流程与边界见 update_client.hpp 头注。
            Card {
                title: "在线升级"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: Theme.s4

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2

                            Text {
                                text: {
                                    const cur = "当前 " + (typeof appVersion !== "undefined"
                                                           ? "v" + appVersion : "dev");
                                    switch (UpdateClient.state) {
                                    case UpdateClient.Checking:
                                        return cur + " · 正在检查…";
                                    case UpdateClient.UpToDate:
                                        return cur + " · 已是最新";
                                    case UpdateClient.Available:
                                        return cur + " → 可升级到 v" + UpdateClient.remoteVersion
                                               + "（" + UpdateClient.diffCount + " 个文件，"
                                               + (UpdateClient.diffBytes / 1048576).toFixed(1)
                                               + " MB）";
                                    case UpdateClient.Downloading:
                                        return "正在下载 v" + UpdateClient.remoteVersion
                                               + "…";   // 百分比在下方进度条上，别两处重复
                                    case UpdateClient.Staged:
                                        return "v" + UpdateClient.remoteVersion
                                               + " 已就绪 —— 安装会关闭软件并自动重启";
                                    case UpdateClient.Error:
                                        return cur;
                                    default:
                                        return cur;
                                    }
                                }
                                color: UpdateClient.state === UpdateClient.Staged
                                       ? Theme.brand : Theme.textPrimary
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.body
                                font.weight: TypeScale.weightMedium
                                // 占满可用宽 + 自动换行："可升级到 vX（N 个文件…）"
                                // 那行长，不换行会把按钮挤出卡片
                                Layout.fillWidth: true
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                // 只在出错时占一行；平时不放说明文字（用户 2026-08-21 定）
                                visible: UpdateClient.state === UpdateClient.Error
                                text: UpdateClient.errorText
                                color: Theme.fail
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                                wrapMode: Text.WordWrap
                                Layout.fillWidth: true
                            }
                        }

                        AppButton {
                            text: {
                                switch (UpdateClient.state) {
                                case UpdateClient.Checking:    return "检查中…";
                                case UpdateClient.Available:   return "下载更新";
                                case UpdateClient.Downloading: return "下载中…";
                                case UpdateClient.Staged:      return "安装并重启";
                                default:                       return "检查更新";
                                }
                            }
                            glyph: UpdateClient.state === UpdateClient.Staged
                                   ? Icons.play : Icons.reset
                            kind: UpdateClient.state === UpdateClient.Staged
                                  ? "primary" : "normal"
                            enabled: UpdateClient.state !== UpdateClient.Checking
                                     && UpdateClient.state !== UpdateClient.Downloading
                            Layout.preferredWidth: 136
                            onClicked: {
                                switch (UpdateClient.state) {
                                case UpdateClient.Available: UpdateClient.download(); break;
                                case UpdateClient.Staged:    UpdateClient.apply(); break;
                                default:                     UpdateClient.check(); break;
                                }
                            }
                        }
                    }

                    // 下载进度。自绘而不用样式的 ProgressBar：FluentWinUI3 的条又细
                    // 又浅，工位屏幕上瞟不清 —— 这里要的是"隔一米能看到升到哪了"。
                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: UpdateClient.state === UpdateClient.Downloading
                        spacing: Theme.s1

                        RowLayout {
                            Layout.fillWidth: true

                            Text {
                                text: Math.round(UpdateClient.progress * 100) + "%"
                                color: Theme.brand
                                font.family: "Consolas"
                                font.pointSize: TypeScale.body
                                font.weight: TypeScale.weightBold
                            }
                            Item { Layout.fillWidth: true }
                            Text {
                                // 已下 / 总量，工人能估还要等多久
                                text: (UpdateClient.progress * UpdateClient.diffBytes
                                       / 1048576).toFixed(1)
                                      + " / "
                                      + (UpdateClient.diffBytes / 1048576).toFixed(1)
                                      + " MB"
                                color: Theme.textDim
                                font.family: "Consolas"
                                font.pointSize: TypeScale.caption
                            }
                        }

                        // 轨道 + 圆角填充。宽度变化加缓动，逐文件跳变不显得卡顿。
                        Rectangle {
                            id: dlTrack
                            Layout.fillWidth: true
                            height: 10
                            radius: 5
                            color: Theme.bgDeep
                            border.width: 1
                            border.color: Theme.borderSoft

                            Rectangle {
                                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                                anchors.margins: 2
                                // 起步就给一点宽度：0% 时全空看着像没在动
                                width: Math.max(6, (dlTrack.width - 4) * UpdateClient.progress)
                                radius: 3
                                color: Theme.brand
                                Behavior on width { NumberAnimation { duration: Theme.durFast } }
                            }
                        }
                    }
                }
            }

            // ---- 负责人 ----
            Card {
                title: "联系人"
                fitContent: true
                Layout.fillWidth: true
                Layout.leftMargin: Theme.s5
                Layout.rightMargin: Theme.s5

                ColumnLayout {
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    spacing: Theme.s3

                    Repeater {
                        model: MockData.owners

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: Theme.s3

                            Rectangle {
                                width: 38; height: 38; radius: 19
                                color: Theme.brandWash
                                border.width: 1
                                border.color: Theme.brandEdge
                                Icon {
                                    anchors.centerIn: parent
                                    text: Icons.person
                                    size: 17
                                    color: Theme.brand
                                }
                            }

                            ColumnLayout {
                                spacing: 1
                                Text {
                                    text: modelData.name
                                    color: Theme.textPrimary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.body
                                    font.weight: TypeScale.weightBold
                                }
                                Text {
                                    text: modelData.wecom
                                    color: Theme.textSecondary
                                    font.family: "Consolas"
                                    font.pointSize: TypeScale.caption
                                }
                            }

                            Item { Layout.fillWidth: true }

                            AppButton {
                                text: "企业微信"
                                glyph: Icons.chat
                                kind: "primary"
                                implicitHeight: Theme.hit - 6
                                onClicked: root.openWeCom(modelData.wecom)
                            }

                            AppButton {
                                text: "复制工号"
                                glyph: Icons.copy
                                implicitHeight: Theme.hit - 6
                                onClicked: {
                                    root.copyText(modelData.wecom);
                                    copied.owner = modelData.wecom;
                                }
                            }
                        }
                    }

                    Text {
                        id: copied
                        property string owner: ""
                        visible: owner.length > 0
                        text: "已复制 " + owner
                        color: Theme.pass
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        onOwnerChanged: if (owner.length > 0) clearTimer.restart()
                        Timer {
                            id: clearTimer
                            interval: 2200
                            onTriggered: copied.owner = ""
                        }
                    }


                }
            }

            Item { Layout.preferredHeight: Theme.s5 }
        }
    }

    // 复制用的隐藏文本框（仅 copyText() 使用，id 不能叫 clip，见上）。
    TextEdit {
        id: copyHelper
        visible: false
    }
}
