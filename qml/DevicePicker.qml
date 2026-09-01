import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 工装卡选择器 —— 右上角显示当前 device_name，点开浮层列出全部、点选切换。
//
// 为什么是浮层而不是列表条/ComboBox：
//   1) **任何占高度的东西都会挤到画面**。调焦页 LivePreview 是 PreserveAspectCrop，
//      可用高度一少就从上下裁，正好吃掉画面顶部 OSD 时间戳和底部 Tenda logo
//      （README 第 18 条；日志面板、名单条各踩过一次）。浮层不参与布局，零成本。
//   2) FluentWinUI3 的 ComboBox 在深色下边框与箭头都很重，顶栏塞一个很难看。
//      这里自己画：平时只是一行等宽字，点开才有面板。
//
// 一处选中，所有工位页与云调试页跟着走：改的是 CloudClient.deviceName，而 transport
// 每次调用都带 deviceName，所以指令自动指向新设备，页面代码不用改。
Item {
    id: root

    // 当前工位 key（focus/semi/finished/...）。浮层里的绿/红点表示**这个工位**
    // 有没有做完 —— 不是全局进度。云调试页不属于工位，传空串即可（不显示点）。
    property string station: ""

    signal message(string text, bool ok)

    // ⚠️ StationProgress.isDone() 是函数调用，QML 不会因为它内部数据变了就重算
    //    绑定。靠这个计数器驱动：进度一变就 +1，绑定里引用它即可重算。
    property int progressTick: 0
    Connections {
        target: StationProgress
        function onChanged() { root.progressTick++; }
    }

    implicitWidth: face.implicitWidth
    implicitHeight: face.implicitHeight

    // ── 平时的样子：一行 device_name + 小三角 ────────────────────────────
    Row {
        id: face
        spacing: Theme.s2
        anchors.verticalCenter: parent.verticalCenter

        Text {
            id: nameText
            text: CloudClient.deviceName.length > 0
                  ? CloudClient.deviceName
                  : (CloudClient.devicesLoading ? "读取名单中…" : "未选设备")
            color: CloudClient.deviceName.length > 0 ? Theme.textPrimary : Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.heading
            font.weight: TypeScale.weightBold
            anchors.verticalCenter: parent.verticalCenter
        }
        Text {
            text: panel.opened ? "▴" : "▾"
            color: Theme.textDim
            font.pointSize: TypeScale.caption
            anchors.verticalCenter: parent.verticalCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        // 命中区放大到整块，戴手套也点得到
        anchors.margins: -Theme.s2
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: panel.opened ? panel.close() : panel.open()
    }

    // ── 浮层：全部工装卡 ─────────────────────────────────────────────────
    Popup {
        id: panel

        // 就贴在触发处正下方、右对齐到它的右边缘。
        //
        // ⚠️ 不要设 parent: Overlay.overlay 再用 mapToItem 手算坐标（我先前就是
        //    这么写的，结果浮层跑到左上角）：在 Popup 内部 `Overlay.overlay` 是
        //    相对 Popup 自身解析的附加属性，绑定首次求值时为 null，
        //    mapToItem(null, …) 给出无效点，x/y 就掉到下限；而且 mapToItem 不会
        //    因祖先移动而重算。
        //    Popup 默认父项即声明它的 Item，且它**本身就渲染在窗口 overlay 层、
        //    不被父项裁剪**，所以用相对坐标即可 —— 顶栏只有 76px 高也不会被切。
        x: root.width - width
        y: root.height + Theme.s3

        width: 300
        // 高度随台数长，但设上限并允许滚动 —— 这里滚动是安全的：浮层不占页面
        // 高度，滚不到画面上去。老板那条"不许滚动"针对的是常驻版面。
        implicitHeight: Math.min(420, listCol.implicitHeight + Theme.s4 * 2)
        padding: Theme.s3

        modal: false
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: Theme.radiusLg
        }

        ColumnLayout {
            id: listCol
            anchors.fill: parent
            spacing: Theme.s2

            RowLayout {
                Layout.fillWidth: true
                Text {
                    text: "工装卡 · " + CloudClient.devices.length + " 张"
                    color: Theme.textSecondary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    font.weight: TypeScale.weightMedium
                }
                Item { Layout.fillWidth: true }
                // 图例：绿/红点的含义要写出来 —— 不写工人只会猜成"在线/离线"。
                // ⚠️ 点和文字必须分开着色。早先写成一个 Text（"● 已完成本工位"），
                //    整串都被 textDim 压成灰点，跟行里的绿点对不上、图例反而误导。
                Row {
                    visible: root.station.length > 0
                    spacing: Theme.s1 + 2

                    Rectangle {
                        width: 9; height: 9; radius: 4.5
                        color: Theme.pass
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "已完成本工位"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            ListView {
                Layout.fillWidth: true
                Layout.fillHeight: true
                implicitHeight: contentHeight
                clip: true
                model: CloudClient.devices
                spacing: 2

                delegate: Rectangle {
                    id: row
                    required property var modelData

                    readonly property bool isCurrent:
                        modelData.deviceName === CloudClient.deviceName
                    readonly property int deviceStatus:
                        Number.isInteger(modelData.status) ? modelData.status : 2
                    readonly property bool isOnline: deviceStatus === 1
                    readonly property bool stationDone:
                        root.progressTick >= 0        // 依赖它以便进度变化时重算
                        && root.station.length > 0
                        && StationProgress.isDone(CloudClient.productId,
                                                  modelData.deviceName, root.station)

                    width: ListView.view.width
                    height: 40
                    radius: Theme.radius
                    color: isCurrent ? Theme.brandWash
                           : rowHover.containsMouse ? Theme.surfaceAlt
                           : "transparent"
                    border.width: isCurrent ? 1 : 0
                    border.color: Theme.brand

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: Theme.s3
                        anchors.rightMargin: Theme.s3
                        spacing: Theme.s2

                        // 工位完成点：绿=本工位已做完，红=未做完。
                        // ⚠️ 这不是在线状态 —— 在线看后面那个字。
                        Rectangle {
                            visible: root.station.length > 0
                            width: 9; height: 9; radius: 4.5
                            color: row.stationDone ? Theme.pass : Theme.fail
                        }

                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.deviceName
                            color: Theme.textPrimary
                            font.family: "Consolas"
                            font.pointSize: TypeScale.body
                            font.weight: row.isCurrent ? TypeScale.weightBold
                                                       : TypeScale.weightRegular
                        }

                        Text {
                            text: row.deviceStatus === 1 ? "在线"
                                  : row.deviceStatus === 0 ? "离线"
                                  : row.deviceStatus === 3 ? "未激活"
                                  : "状态未知"
                            color: row.deviceStatus === 1 ? Theme.pass
                                   : row.deviceStatus === 3 ? Theme.warn
                                   : Theme.textDim
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                        }
                    }

                    MouseArea {
                        id: rowHover
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.select(row.modelData))
                                panel.close();
                        }
                    }
                }
            }

            Text {
                visible: CloudClient.devices.length === 0
                Layout.fillWidth: true
                text: CloudClient.devicesLoading
                      ? "正在读取设备名单…"
                      : "该产品下没有设备 —— 确认工装卡已插好、设备已上电"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s2

                AppButton {
                    Layout.fillWidth: true
                    text: "刷新名单"
                    glyph: Icons.reset
                    implicitHeight: 32
                    onClicked: CloudClient.refreshDevices()
                }

                // 换下一批 10 台时点一次：清掉本产品所有卡的工位进度。
                // ⚠️ 必须有这个动作。工装卡是复用的，不清会带着上一批的绿点，而
                //    自动跳台**会因此直接跳过没测的机器** —— 漏测流到客户手上。
                //    不能靠"读到设备真值会自愈"兜底：跳哪台是在读之前就决定的。
                AppButton {
                    Layout.fillWidth: true
                    text: "开始新批次"
                    glyph: Icons.erase
                    kind: "danger"
                    implicitHeight: 32
                    enabled: CloudClient.devices.length > 0
                    onClicked: newBatchConfirm.open()
                }
            }

            Dialog {
                id: newBatchConfirm
                title: "开始新一批？"
                modal: true
                anchors.centerIn: Overlay.overlay
                standardButtons: Dialog.Ok | Dialog.Cancel
                onAccepted: {
                    StationProgress.clearProduct(CloudClient.productId);
                    root.message("已清空本批进度，可以开始新一批", true);
                }

                Text {
                    width: 320
                    text: "将清空当前产品下全部工装卡的工位进度（绿点全部变红）。"
                          + "换上新一批设备后点这里，否则自动跳台会跳过未测的机器。"
                    color: Theme.textPrimary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // 返回 true = 已切换（调用方可关浮层）
    function select(d) {
        if (!d)
            return false;
        if (d.online !== true) {
            const status = Number.isInteger(d.status) ? d.status : 2;
            if (status === 3)
                root.message("该设备从未激活过 —— 检查三元组是否已写入、写对", false);
            else if (status === 2)
                root.message("暂时无法获取该设备状态，请刷新名单或检查云 API", false);
            else
                root.message("该设备离线，先确认工装卡已插好、设备已上电", false);
            return false;
        }
        if (d.deviceName === CloudClient.deviceName)
            return true;
        CloudClient.deviceName = d.deviceName;
        CloudClient.refreshInfo();   // 顺手拿到三个时间戳，用于校正本地进度
        root.message("已切到 " + d.deviceName, true);
        return true;
    }

    // 名单要主动问；在线状态会变（装壳时断电、换批次换卡），周期性重刷。
    // 15s 是"谁在线"的粒度，不是心跳粒度。
    Component.onCompleted: CloudClient.refreshDevices()

    Connections {
        target: CloudClient
        // 切产品后 productId 变了，名单要重问 —— 这是"按产品过滤"的入口
        function onDeviceChanged() { poll.restart(); }
    }

    Timer {
        id: poll
        interval: 15000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: CloudClient.refreshDevices()
    }
}
