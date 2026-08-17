import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

// 批次文件页（非工位，所有角色可用）。
//
// 只做两件事，对应工艺路线的两端：
//   ① 导入 InputData1.txt —— 腾达/计划给的批次文件，一台机器一行，
//      内含 MAC/SN/四元组/SUID/语言等。打印房据它印铜板贴，产测据它写身份。
//      **PC 只负责解析，不负责生成** —— 文件来自上游。
//   ② 导出 InputData2.txt —— 比 InputData1 只多一列 IMEI（产测时从 4G 模块读出）。
//      产线据它印 IMEI 贴纸，最后核对铜板贴 UUID 与 IMEI 贴纸是否对应。
//
// 为什么不放在工位页里：这两件事是**批次级**的（开线前导入一次、批次跑完导出一次），
// 而工位页的前提是"有一台设备在线"。放一起会让工人在整班作业中误点覆盖批次文件。
//
// ⚠️ 列语义待与产线确认：下面 headers 是按样例文件推断的，改这一处即可全局生效。
Item {
    id: root

    // 推断的列名。前 8 列较有把握，后 4 列存疑（见页内提示）。
    readonly property var headers: [
        "MAC", "SN", "DeviceName", "UUID", "DeviceSecret",
        "ProductKey", "ProductSecret", "语言", "设备标识", "默认密码",
        "SSID 2.4G", "SSID 5G"
    ]

    property string srcName: ""       // 已导入的文件名
    property var rows: []             // 解析结果：每行一个字符串数组
    property int colCount: 0
    property string parseNote: ""     // 解析异常提示（列数不齐等）
    property string exportNote: ""

    // 已入库台数与每台 IMEI 来自会话批次存储 —— 成品工位校验通过后写入
    //（Session.markBatchDone）;校验失败/未测的留空白。
    readonly property int testedCount: Session.batchDoneCount
    function imeiFor(rowIndex) {
        return rowIndex < Session.batchImei.length ? Session.batchImei[rowIndex] : "";
    }

    function parseText(text) {
        var out = [];
        var widths = {};
        var lines = text.split(/\r?\n/);
        for (var i = 0; i < lines.length; ++i) {
            var line = lines[i].trim();
            if (line.length === 0) continue;
            // 制表符或空格分隔都吃 —— 产线给的文件两种都见过。
            var cols = line.split(/\s+/);
            widths[cols.length] = true;
            out.push(cols);
        }
        rows = out;
        colCount = out.length > 0 ? out[0].length : 0;
        var kinds = Object.keys(widths);
        parseNote = kinds.length > 1
            ? "⚠ 各行列数不一致（出现 " + kinds.join(" / ") + " 列），请检查文件是否被编辑器改动过"
            : "";
        exportNote = "";
        // 批次入会话:成品工位据此做 MAC 检索/入库标记/IMEI 回填
        Session.setBatch(srcName, out);
    }

    // 开发/演示用:--sample 启动即加载安装目录下的样例文件,
    // 省得每次手点文件对话框(也让"解析是否正确"可被脚本验证)。
    // --selftest-export=<路径> 额外把 InputData2 写到指定路径 ——
    // 文件对话框没法脚本化,这条通道让"导出内容与列数"能被自动验证。
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--sample") < 0) return;
        var url = "file:///" + applicationDirPath + "/sample/inputdata1_sample.txt";
        var text = FileIo.readText(url);
        if (text.length === 0) {
            parseNote = "⚠ " + FileIo.lastError();
            return;
        }
        srcName = FileIo.fileName(url) + "（样例）";
        parseText(text);

        var args = Qt.application.arguments;
        for (var i = 0; i < args.length; ++i) {
            if (args[i].indexOf("--selftest-export=") !== 0) continue;
            var out = args[i].substring("--selftest-export=".length);
            var lines = [];
            for (var r = 0; r < rows.length; ++r)
                lines.push(rows[r].join("\t") + "\t" + imeiFor(r));
            var ok = FileIo.writeText("file:///" + out, lines.join("\n") + "\n");
            exportNote = ok ? "✓ selftest 已写 " + out : "⚠ " + FileIo.lastError();
        }
    }

    FileDialog {
        id: importDialog
        title: "选择 InputData1 文件"
        nameFilters: ["文本文件 (*.txt)", "全部文件 (*)"]
        onAccepted: {
            var text = FileIo.readText(selectedFile);
            if (text.length === 0) {
                root.parseNote = "⚠ " + FileIo.lastError();
                root.rows = [];
                root.srcName = "";
                return;
            }
            root.srcName = FileIo.fileName(selectedFile);
            root.parseText(text);
        }
    }

    FileDialog {
        id: exportDialog
        title: "导出 InputData2 文件"
        fileMode: FileDialog.SaveFile
        defaultSuffix: "txt"
        currentFile: "file:///inputdata2.txt"
        nameFilters: ["文本文件 (*.txt)"]
        onAccepted: {
            var lines = [];
            for (var i = 0; i < root.rows.length; ++i) {
                // InputData2 = InputData1 原样 + 末列 IMEI（未测到的留空占位）
                lines.push(root.rows[i].join("\t") + "\t" + root.imeiFor(i));
            }
            var ok = FileIo.writeText(selectedFile, lines.join("\n") + "\n");
            root.exportNote = ok
                ? "✓ 已导出 " + FileIo.fileName(selectedFile)
                  + "（" + root.rows.length + " 行，含 IMEI " + root.testedCount + " 台）"
                : "⚠ " + FileIo.lastError();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ---- ① 导入 ----
        Card {
            title: "① 导入 InputData1  ·  批次文件由上游提供，PC 只解析"
            titleIcon: Icons.save
            Layout.fillWidth: true
            fitContent: true   // 高度由内容定，不开会被 fillHeight 的预览卡压成 0

            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s3

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Theme.s3

                    AppButton {
                        text: "选择 InputData1.txt"
                        glyph: Icons.save
                        kind: "primary"
                        onClicked: importDialog.open()
                    }

                    Text {
                        Layout.fillWidth: true
                        text: root.srcName.length > 0
                              ? root.srcName + "   ·   " + root.rows.length + " 台   ·   "
                                + root.colCount + " 列"
                              : "未导入。样例文件在安装目录 sample/inputdata1_sample.txt"
                        color: root.srcName.length > 0 ? Theme.textPrimary : Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        elide: Text.ElideMiddle
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: root.parseNote.length > 0
                    text: root.parseNote
                    color: Theme.warn
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ---- 表格预览 ----
        Card {
            title: "批次内容预览" + (root.rows.length > 0 ? "（前 12 台）" : "")
            titleIcon: Icons.history
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.topMargin: Theme.s6
                spacing: Theme.s2

                Text {
                    Layout.fillWidth: true
                    text: "列名按样例推断，待与产线/工艺确认；最后一列 IMEI 是产测读到后补的（InputData2 才有）"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WordWrap
                }

                // 12 列放不下一屏，横向可滚
                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: grid.width
                    contentHeight: grid.height
                    clip: true
                    flickableDirection: Flickable.HorizontalAndVerticalFlick
                    ScrollBar.horizontal: ScrollBar { policy: ScrollBar.AsNeeded }

                    Column {
                        id: grid
                        spacing: 0

                        // 表头
                        Row {
                            spacing: 0
                            Repeater {
                                model: root.headers.length + 1
                                Rectangle {
                                    required property int index
                                    width: index === 3 || index === 4 ? 250 : 130
                                    height: 30
                                    color: Theme.bgDeep
                                    border.width: 1
                                    border.color: Theme.borderSoft
                                    Text {
                                        anchors.centerIn: parent
                                        text: index < root.headers.length
                                              ? root.headers[index] : "IMEI"
                                        color: index === root.headers.length
                                               ? Theme.brand : Theme.textSecondary
                                        font.family: TypeScale.family
                                        font.pointSize: TypeScale.caption
                                        font.weight: TypeScale.weightBold
                                    }
                                }
                            }
                        }

                        // 数据行
                        Repeater {
                            model: Math.min(12, root.rows.length)
                            Row {
                                required property int index
                                readonly property var cols: root.rows[index]
                                spacing: 0
                                Repeater {
                                    model: root.headers.length + 1
                                    Rectangle {
                                        required property int index
                                        readonly property bool imeiCol:
                                            index === root.headers.length
                                        width: index === 3 || index === 4 ? 250 : 130
                                        height: 26
                                        color: "transparent"
                                        border.width: 1
                                        border.color: Theme.borderSoft
                                        Text {
                                            anchors.fill: parent
                                            anchors.margins: 6
                                            verticalAlignment: Text.AlignVCenter
                                            // 与表头一致居中。两侧留等宽内距,
                                            // 长字段 elide 时不会贴到格线上。
                                            horizontalAlignment: Text.AlignHCenter
                                            text: imeiCol
                                              ? (root.imeiFor(parent.parent.index).length > 0
                                                 ? root.imeiFor(parent.parent.index) : "—")
                                              : (index < parent.parent.cols.length
                                                 ? parent.parent.cols[index] : "")
                                            color: imeiCol ? Theme.brand : Theme.textPrimary
                                            font.family: "Consolas"
                                            font.pointSize: TypeScale.caption
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- ② 导出 ----
        Card {
            title: "② 导出 InputData2  ·  = InputData1 + IMEI 列"
            titleIcon: Icons.copy
            Layout.fillWidth: true
            fitContent: true

            RowLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s3

                AppButton {
                    text: "导出 InputData2.txt"
                    glyph: Icons.copy
                    kind: "primary"
                    enabled: root.rows.length > 0
                    onClicked: exportDialog.open()
                }

                Text {
                    Layout.fillWidth: true
                    text: root.exportNote.length > 0 ? root.exportNote
                          : (root.rows.length === 0
                             ? "先导入 InputData1"
                             : "本批 " + root.rows.length + " 台，已入库 "
                               + root.testedCount + " 台；未入库/校验失败的 IMEI 列留空")
                    color: root.exportNote.indexOf("⚠") === 0 ? Theme.warn
                           : (root.exportNote.length > 0 ? Theme.pass : Theme.textDim)
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                }
            }
        }
    }
}
