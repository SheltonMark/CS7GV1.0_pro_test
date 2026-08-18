#include "mock_transport.hpp"

#include <QDateTime>
#include <QTimer>

#include "crc32.hpp"

namespace {

// 模拟真实节奏：受理 ≠ 执行完。受理很快回，执行完才更新上报——
// 强迫上层的轮询闭环真的跑起来，而不是发完立刻就有结果。
constexpr int kAcceptDelayMs = 120;
constexpr int kExecuteDelayMs = 650;
constexpr int kReadDelayMs = 120;

} // namespace

MockTransport::MockTransport(QObject *parent)
    : QObject(parent)
{
    // SupportedItems=1765（0x6E5）：指示灯(0)/白光(2)/电池(5)/云台(6)/喇叭(7)/
    // 4G(9)/SD卡(10)。红外灯 bit1 是设备端误注册（CS7G 无此硬件）待摘，不算。
    //
    // 云台(6) 计入是刻意的（用户定稿 2026-08-18）：本产品没有电机，设备端先注册
    // 桩执行体**恒回成功**，等硬件到位再换真实执行体。所以能力位要报"支持"——
    // 否则 PC 侧按「设备缺能力」判废，整条流程卡在一个已知没有的硬件上。
    // ⚠️ 这条依赖设备端(battery_ipc)同步注册 item 6 的桩执行体，两边必须一致。
    //
    // 复位按键(4) 与 咪头(8) 不计入且无需计入：两项已定走"无指令纯人工"
    //（复位只验按键手感、不验触发的功能；咪头靠拉流听声），PC 不下发指令，
    // 也就不查这两位（见 SequentialTestPanel.startCurrent 的 noCommand 分支）。
    //
    // 此前的 2037 把 4/6/8 全置 1，恰好掩盖了 Mock 与真机的差异（核对报告断点②）。
    info_ = QJsonObject{
        {QStringLiteral("Active"), 1},
        {QStringLiteral("Stage"), 0},
        {QStringLiteral("FocusTime"), QString()},
        {QStringLiteral("SemiTime"), QString()},
        {QStringLiteral("FinishTime"), QString()},
        {QStringLiteral("InspectTime"), QString()},
        {QStringLiteral("SupportedItems"), 1765},
        {QStringLiteral("Sn"), QString()},
        {QStringLiteral("Mac"), QString()},
        {QStringLiteral("Uuid"), QString()},
        {QStringLiteral("Imei"), QStringLiteral("862000000000003")},
        {QStringLiteral("Suid"), QString()},
        {QStringLiteral("Language"), QString()},
        {QStringLiteral("ProductKey"), QString()},
        {QStringLiteral("DeviceName"), QString()},
        {QStringLiteral("SwVersion"), QStringLiteral("mock-0.1.0")},
        {QStringLiteral("HwVersion"), QStringLiteral("demo")},
        {QStringLiteral("SecretCrc32"), QString()},
    };

    // 阶段4 展示样例：一条「上云阶段失败」的最近异常（Stage=2，Code 走
    // ProductTestResult.Code 口径的通用失败 1），Ts 固定在启动前 1 小时，
    // 界面的时间格式化一眼可核。真机语义 = 最近一条非指令类失败，粘滞不清零。
    lastError_ = QJsonObject{
        {QStringLiteral("Stage"), 2},
        {QStringLiteral("Code"), 1},
        {QStringLiteral("Detail"), QStringLiteral("mqtt connect timeout, retry=3 (mock)")},
        {QStringLiteral("Ts"), QDateTime::currentSecsSinceEpoch() - 3600},
    };
    // ptest.log 尾部样例（管道分隔：时间戳|请求号|指令|测试项|结果码|详情）。
    // 起机四行打底；之后每执行一条指令 setResult 追加一行、Seq 自增——
    // 让 QML「仅 Seq 变化才刷新」的逻辑在 Mock 自测里就真的被踩到。
    logLines_ = QStringList{
        QStringLiteral("20260818090001123|0|boot|-1|0|provision ok"),
        QStringLiteral("20260818090003456|0|selfcheck|-1|0|4g ok rsrp=-95dBm"),
        QStringLiteral("20260818090007789|0|cloud|-1|1|mqtt connect timeout, retry=3"),
        QStringLiteral("20260818090011024|0|cloud|-1|0|mqtt connected"),
    };
}

