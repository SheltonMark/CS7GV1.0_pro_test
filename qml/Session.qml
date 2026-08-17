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

    // ---- 批次(InputData1)会话存储:批次文件页导入,成品工位消费 ----
    // records: 每台一行(12 列字符串数组,列序见批次文件页 headers);
    // used:    0/1 入库标记 —— 成品校验通过置 1,防同一条身份写进两台设备;
    // imei:    采集到的 IMEI(""=未测或校验失败留空白),导出 InputData2 时为末列。
    // 只在内存:重开软件需重新导入;对账以导出的 InputData2 为准。
    property string batchName: ""
    property var batchRecords: []
    property var batchUsed: []
    property var batchImei: []

    readonly property int batchDoneCount: {
        var n = 0;
        for (var i = 0; i < batchUsed.length; ++i) if (batchUsed[i] === 1) n++;
        return n;
    }

    // 切产品=换会话,批次一起清 —— 跨产品复用批次必然写错身份
    onProfileChanged: { batchName = ""; batchRecords = []; batchUsed = []; batchImei = []; }

    function setBatch(name, records) {
        batchName = name;
        batchRecords = records;
        var u = [], m = [];
        for (var i = 0; i < records.length; ++i) { u.push(0); m.push(""); }
        batchUsed = u;
        batchImei = m;
    }

    // MAC 归一化:去分隔符并大写 —— 工人可能带冒号输入,批次文件里是纯 hex
    function normalizeMac(mac) {
        return ("" + mac).replace(/[:\-\s]/g, "").toUpperCase();
    }

    function batchIndexOfMac(mac) {
        const norm = normalizeMac(mac);
        if (norm.length === 0) return -1;
        for (var i = 0; i < batchRecords.length; ++i)
            if (normalizeMac(batchRecords[i][0]) === norm) return i;
        return -1;
    }

    // 第一条未入库记录的 MAC —— 成品工位默认带出,入库后自动跳下一条
    function nextUnusedMac() {
        for (var i = 0; i < batchRecords.length; ++i)
            if (batchUsed[i] !== 1) return batchRecords[i][0];
        return "";
    }

    // 校验通过才调;失败的记录 IMEI 留空白且不置标记(设备转维修后该条仍可用)
    function markBatchDone(index, imei) {
        if (index < 0 || index >= batchRecords.length) return;
        var u = batchUsed.slice(); u[index] = 1; batchUsed = u;
        var m = batchImei.slice(); m[index] = imei; batchImei = m;
    }
}
