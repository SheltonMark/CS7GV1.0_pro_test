pragma Singleton
import QtQuick
import ptest

// 纯假数据。demo 只看 UI,不接任何真实协议。
// 字段名与真实物模型一致(ProductTestInfo / ProductTestResult),方便日后换真数据。
QtObject {
    id: root

    // ---- 当前产品 profile(多产品:一份配置一款产品) ----
    readonly property string productName: "CS7GV1.0"
    readonly property string productDesc: "低功耗电池 IPC"
    readonly property string productId:   "5KHBENFCX2"

    // ---- ProductTestInfo 假值 ----
    // SN = 型号前缀 + 流水号。分隔符只做"显示分组",不进数据 —— 见 snModel/snSerial。
    readonly property string snModel:  "CS7GV1.0"
    readonly property string snSerial: "2608150042"
    readonly property string sn:       snModel + snSerial
    readonly property string deviceName: "1000000003"
    readonly property string imei:       "867726051234567"
    readonly property string uuid:       "b7e4f2a1-9c3d-4e8f-a012-3456789abcde"
    readonly property string mac:        "C8:3A:35:1F:2B:9C"
    readonly property string swVersion:  "V1.0.0.14"
    readonly property string hwVersion:  "A2"
    readonly property string secretCrc32:"7F3A9B2E"
    readonly property string suid:       "SU2608A1B2C3D4E5"
    readonly property string language:   "CN"
    // 本地按评审表 §2.6 算得(zlib CRC32(DeviceSecret+ProductSecret),8位大写hex)。
    // 真实实现由 C++ 用下发时的明文算;mock 直接给相同值 = 校验通过。
    readonly property string localSecretCrc32: "7F3A9B2E"
    readonly property int supportedItems: 0x6A7   // 首版位图:七项可测

    // 四阶段完成时间戳(空串 = 未完成)
    readonly property string focusTime:   "20260815094512380"
    readonly property string semiTime:    "20260815101233907"
    readonly property string finishTime:  "20260815103501120"
    readonly property string inspectTime: ""

    // ---- 负责人(关于页) ----
    // 假数据。真实工号要从产线台账拿。
    // ⚠️ 工号 0038165 必须是字符串。前导零一旦被当数字处理就会丢成 38165，
    //    将来若导出到 Excel/CSV 也是同一个坑(Excel 默认按数字解析、吃掉前导零)。
    readonly property var owners: [
        { name: "肖洁", wecom: "0038165" }
    ]

    // ---- 11 项测试项主表 ----
    // state: 0 待测 1 执行中 2 通过 3 失败 4 设备不支持 5 profile要求但设备缺(标红)
    readonly property var items: [
        { item: 0,  name: "指示灯",    detail: "红蓝双色 + 闪烁",     state: 2, reading: "ok" },
        { item: 1,  name: "红外灯",    detail: "开关 / 亮度 100",     state: 2, reading: "ok" },
        { item: 2,  name: "白光灯",    detail: "开关 / 亮度 100",     state: 2, reading: "ok" },
        { item: 3,  name: "日夜切换",  detail: "本产品不启用",         state: 4, reading: "" },
        { item: 4,  name: "复位按键",  detail: "待 MCU 链路",          state: 5, reading: "" },
        { item: 5,  name: "电池",      detail: "电量查询",             state: 2, reading: "percent=87, external=1" },
        { item: 6,  name: "云台",      detail: "待装电机",             state: 4, reading: "" },
        { item: 7,  name: "喇叭",      detail: "放音 ptest_speaker.aac", state: 1, reading: "" },
        { item: 8,  name: "咪头",      detail: "拉流人工判定",         state: 0, reading: "" },
        { item: 9,  name: "4G 信号",   detail: "RSRP / SINR",          state: 0, reading: "" },
        { item: 10, name: "SD 卡",     detail: "在位与状态",           state: 3, reading: "state=absent" }
    ]

    // ---- 工位步骤(线性流程,一次只让工人面对一步) ----
    readonly property var finishedSteps: [
        { name: "设备上云建连",   state: 2 },
        { name: "时间同步",       state: 2 },
        { name: "读产测信息",     state: 2 },
        { name: "拉流图像检查",   state: 2 },
        { name: "外设逐项测试",   state: 1 },
        { name: "写 InputData",   state: 0 },
        { name: "写成品标识",     state: 0 },
        { name: "采集信息入库",   state: 0 },
        { name: "恢复默认",       state: 0 },
        { name: "定时重启",       state: 0 }
    ]

    // ---- 指令流水(RequestId 关联) ----
    readonly property var log: [
        { rid: 1041, cmd: "PtestPeripheralTest",  item: "喇叭",    code: -1, detail: "等待设备回报…" },
        { rid: 1040, cmd: "PtestPeripheralTest",  item: "SD卡",    code: 3,  detail: "state=absent" },
        { rid: 1039, cmd: "PtestPeripheralTest",  item: "电池",    code: 0,  detail: "percent=87,external=1" },
        { rid: 1038, cmd: "PtestPeripheralTest",  item: "白光灯",  code: 0,  detail: "ok" },
        { rid: 1037, cmd: "PtestWriteStage",      item: "准成品",  code: 0,  detail: "ok" },
        { rid: 1036, cmd: "SetDeviceTime",        item: "—",       code: 0,  detail: "accepted" }
    ]

}