void MockTransport::invokeAction(const QString & /*productId*/, const QString & /*deviceName*/,
                                 const QString &actionId, const QJsonObject &inputParams,
                                 CloudReplyHandler done)
{
    QTimer::singleShot(kAcceptDelayMs, this, [done]() {
        done(CloudReply::success(
            QJsonObject{{QStringLiteral("ClientToken"), QStringLiteral("mock-token")}}));
    });
    QTimer::singleShot(kExecuteDelayMs, this, [this, actionId, inputParams]() {
        execute(actionId, inputParams);
    });
}

void MockTransport::readDeviceData(const QString & /*productId*/, const QString & /*deviceName*/,
                                   CloudReplyHandler done)
{
    QTimer::singleShot(kReadDelayMs, this, [this, done]() {
        const qint64 nowMs = QDateTime::currentMSecsSinceEpoch();
        QJsonObject data{
            {QStringLiteral("ProductTestInfo"),
             QJsonObject{{QStringLiteral("Value"), info_},
                         {QStringLiteral("LastUpdate"), nowMs}}},
            // 心跳:假设备永远新鲜(真机=固件周期上报,LastUpdate 由云端盖章)。
            // 计数照真机自增 —— 钉死成常量的话,"计数器变化=新鲜"那条兜底
            // 证据在自测里永远走不到,真机上才第一次生效。
            {QStringLiteral("PtestHeartbeat"),
             QJsonObject{{QStringLiteral("Value"), ++heartbeat_},
                         {QStringLiteral("LastUpdate"), nowMs}}},
            // 设备信息:调焦 RTSP 直拉要用的 IP(CS7G 网口)
            {QStringLiteral("DeviceInformation"),
             QJsonObject{{QStringLiteral("Value"),
                          QJsonObject{{QStringLiteral("IpAddress"),
                                       QStringLiteral("192.168.170.66")},
                                      {QStringLiteral("SystemVersion"),
                                       QStringLiteral("mock-sys-1.0")}}},
                         {QStringLiteral("LastUpdate"), nowMs}}},
            // 阶段4 日志展示(物模型 v3)：形状与真云一致 {"Value":{...},"LastUpdate":毫秒}
            {QStringLiteral("PtestLastError"),
             QJsonObject{{QStringLiteral("Value"), lastError_},
                         {QStringLiteral("LastUpdate"), nowMs}}},
            {QStringLiteral("PtestLogTail"),
             QJsonObject{{QStringLiteral("Value"),
                          QJsonObject{{QStringLiteral("Seq"), logSeq_},
                                      {QStringLiteral("Text"),
                                       logLines_.join(QLatin1Char('\n'))}}},
                         {QStringLiteral("LastUpdate"), nowMs}}},
        };
        if (hasResult_) {
            data.insert(QStringLiteral("ProductTestResult"),
                        QJsonObject{{QStringLiteral("Value"), result_},
                                    {QStringLiteral("LastUpdate"), nowMs}});
        }
        done(CloudReply::success(data));
    });
}

