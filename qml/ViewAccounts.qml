import QtQuick
import ptest
import QtQuick.Controls
import QtQuick.Layouts

// 账号管理（非工位页）。管的是**授权**，不是密码 —— 密码在腾达安防云那边。
//
// 所以这页只做三件事：把某个手机号加进授权表、改他的姓名/角色、把他移出去。
// 工人自己的密码、忘记密码、改密码都由腾达安防 App 处理，本软件碰不到也不该碰。
//
// 权限分层沿用 Session 现有的位，不新增概念：
//   超级用户（canManageEngineer）→ 能管所有人
//   工程师（canManageTech）      → 只能管技术员
//   技术员                       → 看不到这一页（NavRail 已挡）
Item {
    id: root

    // 装在 ProductGate 的对话框里，需要一个关闭出口
    signal closeRequested()

    // 当前登录者能授予的角色。工程师不能造出工程师/超级用户 —— 否则等于自己提权。
    readonly property var grantableRoles: Session.canManageEngineer
        ? [{ key: "super", label: "超级用户" },
           { key: "engineer", label: "工程师" },
           { key: "tech", label: "技术员" }]
        : [{ key: "tech", label: "技术员" }]

    function roleLabel(key) {
        if (key === "super") return "超级用户";
        if (key === "engineer") return "工程师";
        if (key === "tech") return "技术员";
        return key;
    }

    // 能不能动这条记录：工程师只能动技术员
    function canEdit(role) {
        return Session.canManageEngineer || role === "tech";
    }

    Toast { id: toast }
    ConfirmDialog { id: confirm }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Theme.s5
        spacing: Theme.s4

        // ── 说明卡：把"密码不在这里"讲清楚 ──────────────────────────────
        // 不写这一条，管理员一定会来问"怎么给工人设密码/改密码"。
        Card {
            title: "账号授权  ·  身份由腾达安防云验证，本表只管角色"
            titleIcon: Icons.person
            Layout.fillWidth: true
            fitContent: true

            ColumnLayout {
                anchors { left: parent.left; right: parent.right; top: parent.top }
                spacing: Theme.s2

                Text {
                    Layout.fillWidth: true
                    text: "工人用自己的腾达安防云账号（手机号 + 密码）登录本软件。"
                          + "本表只决定「这个手机号在本软件里是什么角色」，"
                          + "**不保存任何密码**。"
                    color: Theme.textSecondary
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.body
                    wrapMode: Text.WordWrap
                    textFormat: Text.MarkdownText
                }
                Text {
                    Layout.fillWidth: true
                    text: "· 新人先用「腾达安防」手机 App 注册，再把手机号加到下面\n"
                          + "· 忘记密码 / 改密码：都在腾达安防 App 里操作，与本软件无关\n"
                          + "· 员工离职：腾达云停用其账号即全产线失效；本表移出只影响本机"
                    color: Theme.textDim
                    font.family: TypeScale.family
                    font.pointSize: TypeScale.caption
                    wrapMode: Text.WordWrap
                }
            }
        }

        // ── 列表 ────────────────────────────────────────────────────────
        Card {
            title: "已授权账号  ·  共 " + AccountStore.accounts.length + " 人"
            titleIcon: Icons.device
            Layout.fillWidth: true
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                // 表头。用与行一致的列宽比例，不用固定像素 —— 窗口能拉伸。
                RowLayout {
                    Layout.fillWidth: true
                    Layout.bottomMargin: Theme.s2
                    spacing: Theme.s3

                    Text {
                        Layout.preferredWidth: 160
                        text: "手机号"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        font.weight: TypeScale.weightMedium
                    }
                    Text {
                        Layout.fillWidth: true
                        text: "姓名"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        font.weight: TypeScale.weightMedium
                    }
                    Text {
                        Layout.preferredWidth: 110
                        text: "角色"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.caption
                        font.weight: TypeScale.weightMedium
                    }
                    Item { Layout.preferredWidth: 190 }   // 操作列占位
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Theme.border
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    model: AccountStore.accounts
                    ScrollBar.vertical: ScrollBar {}

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index

                        readonly property bool editable: root.canEdit(modelData.role)

                        width: list.width
                        height: 54
                        color: rowHover.hovered ? Theme.surfaceAlt : "transparent"
                        Behavior on color { ColorAnimation { duration: Theme.durFast } }

                        HoverHandler { id: rowHover }

                        Rectangle {   // 行分隔线
                            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                            height: 1
                            color: Theme.borderSoft
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.rightMargin: Theme.s2
                            spacing: Theme.s3

                            Text {
                                Layout.preferredWidth: 160
                                text: row.modelData.phoneMask
                                color: Theme.textPrimary
                                font.family: "Consolas"
                                font.pointSize: TypeScale.body
                            }
                            Text {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                color: Theme.textPrimary
                                font.family: TypeScale.family
                                font.pointSize: TypeScale.body
                                elide: Text.ElideRight
                            }

                            // 角色徽标：颜色分层，一眼看出谁权限大
                            Rectangle {
                                Layout.preferredWidth: 110
                                implicitHeight: 24
                                radius: 12
                                color: row.modelData.role === "super"
                                       ? Qt.rgba(0.937, 0.573, 0.267, 0.18)
                                       : row.modelData.role === "engineer"
                                         ? Qt.rgba(0.267, 0.6, 0.937, 0.18)
                                         : Qt.rgba(1, 1, 1, 0.07)
                                border.width: 1
                                border.color: row.modelData.role === "super"
                                              ? Theme.brand
                                              : row.modelData.role === "engineer"
                                                ? Theme.accent : Theme.border

                                Text {
                                    anchors.centerIn: parent
                                    text: root.roleLabel(row.modelData.role)
                                    color: Theme.textPrimary
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                    font.weight: TypeScale.weightMedium
                                }
                            }

                            // 操作。不可动的行（工程师看超级用户/工程师）显示原因，
                            // 而不是给个灰按钮让人猜为什么点不动。
                            RowLayout {
                                Layout.preferredWidth: 190
                                spacing: Theme.s2

                                Text {
                                    visible: !row.editable
                                    Layout.fillWidth: true
                                    text: "需超级用户"
                                    color: Theme.textDim
                                    font.family: TypeScale.family
                                    font.pointSize: TypeScale.caption
                                    horizontalAlignment: Text.AlignRight
                                }
                                AppButton {
                                    visible: row.editable
                                    text: "编辑"
                                    implicitHeight: 30
                                    implicitWidth: 76
                                    onClicked: editDialog.openFor(row.modelData)
                                }
                                AppButton {
                                    visible: row.editable
                                    text: "移出"
                                    kind: "danger"
                                    implicitHeight: 30
                                    implicitWidth: 76
                                    onClicked: confirm.ask(
                                        "移出该账号？",
                                        row.modelData.name + "（" + row.modelData.phoneMask
                                        + "）将无法再登录本软件。腾达云账号本身不受影响，"
                                        + "重新加回来即可恢复。",
                                        function () {
                                            const err = AccountStore.remove(
                                                row.modelData.phoneMask);
                                            if (err.length > 0)
                                                toast.show(err, false);
                                            else
                                                toast.show("已移出 " + row.modelData.name, true);
                                        })
                                }
                            }
                        }
                    }

                    // 空列表不该是一片空白 —— 那看着像坏了
                    Text {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: "还没有授权账号"
                        color: Theme.textDim
                        font.family: TypeScale.family
                        font.pointSize: TypeScale.body
                    }
                }
            }
        }

        // ── 底部动作条 ──────────────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.s3

            AppButton {
                text: "添加账号"
                glyph: Icons.add
                kind: "primary"
                Layout.preferredWidth: 158
                onClicked: editDialog.openFor(null)
            }

            Text {
                Layout.fillWidth: true
                text: Session.canManageEngineer
                      ? "你是超级用户，可授予任意角色"
                      : "你是工程师，只能添加/管理技术员（造不出工程师或超级用户）"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }

            AppButton {
                text: "关闭"
                Layout.preferredWidth: 96
                onClicked: root.closeRequested()
            }
        }
    }

    // ── 新增/编辑对话框 ─────────────────────────────────────────────────
    Dialog {
        id: editDialog

        // null = 新增；否则改这一条
        property var editing: null
        readonly property bool isNew: editing === null

        // 勾选中的型号名。空对象 = 全部型号（默认）
        property var pickedModels: ({})

        function openFor(item) {
            editing = item;
            phoneField.text = item ? item.phoneMask : "";
            nameField.text = item ? item.name : "";
            // 编辑时预选原角色；新增默认给最低权限（技术员），不默认给大权限
            let idx = 0;
            for (let i = 0; i < root.grantableRoles.length; ++i) {
                if (item && root.grantableRoles[i].key === item.role) { idx = i; break; }
                if (!item && root.grantableRoles[i].key === "tech") { idx = i; break; }
            }
            roleBox.currentIndex = idx;
            // 回填型号范围（accounts() 里带 products；空 = 全部）
            const picked = {};
            if (item && item.products !== undefined) {
                for (let i = 0; i < item.products.length; ++i)
                    picked[item.products[i]] = true;
            }
            pickedModels = picked;
            hint.text = "";
            open();
        }

        // 当前是否"全部型号"（没勾任何一个 = 全部）
        readonly property bool allModels: {
            for (const k in pickedModels) return false;
            return true;
        }

        title: isNew ? "添加账号" : "编辑账号"
        modal: true
        anchors.centerIn: Overlay.overlay
        width: 460
        // ⚠️ 不用 standardButtons：那个 Ok 会**先关闭对话框再触发 onAccepted**，
        //    校验失败时工人填的内容全丢、要重填一遍。自己摆按钮，校验通过才 close()。
        closePolicy: Popup.CloseOnEscape

        background: Rectangle {
            color: Theme.surface
            border.color: Theme.border
            border.width: 1
            radius: Theme.radiusLg
        }

        // 校验 + 保存。失败时把原因显示在对话框里（不是 toast —— 错误就该出现在
        // 出错的那个表单上），对话框保持打开，内容不丢。
        function submit() {
            const phone = phoneField.text.trim();
            const name = nameField.text.trim();
            if (editDialog.isNew) {
                // 只在新增时校手机号格式：编辑时这个框是掩码且禁用的
                if (!/^\d{11}$/.test(phone)) {
                    hint.text = "请输入 11 位手机号";
                    return;
                }
            }
            if (name.length === 0) {
                hint.text = "请填写姓名";
                return;
            }
            const role = root.grantableRoles[roleBox.currentIndex].key;
            // 新增按手机号（会算哈希）；编辑按掩码（哈希不可逆，只能这么定位）——
            // 两条路不能混用，见 AccountStore::updateByMask 的说明
            const err = editDialog.isNew
                ? AccountStore.upsert(phone, name, role)
                : AccountStore.updateByMask(editDialog.editing.phoneMask, name, role);
            if (err.length > 0) {
                hint.text = err;
                return;
            }

            // 型号范围（只对技术员有意义；工程师/超级用户在 allowsProduct 里恒放行）。
            // 新增时掩码要现算 —— upsert 存的是哈希，界面这边只有原号。
            const models = [];
            for (const k in editDialog.pickedModels)
                models.push(k);
            const mask = editDialog.isNew ? AccountStore.maskPhone(phone)
                                          : editDialog.editing.phoneMask;
            const err2 = AccountStore.setProducts(mask, models);
            if (err2.length > 0) {
                hint.text = err2;
                return;
            }

            toast.show(editDialog.isNew ? "已添加 " + name : "已更新 " + name, true);
            editDialog.close();
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: Theme.s3

            Text {
                Layout.fillWidth: true
                text: "手机号"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }
            TextField {
                id: phoneField
                Layout.fillWidth: true
                // ⚠️ 编辑已有账号时这里是**掩码**（138****8000）——手机号存的是哈希，
                //    原号取不回来。所以编辑时禁掉：要改号只能移出再重新添加。
                enabled: editDialog.isNew
                placeholderText: "11 位手机号（腾达安防云账号）"
                inputMethodHints: Qt.ImhDigitsOnly
                font.family: "Consolas"
                font.pointSize: TypeScale.body
            }
            Text {
                visible: !editDialog.isNew
                Layout.fillWidth: true
                text: "手机号不可改（表里只存哈希，原号取不回来）。要换号请移出后重新添加。"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: "姓名"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }
            TextField {
                id: nameField
                Layout.fillWidth: true
                placeholderText: "显示在顶栏与产测记录里"
                font.pointSize: TypeScale.body
            }

            Text {
                Layout.fillWidth: true
                text: "角色"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }
            ComboBox {
                id: roleBox
                Layout.fillWidth: true
                model: root.grantableRoles
                textRole: "label"
                font.pointSize: TypeScale.body
            }

            // ── 型号范围：只对技术员显示 ──────────────────────────────────
            // 工程师/超级用户不受限（allowsProduct 恒放行），摆出来只会造成
            // "勾了却不生效"的困惑。
            Text {
                visible: modelScope.visible
                Layout.fillWidth: true
                text: "可操作的型号（一个不勾 = 全部型号）"
                color: Theme.textDim
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
            }
            Flow {
                id: modelScope
                visible: root.grantableRoles[roleBox.currentIndex] !== undefined
                         && root.grantableRoles[roleBox.currentIndex].key === "tech"
                Layout.fillWidth: true
                spacing: Theme.s3

                Repeater {
                    model: ProfileStore.profiles

                    CheckBox {
                        required property var modelData
                        text: modelData.name
                        checked: editDialog.pickedModels[modelData.name] === true
                        onToggled: {
                            // 改对象要整体重赋值，QML 侦测不到深层属性变化
                            const next = {};
                            for (const k in editDialog.pickedModels)
                                next[k] = editDialog.pickedModels[k];
                            if (checked)
                                next[modelData.name] = true;
                            else
                                delete next[modelData.name];
                            editDialog.pickedModels = next;
                        }
                    }
                }
            }
            Text {
                visible: modelScope.visible
                Layout.fillWidth: true
                text: editDialog.allModels
                      ? "当前：全部型号（含以后新增的）"
                      : "当前：仅勾选的型号 —— 该技术员的产品选择页只会出现这些"
                color: Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            Text {
                Layout.fillWidth: true
                text: {
                    const k = root.grantableRoles[roleBox.currentIndex]
                              ? root.grantableRoles[roleBox.currentIndex].key : "tech";
                    // 三层权限的准确口径（对应 Session 里的位）：
                    //   canEditProfile = isSuper      改产品要测哪些项
                    //   canSkipItem    = 非技术员      某项测出 fail 时放行
                    //   无限制                         执行产测流程
                    if (k === "super")
                        return "全部权限：可勾选产品的测试项、可放行失败项、"
                               + "可导出批次、可用云调试页、可管理所有账号。";
                    if (k === "engineer")
                        return "可放行测试失败的项、导出批次、用云调试页、管理技术员。"
                               + "不能勾选产品的测试项（那只有超级用户能改）。";
                    return "只能执行产测流程。某项测不过时只能重测或转维修，"
                           + "不能放行；看不到云调试页与本页。";
                }
                color: Theme.textSecondary
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            Text {
                id: hint
                Layout.fillWidth: true
                visible: text.length > 0
                color: Theme.fail
                font.family: TypeScale.family
                font.pointSize: TypeScale.caption
                wrapMode: Text.WordWrap
            }

            // 自己摆按钮（不用 standardButtons，理由见上面 closePolicy 处的说明）
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: Theme.s2
                spacing: Theme.s3

                Item { Layout.fillWidth: true }
                AppButton {
                    text: "取消"
                    Layout.preferredWidth: 96
                    onClicked: editDialog.close()
                }
                AppButton {
                    text: editDialog.isNew ? "添加" : "保存"
                    glyph: Icons.save
                    kind: "primary"
                    Layout.preferredWidth: 116
                    onClicked: editDialog.submit()
                }
            }
        }
    }
}
