import QtQuick
import ptest
import QtQuick.Controls

// 产测 PC 客户端。测试结果来自 CloudClient 信号（Mock/真云由 cloud_config.json
// 决定），MockData 只提供产品配置（profiles/测试项主表）。构建见根目录 README.md
ApplicationWindow {
    id: win
    width: 1440
    height: 900
    minimumWidth: 1180
    minimumHeight: 720
    visible: true
    // 最大化启动：保留系统标题栏（含最小化/最大化/关闭按钮），同时撑满屏幕。
    // FullScreen 会隐藏系统标题栏，工人找不到关闭按钮。
    visibility: Window.Maximized
    title: "产测软件 v" + (typeof appVersion !== "undefined" ? appVersion : "dev")
    color: Theme.bg

    // 必须显式钉强调色。FluentWinUI3 默认跟随 Windows 系统强调色 ——
    // 产线机器若系统色是红色，复选框/主按钮会变红，与 FAIL 语义直接撞车。
    // 注意：qtquickcontrols2.conf 里写 Accent= 无效，只有 palette.accent 生效。
    palette.accent: Theme.accent

    // 设备准入(规则5):设备上报的 ProductId 与会话产品不符 → 顶栏红警,
    // 全部工位操作禁用(关于页保持可用)。mock 里两者一致,路径存在但不触发。
    readonly property bool mismatch: Session.profile !== null
        && MockData.deviceProductId !== Session.profile.productId

    // 启动流程 = 操作者登录 → 产品选择门 → 工位主界面
    ViewLogin {
        anchors.fill: parent
        visible: Session.user === null
    }

    ProductGate {
        anchors.fill: parent
        visible: Session.user !== null && Session.profile === null
    }

    // 主界面挂 Loader:切换产品 = Session.profile 置空 → 整棵 UI 销毁重建,
    // 设备连接/指令流水/页面状态随会话一起清空,不做逐项清理(会漏)。
    // 切换用户只清 Session.user:回登录页换班,profile 保留,登录后直回主界面。
    Loader {
        anchors.fill: parent
        active: Session.user !== null && Session.profile !== null
        sourceComponent: mainUi
    }

    // 拉流全屏层。必须挂在**窗口根层**（Loader 之外）——
    // 放在工位内容里只能盖住内容区，顶栏和左侧导航栏仍会露出来。
    // 各页面用 liveFull.open("标题") 唤起：id 在 Main 作用域内对
    // Loader 里的页面同样可见（QML 作用域按词法层级向上查找）。
    LiveFullscreen { id: liveFull }

    Component {
        id: mainUi

        Item {
            NavRail {
                id: rail
                width: 96
                // 开发用:--page N 启动即停在第 N 页(截图/联调方便)
                Component.onCompleted: {
                    const a = Qt.application.arguments;
                    const i = a.indexOf("--page");
                    if (i >= 0 && i + 1 < a.length) currentIndex = parseInt(a[i + 1]);
                }
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                onSwitchProduct: switchDialog.open()
                onSwitchUser: Session.user = null   // 保 profile,回登录页即换班
            }

            TopBar {
                id: bar
                height: 76
                anchors { left: rail.right; right: parent.right; top: parent.top }
                // 工位数随产品而变(CS7 五站、CS8 七站),不能按固定索引判断。
                // 关于页恒在末尾 ⇒ 索引 < 工位数即为工位页。
                station: rail.currentIndex < rail.entries.length
                         ? rail.entries[rail.currentIndex].key : ""
                isStation: rail.currentIndex < rail.stations.length
                // 在线 = 设备心跳新鲜(CloudClient 按 PtestHeartbeat.LastUpdate 判,
                // 腾讯云自带的在线状态有延迟不可靠 —— 2026-08-17 需求)
                online: CloudClient.online
                mismatch: win.mismatch
            }

            StackLayout_ {
                anchors {
                    left: rail.right; right: parent.right
                    top: bar.bottom; bottom: parent.bottom
                }
                index: rail.currentIndex
            }

            // 切产品 = 换会话,二次确认(规则1)
            Dialog {
                id: switchDialog
                title: "切换产品？"
                modal: true
                anchors.centerIn: parent
                standardButtons: Dialog.Ok | Dialog.Cancel
                onAccepted: Session.profile = null

                Text {
                    width: 340
                    text: "切换产品将断开当前设备连接并清空指令流水，返回产品选择。"
                    color: Theme.textPrimary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                }
            }
        }
    }

    // 工位页按产品 profile 的 stations 动态生成 —— 工位序列由产品决定
    // （射频线产品多流量/射频/耦合三站且无调焦），不再硬编码 index。
    // 关于页与工位无关，恒定挂在末尾（索引 = stations.length，与 NavRail 一致）。
    // 设备型号不符时工位页整页禁用，关于页不受影响。
    component StackLayout_: Item {
        id: stack
        property int index: 0

        readonly property var stations: Session.profile && Session.profile.stations
                                        ? Session.profile.stations : []

        // 用 Repeater + Loader:切产品时整批重建，旧工位页随之销毁
        //（与"切产品即换会话"一致，不靠逐个清理）。
        Repeater {
            model: stack.stations

            Loader {
                required property int index
                required property var modelData

                anchors.fill: parent
                active: true
                visible: stack.index === index
                enabled: !win.mismatch
                opacity: visible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }

                sourceComponent: {
                    if (modelData.pending === true) return pendingPage;
                    switch (modelData.key) {
                    case "focus":    return focusPage;
                    case "semi":     return semiPage;
                    case "finished": return finishedPage;
                    case "inspect":  return inspectPage;
                    case "repair":   return repairPage;
                    // profile 写了未知 key 也不能白屏 —— 按未实现处理
                    default:         return pendingPage;
                    }
                }
                onLoaded: {
                    if (item && item.hasOwnProperty("station")) {
                        item.station = modelData;
                    }
                }
            }
        }

        // 非工位页:批次文件、关于。都不受设备型号不符影响
        //（批次文件只碰本地文件,关于只读版本,都与在线设备无关）。
        ViewBatchFiles {
            anchors.fill: parent
            visible: stack.index === stack.stations.length
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }
        }

        ViewAbout {
            anchors.fill: parent
            visible: stack.index === stack.stations.length + 1
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }
        }

        // 云链路调试(联调用):Mock/真连切换、逐条下发产测指令、盯上报闭环。
        // 与设备在线状态无关,型号不符也不禁用 —— 它就是用来排链路问题的。
        ViewCloudDebug {
            anchors.fill: parent
            visible: stack.index === stack.stations.length + 2
            opacity: visible ? 1 : 0
            Behavior on opacity { NumberAnimation { duration: Theme.durSlow } }
        }

        Component { id: focusPage;    ViewFocus {} }
        Component { id: semiPage;     ViewFinished { semi: true } }
        Component { id: finishedPage; ViewFinished {} }
        Component { id: inspectPage;  ViewInspect {} }
        Component { id: repairPage;   ViewRepair {} }
        Component { id: pendingPage;  ViewPending {} }
    }
}