void MockTransport::execute(const QString &actionId, const QJsonObject &p)
{
    const int requestId = p.value(QStringLiteral("RequestId")).toInt();

    if (actionId == QLatin1String("PtestWriteStage")) {
        const int stage = p.value(QStringLiteral("Stage")).toInt();
        if (stage < 1 || stage > 4) {
            setResult(requestId, 0, -1, 1, QStringLiteral("invalid stage"));
            return;
        }
        QString ts = p.value(QStringLiteral("Timestamp")).toString();
        if (ts.isEmpty()) ts = nowStamp17();
        static const char *kSlots[] = {nullptr, "FocusTime", "SemiTime", "FinishTime", "InspectTime"};
        info_.insert(QLatin1String(kSlots[stage]), ts);
        if (stage > info_.value(QStringLiteral("Stage")).toInt())
            info_.insert(QStringLiteral("Stage"), stage);
        setResult(requestId, 0, -1, 0, QString());

    } else if (actionId == QLatin1String("PtestClearPartition")) {
        const int scope = p.value(QStringLiteral("Scope")).toInt();
        for (const char *k : {"FocusTime", "SemiTime", "FinishTime", "InspectTime"})
            info_.insert(QLatin1String(k), QString());
        info_.insert(QStringLiteral("Stage"), 0);
        if (scope == 0) {  // 全清：标识+身份+SUID
            for (const char *k : {"Sn", "Mac", "Uuid", "Suid", "Language",
                                  "ProductKey", "DeviceName", "SecretCrc32"})
                info_.insert(QLatin1String(k), QString());
        }
        setResult(requestId, 1, -1, 0, QString());

    } else if (actionId == QLatin1String("PtestPeripheralTest")) {
        const int item = p.value(QStringLiteral("Item")).toInt();
        if (item == 1 || item == 3) {  // CS7G 无红外灯/日夜切换 → 能力集语义回 4
            setResult(requestId, 2, item, 4, QStringLiteral("not supported on CS7G"));
            return;
        }
        QString detail;
        switch (item) {
        case 5:  detail = QStringLiteral("voltage=3868mV"); break;
        // 云台：桩执行体恒回成功（本产品无电机）。detail 写明白，免得日后
        // 在指令流水里看到"云台通过"以为真转过了。
        case 6:  detail = QStringLiteral("stub: no gimbal motor, always ok"); break;
        case 9:  detail = QStringLiteral("sim0 rsrp=-92dBm"); break;
        case 10: detail = QStringLiteral("total=30436MB free=30120MB"); break;
        default: break;
        }
        setResult(requestId, 2, item, 0, detail);

    } else if (actionId == QLatin1String("PtestWriteIdentity")) {
        for (const char *k : {"Sn", "Mac", "ProductKey", "DeviceName", "Uuid", "Language"}) {
            const QString v = p.value(QLatin1String(k)).toString();
            if (!v.isEmpty()) info_.insert(QLatin1String(k), v);
        }
        // 空字段=不写 的语义与设备端一致；密钥不回明文，只回校验值。
        // 与真机同口径：b64url 解码回明文后算 CRC32（PC 侧用明文比对才能过）。
        const QString devSecret = QString::fromUtf8(QByteArray::fromBase64(
            p.value(QStringLiteral("DeviceSecret")).toString().toUtf8(),
            QByteArray::Base64UrlEncoding));
        const QString prodSecret = QString::fromUtf8(QByteArray::fromBase64(
            p.value(QStringLiteral("ProductSecret")).toString().toUtf8(),
            QByteArray::Base64UrlEncoding));
        if (!devSecret.isEmpty() || !prodSecret.isEmpty())
            info_.insert(QStringLiteral("SecretCrc32"), PtestCrc32Hex(devSecret + prodSecret));
        setResult(requestId, 3, -1, 0, QString());

    } else if (actionId == QLatin1String("PtestWriteSuid")) {
        info_.insert(QStringLiteral("Suid"), p.value(QStringLiteral("Suid")).toString());
        setResult(requestId, 4, -1, 0, QString());

    } else if (actionId == QLatin1String("PtestShutdown")) {
        const int delay = p.value(QStringLiteral("DelaySec")).toInt();
        // 真机口径：收到即回执(下发成功=完成)，delay 秒后才真关机
        setResult(requestId, 5, -1, 0,
                  QStringLiteral("shutdown in %1s").arg(delay));

    } else if (actionId == QLatin1String("SetDefaultDevConfigs")
               || actionId == QLatin1String("SetDeviceTime")) {
        // 通用 action（恢复出厂/时间同步）：非产测指令，不写 ProductTestResult
        //（与真机行为一致，PC 按"云端受理即完成"处理）。也不动加密分区字段。
        return;

    } else {
        setResult(requestId, -1, -1, 4, QStringLiteral("unknown action: ") + actionId);
    }
}

void MockTransport::setResult(int requestId, int command, int item, int code,
                              const QString &detail)
{
    result_ = QJsonObject{
        {QStringLiteral("RequestId"), requestId},
        {QStringLiteral("Command"), command},
        {QStringLiteral("Item"), item},
        {QStringLiteral("Code"), code},
        {QStringLiteral("Detail"), detail},
        {QStringLiteral("Ts"), QDateTime::currentSecsSinceEpoch()},
    };
    hasResult_ = true;

    // 日志尾部同步演进：真机每执行一条指令就往 ptest.log 追一行同格式记录。
    // 封顶 8 行 —— 真机 Text ≤2048，Mock 同样只留尾部。
    logLines_.append(QStringLiteral("%1|%2|%3|%4|%5|%6")
                         .arg(nowStamp17()).arg(requestId).arg(command)
                         .arg(item).arg(code).arg(detail));
    while (logLines_.size() > 8)
        logLines_.removeFirst();
    ++logSeq_;
}

QString MockTransport::nowStamp17()
{
    // 17 位 YYYYMMDDHHMMSSmmm，与物模型约定一致
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMddHHmmsszzz"));
}
