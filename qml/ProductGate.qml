import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 启动门:软件第一屏 = 选产品。选定后锁定会话(ProductId/测试项集合,
// 真实实现还锁凭证与工装卡校验基准),再进主界面。
// 产品页不再放工位侧边栏 —— 产线一台电脑一个班次只跑一种产品,
// 产品是会话属性不是页面,混在工位流里会被误点。
Item {
    id: gate

    // 开发用:--autoselect 跳过启动门直接进首个可用产品(自动化/联调方便)
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--autoselect") >= 0)
            Session.profile = MockData.profiles.find(p => p.enabled) || null
    }

    Rectangle { anchors.fill: parent; color: Theme.bg }

    ColumnLayout {
        anchors.centerIn: parent
        width: 560
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

        Text {
            text: "选择产品进入 · 会话将锁定该产品"
            color: Theme.textSecondary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            Layout.alignment: Qt.AlignHCenter
            Layout.bottomMargin: Theme.s4
        }

        Repeater {
            model: MockData.profiles

            Rectangle {
                id: card
                required property var modelData
                readonly property bool usable: modelData.enabled

                Layout.fillWidth: true
                height: 86
                radius: Theme.radiusLg
                color: usable && hh.hovered ? Theme.surfaceAlt : Theme.surface
                border.width: 1
                border.color: usable && hh.hovered ? Theme.brandEdge : Theme.borderSoft
                opacity: usable ? 1.0 : 0.45
                Behavior on color { ColorAnimation { duration: Theme.durFast } }
                Behavior on border.color { ColorAnimation { duration: Theme.durFast } }

                HoverHandler { id: hh; enabled: card.usable }
                TapHandler {
                    // 悬停在"测试项"按钮上时禁掉整卡点击,防止点按钮误选中产品
                    enabled: card.usable && !cfgHover.hovered
                    onTapped: Session.profile = card.modelData
                }

                Rectangle {
                    visible: card.usable && hh.hovered
                    width: 3; radius: 2
                    color: Theme.brand
                    anchors { left: parent.left; top: parent.top; bottom: parent.bottom
                              topMargin: Theme.s4; bottomMargin: Theme.s4 }
                }

                RowLayout {
                    anchors { fill: parent; leftMargin: Theme.s5; rightMargin: Theme.s5 }
                    spacing: Theme.s4

                    Rectangle {
                        width: 44; height: 44; radius: Theme.radius
                        color: card.usable ? Theme.brandWash : Qt.rgba(1, 1, 1, 0.04)
                        Icon {
                            anchors.centerIn: parent
                            text: Icons.navProduct
                            size: 20
                            color: card.usable ? Theme.brand : Theme.textDim
                        }
                    }

                    ColumnLayout {
                        spacing: 2
                        Layout.fillWidth: true

                        Row {
                            spacing: Theme.s2
                            Text {
                                text: card.modelData.name
                                color: card.usable ? Theme.textPrimary : Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.heading
                                font.weight: TypeScale.weightBold
                            }
                            Text {
                                text: card.modelData.desc
                                color: Theme.textDim
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.caption
                                anchors.baseline: parent.children[0].baseline
                            }
                        }
                        Text {
                            // 工位数也列出来:不同产品工艺路线不同(射频线多三站),
                            // 选产品时就能看出差异,不用进去才发现。
                            // ⚠️ 必须可压缩(fillWidth+elide):这行不肯让步的话,
                            // 加上"测试项"按钮后行宽超限,右侧小三角会被顶出卡片。
                            Layout.fillWidth: true
                            elide: Text.ElideRight
                            text: card.usable
                                  ? "ProductId  " + card.modelData.productId
                                    + "   ·   工位 " + card.modelData.stations.length + " 站"
                                    + "   ·   测试项 " + card.modelData.items.length + " 项"
                                  : "ProductId  （待建模）"
                            color: Theme.textDim
                            font.family: "Consolas"
                            font.pointSize: TypeScale.caption
                        }
                    }

                    // 管理员动作(需求① 2026-08-17):配置本产品准成品/成品的
                    // 测试项勾选。普通角色不可见。
                    AppButton {
                        id: cfgBtn
                        visible: card.usable && Session.isSuper
                        text: "测试项"
                        glyph: Icons.navFinished
                        implicitHeight: Theme.hit - 12
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: itemCfg.openFor(card.modelData)
                        // 悬停感知放按钮内部:用于禁掉整卡点击,防误选产品
                        HoverHandler { id: cfgHover }
                    }

                    // 待建模产品可见但置灰(规则6):看得见"它在计划里",选不进坏会话
                    Rectangle {
                        visible: !card.usable
                        width: badge.implicitWidth + Theme.s3
                        height: 24; radius: 12
                        color: Qt.rgba(0.980, 0.800, 0.082, 0.10)
                        border.width: 1
                        border.color: Qt.rgba(0.980, 0.800, 0.082, 0.40)
                        Text {
                            id: badge
                            text: "待建模"
                            color: Theme.warn
                            font.family: TypeScale.family
                            font.pointSize: TypeScale.caption
                            anchors.centerIn: parent
                        }
                    }

                    Icon {
                        visible: card.usable
                        text: Icons.play
                        size: 16
                        color: hh.hovered ? Theme.brand : Theme.textDim
                    }
                }
            }
        }

        // 新增入口:普通工人不可编辑 profile,入口只指路
        Rectangle {
            Layout.fillWidth: true
            height: 52
            radius: Theme.radiusLg
            color: "transparent"
            border.width: 1
            border.color: Theme.borderSoft

            HoverHandler { id: addHover }
            TapHandler { onTapped: addDialog.open() }

            Row {
                anchors.centerIn: parent
                spacing: Theme.s2
                Icon {
                    text: Icons.add
                    size: 14
                    color: addHover.hovered ? Theme.textSecondary : Theme.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: "新增产品"
                    color: addHover.hovered ? Theme.textSecondary : Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    anchors.verticalCenter: parent.verticalCenter
                }
            }
        }

        Text {
            text: "工具 " + (typeof appVersion !== "undefined" ? "v" + appVersion : "dev")
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.s5
        }
    }

    Dialog {
        id: addDialog
        title: "新增产品"
        modal: true
        anchors.centerIn: parent
        standardButtons: Dialog.Ok

        Text {
            width: 360
            text: "产品 profile 随软件发布、由管理员维护：安装目录 profiles/*.json"
                + "（productId / 显示名 / 固定测试项集合 / 工装卡模板）。"
                + "普通工位电脑不提供编辑入口。"
            color: Theme.textPrimary
            font.family: TypeScale.family
            font.pointSize: TypeScale.body
            wrapMode: Text.WordWrap
        }
    }

    // 勾选框(测试项配置用):user 交互会打断 checked 绑定,靠 onSelChanged
    // 显式回同步 —— 否则点"全选"后单项框不刷新(QML 绑定被交互覆盖的老坑)。
    component SelBox: CheckBox {
        id: box
        property string st: ""
        property string grp: ""
        property string keyName: ""
        checked: itemCfg.isOn(st, grp, keyName)
        onToggled: itemCfg.setSel(st, grp, keyName, checked)
        font.family: TypeScale.family
        font.pointSize: TypeScale.body
        Connections {
            target: itemCfg
            function onSelChanged() {
                box.checked = itemCfg.isOn(box.st, box.grp, box.keyName);
            }
        }
    }

    // 测试项配置(需求① 2026-08-17):按 工位 × 自动/人工 分组勾选 + 组内全选。
    // 保存进 factory_config.json(FactoryConfig 单例),工厂也可直接改文件;
    // 工位页的测试队列 = 此处勾选 ∩ 产品 profile ∩ 设备 SupportedItems。
    Dialog {
        id: itemCfg
        modal: true
        anchors.centerIn: parent
        title: "测试项配置" + (product !== null ? " · " + product.name : "")
        standardButtons: Dialog.Save | Dialog.Cancel

        property var product: null
        readonly property var autoAll: product !== null
            ? product.items.filter(b => MockData.manualBits.indexOf(b) < 0) : []
        // sel[station][group][key] = bool。整对象替换触发刷新(selChanged)。
        property var sel: ({})

        function openFor(p) {
            product = p;
            const manualAll = MockData.manualChecks.map(c => c.key);
            const aAll = p.items.filter(b => MockData.manualBits.indexOf(b) < 0);
            var s = {};
            ["semi", "finished"].forEach(function (st) {
                const a = FactoryConfig.stationItems(p.productId, st, "auto", aAll);
                const m = FactoryConfig.stationItems(p.productId, st, "manual", manualAll);
                var sa = {}, sm = {};
                aAll.forEach(function (b) { sa[b] = a.indexOf(b) >= 0; });
                manualAll.forEach(function (k) { sm[k] = m.indexOf(k) >= 0; });
                s[st] = { auto: sa, manual: sm };
            });
            sel = s;
            open();
        }

        function setSel(st, grp, key, val) {
            var s = JSON.parse(JSON.stringify(sel));
            s[st][grp][key] = val;
            sel = s;
        }
        function setAll(st, grp, val) {
            var s = JSON.parse(JSON.stringify(sel));
            for (var k in s[st][grp]) s[st][grp][k] = val;
            sel = s;
        }
        function allOn(st, grp) {
            if (sel[st] === undefined) return false;
            for (var k in sel[st][grp]) if (!sel[st][grp][k]) return false;
            return true;
        }
        function isOn(st, grp, key) {
            return sel[st] !== undefined && sel[st][grp][key] === true;
        }

        onAccepted: {
            ["semi", "finished"].forEach(function (st) {
                var a = [], m = [];
                for (var b in sel[st].auto) if (sel[st].auto[b]) a.push(parseInt(b));
                for (var k in sel[st].manual) if (sel[st].manual[k]) m.push(k);
                FactoryConfig.setStationItems(itemCfg.product.productId, st, "auto", a);
                FactoryConfig.setStationItems(itemCfg.product.productId, st, "manual", m);
            });
        }

        contentItem: Row {
            spacing: Theme.s6
            padding: Theme.s2

            Repeater {
                model: [{ st: "semi", name: "准成品" }, { st: "finished", name: "成品" }]

                Column {
                    required property var modelData
                    readonly property string st: modelData.st
                    spacing: Theme.s1
                    width: 250

                    Text {
                        text: modelData.name
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.heading
                        font.weight: TypeScale.weightBold
                        bottomPadding: Theme.s2
                    }

                    // 全选框不用 SelBox —— 它的回同步键是 "__all__" 会被拍回
                    // false;这里显式按 allOn 回同步。
                    CheckBox {
                        id: allAuto
                        text: "自动测试（全选）"
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightBold
                        checked: itemCfg.allOn(parent.st, "auto")
                        onToggled: itemCfg.setAll(parent.st, "auto", checked)
                        Connections {
                            target: itemCfg
                            function onSelChanged() {
                                allAuto.checked = itemCfg.allOn(allAuto.parent.st, "auto");
                            }
                        }
                    }
                    Repeater {
                        model: itemCfg.autoAll
                        SelBox {
                            required property var modelData
                            st: parent.st; grp: "auto"
                            keyName: "" + modelData
                            leftPadding: Theme.s5
                            text: {
                                const it = MockData.itemByBit(modelData);
                                return it ? it.name : ("bit" + modelData);
                            }
                        }
                    }

                    CheckBox {
                        id: allManual
                        text: "人工判定（全选）"
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightBold
                        checked: itemCfg.allOn(parent.st, "manual")
                        onToggled: itemCfg.setAll(parent.st, "manual", checked)
                        Connections {
                            target: itemCfg
                            function onSelChanged() {
                                allManual.checked = itemCfg.allOn(allManual.parent.st, "manual");
                            }
                        }
                    }
                    Repeater {
                        model: MockData.manualChecks
                        SelBox {
                            required property var modelData
                            st: parent.st; grp: "manual"
                            keyName: modelData.key
                            leftPadding: Theme.s5
                            // 只列项目名,不带判据说明(拥挤);指示灯按颜色区分
                            text: modelData.group
                                  + (modelData.short.length > 0 ? " · " + modelData.short : "")
                        }
                    }
                }
            }
        }
    }
}
