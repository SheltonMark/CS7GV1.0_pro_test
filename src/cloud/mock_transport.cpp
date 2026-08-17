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
    // SupportedItems=2037：CS7G 支持 9 项外设（无红外灯 bit1、无日夜切换 bit3），
    // 0x7FF - 0x002 - 0x008 = 0x7F5 = 2037，与设备端能力注册表一致。
    info_ = QJsonObject{
        {QStringLiteral("Active"), 1},
        {QStringLiteral("Stage"), 0},
        {QStringLiteral("FocusTime"), QString()},
        {QStringLiteral("SemiTime"), QString()},
        {QStringLiteral("FinishTime"), QString()},
        {QStringLiteral("InspectTime"), QString()},
        {QStringLiteral("SupportedItems"), 2037},
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
            // 心跳:假设备永远新鲜(真机=固件周期上报,LastUpdate 由云端盖章)
            {QStringLiteral("PtestHeartbeat"),
             QJsonObject{{QStringLiteral("Value"), 1},
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
}

QString MockTransport::nowStamp17()
{
    // 17 位 YYYYMMDDHHMMSSmmm，与物模型约定一致
    return QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMddHHmmsszzz"));
}
