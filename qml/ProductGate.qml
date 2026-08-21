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

    // 当前登录者可选的型号。技术员可以被限定只做某几个型号（账号管理页里设，
    // 空 = 全部）；工程师/超级用户不受限，他们要能进任意型号配测试项、排障。
    readonly property var visibleProfiles: {
        const all = ProfileStore.profiles;
        if (!Session.user || Session.canManageTech)
            return all;                      // 非技术员：全部可见
        const mask = Session.user.phoneMask !== undefined ? Session.user.phoneMask : "";
        const out = [];
        for (let i = 0; i < all.length; ++i) {
            // 按型号名过滤，不是 productId —— 两个型号现在共用同一个 productId，
            // 按 id 过滤会"授一个送一个"
            if (AccountStore.allowsProduct(mask, all[i].name))
                out.push(all[i]);
        }
        return out;
    }

    // 开发用:--autoselect 跳过启动门直接进首个可用产品(自动化/联调方便)
    Component.onCompleted: {
        if (Qt.application.arguments.indexOf("--autoselect") >= 0) {
            const list = gate.visibleProfiles;
            for (let i = 0; i < list.length; ++i) {
                if (list[i].enabled) { Session.profile = list[i]; break; }
            }
        }
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
            // 型号来自 ProfileStore（profiles.json），不再是 MockData 里的硬编码 ——
            // 加型号不用重新构建。技术员只看到被授权的型号（见 visibleProfiles）。
            model: gate.visibleProfiles

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
                    // 悬停在卡内任一管理按钮上时禁掉整卡点击，防止点按钮误选中产品。
                    // ⚠️ 新增按钮都要加进这个条件 —— 漏一个就会"点按钮顺带把产品选了"，
                    //    而选产品是锁定会话的动作，误触代价大。
                    enabled: card.usable && !cfgHover.hovered && !editHover.hovered
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
                    // 测试项勾选。技术员不可见 —— 用 canEditProfile 而不是 isSuper，
                    // 工程师也有这个权限（2026-08-21 用户定）。
                    AppButton {
                        id: cfgBtn
                        visible: card.usable && Session.canEditProfile
                        text: "测试项"
                        glyph: Icons.navFinished
                        implicitHeight: Theme.hit - 12
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: itemCfg.openFor(card.modelData)
                        // 悬停感知放按钮内部:用于禁掉整卡点击,防误选产品
                        HoverHandler { id: cfgHover }
                    }

                    // 改型号本身（名称/ProductId/能力位）。与"测试项"分开：
                    // 前者是型号定义，后者是本工位测哪些项 —— 两件事、两个存储
                    //（profiles.json vs factory_config.json）。
                    AppButton {
                        id: editBtn
                        visible: Session.canEditProfile
                        text: "型号"
                        glyph: Icons.device
                        implicitHeight: Theme.hit - 12
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: addDialog.openFor(card.modelData)
                        HoverHandler { id: editHover }
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

        // 管理入口行。账号管理放这儿而**不是**登录后弹模态框（2026-08-21 讨论）：
        // 模态框每班次都弹，工人很快会条件反射地关掉，而管理员真要用时它已经关了；
        // 这一页本来就是登录后第一屏，且已有"测试项"这类管理动作，放同一处不新增
        // 概念，也不打断流程 —— 要用就点，不用就走。技术员看不到账号入口。
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s3

            // 新增型号。技术员看不到 —— canEditProfile 现在含工程师（用户 2026-08-21 定）
            Rectangle {
                Layout.fillWidth: true
                visible: Session.canEditProfile
                height: 52
                radius: Theme.radiusLg
                color: "transparent"
                border.width: 1
                border.color: addHover.hovered ? Theme.border : Theme.borderSoft

                HoverHandler { id: addHover }
                TapHandler { onTapped: addDialog.openFor(null) }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s2
                    // 亮度/粗细对齐上方「测试项」按钮（textPrimary + Medium）：
                    // 原先 textDim 太暗看不清（2026-08-21 反馈）。悬停效果不变。
                    Icon {
                        text: Icons.add
                        size: 14
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "新增型号"
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }

            // 账号管理：canManageTech = 非技术员
            Rectangle {
                Layout.fillWidth: true
                visible: Session.canManageTech
                height: 52
                radius: Theme.radiusLg
                color: "transparent"
                border.width: 1
                border.color: acctHover.hovered ? Theme.border : Theme.borderSoft

                HoverHandler { id: acctHover }
                TapHandler { onTapped: acctDialog.open() }

                Row {
                    anchors.centerIn: parent
                    spacing: Theme.s2
                    // 同上：亮度/粗细对齐「测试项」，悬停效果不变
                    Icon {
                        text: Icons.person
                        size: 14
                        color: Theme.textPrimary
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "账号管理"
                        color: Theme.textPrimary
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                        font.weight: TypeScale.weightMedium
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        // 当前登录者 + 退出登录。放居中下方（2026-08-21 用户定）：顶部是品牌区，
        // 底部本来就是管理动作地带。这块同时解决"登错账号的人被困在这页"——
        // 原先这页没有任何退路。
        //
        // 按钮做成与上方「测试项」同等尺寸（用 AppButton，命中区 Theme.hit）：
        // 换班每天都要点，之前那行小字太难瞄。样式用 normal 而不是 primary ——
        // 一屏只该有一个主操作，那是"选产品"；悬停时边框转主题色（AppButton 的
        // hover 语义），既醒目又不抢主操作的视觉位。
        ColumnLayout {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.s4
            spacing: Theme.s2

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: Theme.s2

                Icon {
                    text: Icons.person
                    size: 13
                    color: Theme.textDim
                    anchors.verticalCenter: parent.verticalCenter
                }
                Text {
                    text: (Session.user ? Session.user.name : "")
                          + " · " + Session.roleLabel()
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            AppButton {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 176
                text: "退出登录"
                glyph: Icons.person
                hoverAccent: true   // 悬停边框转主题色（2026-08-21 用户定）
                onClicked: {
                    OperatorLogin.logout();   // 清云身份 token
                    Session.user = null;      // 回登录页；产品保留（工位属性）
                }
            }
        }

        Text {
            text: "工具 " + (typeof appVersion !== "undefined" ? "v" + appVersion : "dev")
            color: Theme.textDim
            font.family: "Consolas"
            font.pointSize: TypeScale.caption
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Theme.s2
        }
    }

    // 账号管理。整页塞进对话框：这件事与"选产品"无关，不该占产品选择页的版面，
    // 也不该进主界面左侧栏（那是工位导航，账号不是工位）。
    Dialog {
        id: acctDialog
        modal: true
        anchors.centerIn: Overlay.overlay
        width: Math.min(920, Overlay.overlay ? Overlay.overlay.width - 80 : 920)
        height: Math.min(640, Overlay.overlay ? Overlay.overlay.height - 80 : 640)
        padding: 0
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            color: Theme.bg
            border.color: Theme.border
            border.width: 1
            radius: Theme.radiusLg
        }

        ViewAccounts {
            anchors.fill: parent
            onCloseRequested: acctDialog.close()
        }
    }

    // 新增/编辑型号。原先这里只是一句"由管理员维护 profiles/*.json"的指路 ——
    // 而那个文件从来没做，加型号只能改 QML 重新构建。现在真能加了（落 profiles.json）。
    Dialog {
        id: addDialog

        // null = 新增；否则改这一条
        property var editing: null
        readonly property bool isNew: editing === null
        // 勾选中的测试项位。用对象当集合，QML 里没有 Set 的稳定支持。
        property var pickedItems: ({})

        function openFor(p) {
            editing = p;
            nameF.text = p ? p.name : "";
            descF.text = p ? p.desc : "";
            pidF.text = p ? p.productId : "";
            enabledBox.checked = p ? p.enabled === true : true;
            rtspBox.checked = p ? p.focusRtsp === true : false;
            const picked = {};
            const src = p ? p.items : [0, 2, 4, 5, 6, 7, 8, 9, 10];  // 新增默认给现有型号那套
            for (let i = 0; i < src.length; ++i)
                picked[src[i]] = true;
            pickedItems = picked;
            addHint.text = "";
            open();
        }

        function submit() {
            const items = [];
            const all = ProfileStore.allItems();
            for (let i = 0; i < all.length; ++i) {
                if (addDialog.pickedItems[all[i].bit])
                    items.push(all[i].bit);
            }
            const err = ProfileStore.upsert({
                name: nameF.text.trim(),
                desc: descF.text.trim(),
                productId: pidF.text.trim(),
                enabled: enabledBox.checked,
                focusRtsp: rtspBox.checked,
                items: items,
                // 工位序列沿用默认（现有两个型号完全一致）。要按型号改工位顺序是
                // 另一件事，界面上先不开 —— 开了就得处理"工位 key 必须是已实现的
                // 那几个"这类校验，不值得在这一版做。
                stations: addDialog.isNew ? ProfileStore.defaultStations()
                                          : addDialog.editing.stations
            });
            if (err.length > 0) {
                addHint.text = err;
                return;
            }
            addDialog.close();
        }

        title: isNew ? "新增产品型号" : "编辑型号"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 520
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: Theme.radiusLg
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.s3

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: Theme.s3
                rowSpacing: Theme.s2

                Text {
                    text: "型号名"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                }
                TextField {
                    id: nameF
                    Layout.fillWidth: true
                    // 型号名是身份键，也是 SN 的型号段 —— 改名等于换一条 profile
                    enabled: addDialog.isNew
                    placeholderText: "如 CS7GV1.0（也是 SN 的型号段）"
                    font.family: "Consolas"
                    font.pointSize: TypeScale.body
                }

                Text {
                    text: "说明"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                }
                TextField {
                    id: descF
                    Layout.fillWidth: true
                    placeholderText: "如 低功耗电池 IPC · 带网口"
                    font.pointSize: TypeScale.body
                }

                Text {
                    text: "ProductId"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                }
                TextField {
                    id: pidF
                    Layout.fillWidth: true
                    placeholderText: "腾讯云 IoT Explorer 的 ProductId"
                    font.family: "Consolas"
                    font.pointSize: TypeScale.body
                }
            }

            Text {
                Layout.fillWidth: true
                text: "ProductId 决定设备名单、产测指令与云拉流都指向哪个产品 —— 填错会"
                      + "整条链路不通。现有两个型号暂时共用同一个（CS6G 正式 id 未到）。"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.s4

                CheckBox {
                    id: enabledBox
                    text: "可选（取消则卡片置灰）"
                }
                CheckBox {
                    id: rtspBox
                    text: "调焦可走 RTSP（有网口）"
                }
            }

            Text {
                Layout.fillWidth: true
                text: "本型号支持的外设测试项"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }

            Flow {
                Layout.fillWidth: true
                spacing: Theme.s3

                Repeater {
                    model: ProfileStore.allItems()

                    CheckBox {
                        required property var modelData
                        text: modelData.label
                        checked: addDialog.pickedItems[modelData.bit] === true
                        onToggled: {
                            // 改对象要整体重赋值，QML 不会侦测到深层属性变化
                            const next = {};
                            for (const k in addDialog.pickedItems)
                                next[k] = addDialog.pickedItems[k];
                            if (checked)
                                next[modelData.bit] = true;
                            else
                                delete next[modelData.bit];
                            addDialog.pickedItems = next;
                        }
                    }
                }
            }

            Text {
                id: addHint
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.fail
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.s2
                spacing: Theme.s3

                AppButton {
                    visible: !addDialog.isNew && ProfileStore.profiles.length > 1
                    text: "删除型号"
                    kind: "danger"
                    Layout.preferredWidth: 116
                    onClicked: {
                        const err = ProfileStore.remove(addDialog.editing.name);
                        if (err.length > 0)
                            addHint.text = err;
                        else
                            addDialog.close();
                    }
                }
                Item { Layout.fillWidth: true }
                AppButton {
                    text: "取消"
                    Layout.preferredWidth: 96
                    onClicked: addDialog.close()
                }
                AppButton {
                    text: addDialog.isNew ? "添加" : "保存"
                    glyph: Icons.save
                    kind: "primary"
                    Layout.preferredWidth: 116
                    onClicked: addDialog.submit()
                }
            }
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
