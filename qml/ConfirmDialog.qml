import QtQuick
import ptest
import QtQuick.Controls

// 可复用二次确认框。产线防误触的统一入口:
//   confirm.ask("写入调焦标识？", "说明文字", function () { 真实动作 })
//
// 什么按钮需要确认(取舍标准,新增按钮时照此判断):
//   要 —— 写设备状态的(写阶段标识)、人工判定记录(听到了/没听到)、
//         跳过测试项、恢复默认、重启、清除分区、切换产品
//   不要 —— 高频且可重来的(开始拉流/停止/重新读取/开始自动化测试),
//           确认疲劳会让工人闭眼点 OK,反而失去保护
Dialog {
    id: dlg

    property string body: ""
    property var onOk: null

    modal: true
    anchors.centerIn: parent
    standardButtons: Dialog.Ok | Dialog.Cancel

    function ask(title_, body_, cb) {
        title = title_;
        body = body_;
        onOk = cb;
        open();
    }

    onAccepted: if (onOk) onOk()

    Text {
        width: 340
        text: dlg.body
        color: Theme.textPrimary
        font.family: TypeScale.family
        font.pointSize: TypeScale.body
        wrapMode: Text.WordWrap
    }
}
