import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 拉流排障日志入口。产测软件是无控制台的 GUI 程序，stderr 平时没有去处，现场
// 出问题只能截图/复制 —— 所以把日志摆到界面上，工人可直接「复制全部」发回来。
// 日志同时落 dist/logs/ptest_*.log（main.cpp 用 freopen 劫走了整个 stderr）。
//
// ⚠️ 页面上**只留一个按钮**，日志正文与复制/清空全在模态框里：
//    1) 不占预览的高度。早先做成页面里一整行，把小窗挤矮，而 LivePreview 小窗是
//       PreserveAspectCrop，一矮就从上下裁，正好吃掉画面顶部的 OSD 时间戳和底部
//       Tenda logo 下缘（同 README 第 18 条那个坑）；
//    2) 按钮行是工人的主操作区（开始拉流/停止），排障用的东西不该跟它们抢位置。
AppButton {
    id: root

    text: "拉流日志 · " + StreamLog.count
    glyph: Icons.history
    onClicked: logWindow.open()

    Popup {
        id: logWindow

        // 挂到 Overlay 上：不参与页面布局，因此不抢预览的高度。
        // 给足尺寸 —— 日志行很长，窄了全在换行。
        parent: Overlay.overlay
        anchors.centerIn: Overlay.overlay
        width: Math.min(1100, Overlay.overlay ? Overlay.overlay.width - 80 : 1100)
        height: Math.min(620, Overlay.overlay ? Overlay.overlay.height - 80 : 620)

        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        padding: Theme.s4

        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: Theme.radiusLg
        }

        // 包一层 Item：Toast 要浮在内容之上，不能进 ColumnLayout（会被当成
        // 一行排进去）。⚠️ Toast 必须放在**弹出层内部** —— 页面级的那个在
        // overlay 之下，模态框一开就被压住看不见。
        Item {
            anchors.fill: parent

            ColumnLayout {
                anchors.fill: parent
                spacing: Theme.s3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s2

                    Label {
                        text: "拉流日志 · " + StreamLog.count + " 条"
                        font.bold: true
                        color: Theme.textPrimary
                    }
                    Item { Layout.fillWidth: true }
                    AppButton {
                        text: "复制全部"
                        glyph: Icons.copy
                        enabled: StreamLog.count > 0
                        Layout.preferredWidth: 122
                        onClicked: {
                            StreamLog.copyToClipboard();
                            innerToast.show("已复制 " + StreamLog.count + " 条到剪贴板", true);
                        }
                    }
                    AppButton {
                        text: "清空"
                        glyph: Icons.erase
                        enabled: StreamLog.count > 0
                        Layout.preferredWidth: 96
                        onClicked: {
                            StreamLog.clear();
                            innerToast.show("已清空", true);
                        }
                    }
                    AppButton {
                        text: "关闭"
                        Layout.preferredWidth: 96
                        onClicked: logWindow.close()
                    }
                }

                ScrollView {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true

                    TextArea {
                        readOnly: true
                        wrapMode: TextArea.WrapAnywhere
                        font.family: "Consolas"
                        font.pixelSize: 12
                        // 直接拼字符串：StreamLog 内部限 300 条，不会拖慢。
                        text: StreamLog.lines.join("\n")
                        onTextChanged: cursorPosition = length   // 自动滚到底
                    }
                }
            }

            Toast { id: innerToast }
        }
    }
}
