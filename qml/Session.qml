pragma Singleton
import QtQuick
// ⚠️ 必须显式 import ptest：单例的 JS 里**不能隐式引用另一个单例**。少了这行，
//    advanceStation / stationDoneCount / deviceOnlineInRoster 里对 CloudClient、
//    StationProgress、StreamLog 的引用全部抛
//      ReferenceError: CloudClient is not defined
//    —— 函数在第一次碰到它时就中断，表现为"自动跳台完全没反应"，而顶栏徽标却是对的
//    （TopBar 直接调 StationProgress.doneCount，那里 CloudClient 可见）。
//    这一对矛盾现象我追了三轮才定位，日志里那行 ReferenceError 才是真凭据。
import ptest

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

    // 某设备在名单（DescribeDevices）里是否在线。给顶栏在切设备后、心跳还没到的
    // 空档用 —— 那会儿心跳判据还是上一台的，直接显示会是错的。
    function deviceOnlineInRoster(name) {
        if (!name || name.length === 0)
            return false;
        const list = CloudClient.devices;      // 同上：下标遍历，别用 for...of
        for (let i = 0; i < list.length; ++i)
            if (list[i].deviceName === name)
                return list[i].online === true;
        return false;
    }

    // ── 自动跳下一台 ────────────────────────────────────────────────────
    // 一批 10 台同时通电，工人按卡号顺序逐台做。本工位标识写成功（回读核对通过）
    // 即认为这台做完，自动切到下一台，工人不用去点选设备。
    //
    // ⚠️ 调用时机必须是"这台在本工位彻底完事"之后，不是"标识写完"之后。准成品/
    //    成品写完标识还要走 配置清除 → 定时关机 的自动链，链上每一步都用
    //    CloudClient 对**当前设备**下发 —— 提前切走会把后续指令发到下一台去。
    //
    // 返回切过去的设备名；空串 = 没有下一台（都做完了，或剩下的都离线）。
    signal autoAdvanced(string deviceName)
    signal autoAdvanceExhausted(string reason)

    // silent=true：调用方自己会发一条更具体的提示，这里就不要再发通用的那条
    //（否则两条 toast 同时出现、内容还重复 —— 保留信息更全的那条）。
    function advanceStation(station, silent) {
        if (!station || station.length === 0)
            return "";
        const cur = CloudClient.deviceName;
        // 先把这台在本工位记成已完成 —— nextPending 要靠它跳过自己
        StationProgress.setDone(CloudClient.productId, cur, station, true);

        const next = StationProgress.nextPending(CloudClient.productId, station,
                                                 CloudClient.devices, cur);
        StreamLog.log("[进度] advanceStation station=" + station
                         + " 当前=" + cur + " 名单=" + CloudClient.devices.length
                         + " 台 → 下一台='" + next + "'");
        if (next.length === 0) {
            // 分清两种"没有下一台"：全做完 vs 剩下的都离线。产线上这两种的处置
            // 完全不同（一个是收工，一个是去检查供电/工装卡）。
            // 用 C++ 的计数，别在 JS 里重算一遍 —— 同一件事两套实现必然分叉
            const total = CloudClient.devices.length;
            const pending = total - StationProgress.doneCount(
                                CloudClient.productId, station, CloudClient.devices);
            autoAdvanceExhausted(pending > 0
                ? "还有 " + pending + " 台未测，但都不在线 —— 检查工装卡与供电"
                : "本批 " + CloudClient.devices.length + " 台在本工位已全部完成");
            return "";
        }

        CloudClient.deviceName = next;
        CloudClient.refreshInfo();   // 顺手拿设备真值校正进度，也刷新页面上的信息
        if (silent !== true)
            autoAdvanced(next);      // 这个信号只负责弹通用提示，见 Main.qml
        return next;
    }

    // 本工位已完成台数：直接转发给 C++（StationProgress::doneCount）。
    // ⚠️ 别在这里用 JS 重算一遍。原先是 JS 实现，实测顶栏徽标恒为 0 而浮层绿点
    //    却是对的 —— 同一个存储两处结论不同。计数只留一份实现，放 C++。
    function stationDoneCount(station) {
        if (!station || station.length === 0)
            return 0;
        return StationProgress.doneCount(CloudClient.productId, station,
                                        CloudClient.devices);
    }

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
