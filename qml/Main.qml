import QtQuick
import ptest
import QtQuick.Controls

// 产测 PC 客户端。目前只有 UI 外观，数据全来自 MockData.qml。
// 构建见根目录 README.md
ApplicationWindow {
    id: win
    width: 1440
    height: 900
    minimumWidth: 1180
    minimumHeight: 720
    visible: true
    title: "产测工具"
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

    Component {
        id: mainUi

        Item {
            NavRail {
                id: rail
                width: 96
                anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
                onSwitchProduct: switchDialog.open()
                onSwitchUser: Session.user = null   // 保 profile,回登录页即换班
            }

            TopBar {
                id: bar
                height: 76
                anchors { left: rail.right; right: parent.right; top: parent.top }
                station: rail.entries[rail.currentIndex].key
                isStation: rail.currentIndex <= 4
                online: true
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

    // 极简栈:只让当前页可见,并做一次淡入(全屏转场 300-400ms 预算内)。
    // 工位页(0-4)在设备型号不符时整页禁用;关于页(5)不受影响。
    component StackLayout_: Item {
        property int index: 0

        ViewFocus    { anchors.fill: parent; visible: index === 0; enabled: !win.mismatch
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewFinished { anchors.fill: parent; visible: index === 1; semi: true; enabled: !win.mismatch
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewFinished { anchors.fill: parent; visible: index === 2; enabled: !win.mismatch
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewInspect  { anchors.fill: parent; visible: index === 3; enabled: !win.mismatch
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewRepair   { anchors.fill: parent; visible: index === 4; enabled: !win.mismatch
                       opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
        ViewAbout    { anchors.fill: parent; visible: index === 5; opacity: visible ? 1 : 0
                       Behavior on opacity { NumberAnimation { duration: Theme.durSlow } } }
    }
}
