pragma Singleton
import QtQuick
import ptest

// 纯假数据。demo 只看 UI,不接任何真实协议。
// 字段名与真实物模型一致(ProductTestInfo / ProductTestResult),方便日后换真数据。
QtObject {
    id: root

    // ---- 产品 profiles(规则2:真实实现 = 安装目录 profiles/*.json,
    //      随软件发布/管理员维护,普通工人不可编辑) ----
    // items = 本产品固定测试项(bit 序号);enabled:false = 待建模,启动门置灰(规则6)
    // stations = 本产品的工位序列(规则:工位由产品决定,不同产品工位不同)。
    // 每项 key 决定导航标题与页面路由;pending:true = 该工位页面尚未实现,
    // 进入后显示占位页(工位存在于工艺路线里,只是软件还没做,不该假装没有)。
    // 已实现的 key: focus/semi/finished/inspect/repair(+about 由 NavRail 恒定追加)
    readonly property var profiles: [
        { name: "CS7GV1.0", desc: "低功耗电池 IPC", productId: "5KHBENFCX2",
          // CS7G 实际外设 9 项(2026-08-15 确认):无红外灯(1)、无日夜切换(3)
          //   —— 全彩夜视产品用白光补光,既没有 IR 灯也没有 IR-CUT 滤光片。
          enabled: true,  items: [0, 2, 4, 5, 6, 7, 8, 9, 10],
          stations: [
              { key: "focus",    title: "调焦",   sub: "工位 1" },
              { key: "semi",     title: "准成品", sub: "工位 2" },
              { key: "finished", title: "成品",   sub: "工位 2" },
              { key: "inspect",  title: "检查",   sub: "工位 3" },
              { key: "repair",   title: "维修",   sub: "按需"   }
          ] },
        // 示例:多产品工位差异。射频类产品在成品之前多三个工位,
        // 且不做调焦(无镜头对焦环节)。用于验证"切产品换工位"的正确性。
        { name: "CS8GV1.0", desc: "4G 摄像机(射频线)", productId: "8KH2RFDEMO",
          // 示例值:该产品有红外灯与日夜切换(常规夜视),无云台
          enabled: true,  items: [0, 1, 2, 3, 4, 5, 7, 8, 9, 10],
          stations: [
              { key: "flow",     title: "流量",   sub: "工位 1", pending: true },
              { key: "rf",       title: "射频",   sub: "工位 2", pending: true },
              { key: "coupling", title: "耦合",   sub: "工位 3", pending: true },
              { key: "semi",     title: "准成品", sub: "工位 4" },
              { key: "finished", title: "成品",   sub: "工位 4" },
              { key: "inspect",  title: "检查",   sub: "工位 5" },
              { key: "repair",   title: "维修",   sub: "按需"   }
          ] },
        { name: "CS6GV2.0", desc: "低功耗电池 IPC", productId: "",
          enabled: false, items: [], stations: [] }
    ]

    // 设备上报的 ProductId(准入校验用,规则5)。
    // mock 里让"设备"跟随当前会话产品 —— 否则切到 CS8GV1.0 演示时会立刻判型号
    // 不符、全部工位页禁用，看不到工位差异。准入比较的代码路径仍然存在
    // (Main.qml mismatch)，真实实现里这个值来自设备上报，不会跟随会话。
    readonly property string deviceProductId:
        Session.profile && Session.profile.productId ? Session.profile.productId
                                                     : "5KHBENFCX2"

    // 兼容字段(检查页 ProductKey 展示用 = 设备上报值)
    readonly property string productId:   "5KHBENFCX2"

    // ---- ProductTestInfo 假值 ----
    // SN = 型号前缀 + 流水号。分隔符只做"显示分组",不进数据 —— 见 snModel/snSerial。
    // 型号前缀跟随会话产品:真实 SN 的型号段本就来自被测机型,写死会让工人
    // 在切到别的产品后看到不匹配的 SN、以为扫错了机器。
    readonly property string snModel:
        Session.profile ? Session.profile.name : "CS7GV1.0"
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
    // ⚠️ 运行时值,禁止硬编码(规则4)。
    // 真机当前=0x6A5:指示灯(0)/白光(2)/电池(5)/喇叭(7)/4G(9)/SD(10) 六项已接线。
    // 无 bit1(红外)与 bit3(日夜) —— 本产品无此硬件。
    // "profile 要求而设备未上报→标红缺能力"这条路径不用造假来演示:
    // 复位按键(4,待 MCU)/云台(6,待电机)/咪头(8,待分贝采集) 天然就是差集。
    readonly property int supportedItems: 0x6A5

    // 四阶段完成时间戳(空串 = 未完成)
    readonly property string focusTime:   "20260815094512380"
    readonly property string semiTime:    "20260815101233907"
    readonly property string finishTime:  "20260815103501120"
    readonly property string inspectTime: ""

    // ---- 操作者账户(mock,明文仅演示;真实=SQLite+PBKDF2 加盐哈希,docs/plan P5) ----
    // 工号是字符串(前导零);超级用户唯一内置。
    readonly property var users: [
        { id: "0045009", name: "马顺涛",     role: "super",    pwd: "1234" },
        { id: "0038165", name: "肖洁",       role: "engineer", pwd: "1234" },
        { id: "9000001", name: "示例技术员", role: "tech",     pwd: "1234" }
    ]

    // ---- 负责人(关于页) ----
    // 假数据。真实工号要从产线台账拿。
    // ⚠️ 工号 0038165 必须是字符串。前导零一旦被当数字处理就会丢成 38165，
    //    将来若导出到 Excel/CSV 也是同一个坑(Excel 默认按数字解析、吃掉前导零)。
    readonly property var owners: [
        { name: "肖洁", wecom: "0038165" }
    ]

    function itemByBit(bit) {
        for (var i = 0; i < items.length; i++)
            if (items[i].item === bit) return items[i];
        return null;
    }

    // ---- 11 项测试项主表(设备侧全集;实际渲染 = profile ∩ SupportedItems 决定) ----
    // state: 0 待测 1 执行中 2 通过 3 失败 4 设备不支持 5 profile要求但设备缺(标红)
    readonly property var items: [
        // CS7G 外设 9 项。**不含红外灯(1)与日夜切换(3)** —— 本产品是全彩夜视,
        // 用白光补光,没有 IR 灯也没有 IR-CUT。物模型枚举保留那两位供其他产品用。
        { item: 0,  name: "指示灯",    detail: "红蓝双色 + 闪烁",     state: 2, reading: "ok" },
        { item: 2,  name: "白光灯",    detail: "开关 / 亮度 100",     state: 2, reading: "ok" },
        { item: 4,  name: "复位按键",  detail: "等待按键 10s",         state: 5, reading: "" },
        { item: 5,  name: "电池",      detail: "电量 + 低电标志",      state: 2, reading: "percent=87, external=1, low=0" },
        { item: 6,  name: "云台",      detail: "四向转动 + 回中",      state: 5, reading: "" },
        { item: 7,  name: "喇叭",      detail: "放音 ptest_speaker.aac", state: 1, reading: "" },
        { item: 8,  name: "咪头",      detail: "采集音频返回分贝",     state: 0, reading: "" },
        { item: 9,  name: "4G 信号",   detail: "双槽 / 运营商 / 拨号",  state: 0, reading: "" },
        { item: 10, name: "SD 卡",     detail: "在位 + 读写校验",      state: 2,
          reading: "size_mb=1, write=8.5MB/s, read=17.2MB/s, verify=ok" }
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
