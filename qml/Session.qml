pragma Singleton
import QtQuick

// 会话上下文。启动门选定产品后锁定,null = 仍在启动门。
//
// 切换产品 = 置回 null → Main 里挂主界面的 Loader 随之卸载,设备连接、
// 指令流水、各页状态整棵销毁 —— "切产品即换会话"靠对象生命周期保证,
// 不靠逐个清理(会漏)。
//
// 真实实现:选定时一并锁定 云端凭证、工装卡校验基准、测试项集合;
// profile 来自安装目录 profiles/*.json(管理员随软件发布维护)。
QtObject {
    // 产品会话(启动门写入;null=在产品门)
    property var profile: null

    // 操作者(登录门写入;null=未登录)。切换用户只清 user 不清 profile ——
    // 换班不清产品会话与设备连接(老产测惯例)。
    property var user: null

    readonly property bool isSuper:    user !== null && user.role === "super"
    readonly property bool isEngineer: user !== null && user.role === "engineer"
    readonly property bool isTech:     user !== null && user.role === "tech"

    // 权限矩阵(docs/plan §1 为权威表)。UI 惯例:无权限控件对技术员直接隐藏。
    readonly property bool canSkipItem:        user !== null && user.role !== "tech"
    readonly property bool canExport:          canSkipItem
    readonly property bool canDebugPanel:      canSkipItem
    readonly property bool canManageTech:      canSkipItem
    readonly property bool canManageEngineer:  isSuper
    readonly property bool canEditProfile:     isSuper
    readonly property bool canEditCredentials: isSuper

    function roleLabel() {
        if (isSuper) return "超级用户";
        if (isEngineer) return "工程师";
        if (isTech) return "技术员";
        return "";
    }
}
