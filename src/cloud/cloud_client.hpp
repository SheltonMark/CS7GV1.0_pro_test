#pragma once

#include <QJsonObject>
#include <QList>
#include <QObject>
#include <QQmlEngine>
#include <QTimer>
#include <QVariantMap>

#include <memory>

#include "i_cloud_transport.hpp"

// PC 端产测指令客户端（QML 单例）。
//
// 职责：RequestId 生成 → action 下发 → 轮询 ProductTestResult 按 RequestId
// 关联 → 信号通知 QML。指令严格串行（单飞+排队）——设备端是单结果槽
// （ProductTestResult 覆盖式），并发下发必丢结果。
//
// 传输层可切换，由 exe 同目录 cloud_config.json 决定：
//   { "secretId": "...", "secretKey": "...", "region": "ap-guangzhou",
//     "productId": "5KHBENFCX2", "deviceName": "1000000003" }
// secretId/secretKey 齐全 ⇒ 腾讯云直连；否则 Mock 假设备。
// ⚠️ 密钥文件不进 git（.gitignore 已加），也绝不写日志。
//
// 产测 action 共 6 条：WriteStage / ClearPartition / PeripheralTest /
// WriteIdentity / WriteSuid / Shutdown。在线判定优先看 PtestHeartbeat 新鲜度。
class CloudClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QString mode READ mode NOTIFY modeChanged)
    Q_PROPERTY(QString productId READ productId WRITE setProductId NOTIFY deviceChanged)
    Q_PROPERTY(QString deviceName READ deviceName WRITE setDeviceName NOTIFY deviceChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    // 在线判定优先 = PtestHeartbeat.LastUpdate 新鲜；无心跳时退化为读取成功
    Q_PROPERTY(bool online READ online NOTIFY onlineChanged)
    // 最近一次读到的心跳计数 / 年龄(ms)。调试页与顶栏诊断用；-1 = 尚未读到。
    Q_PROPERTY(int heartbeatValue READ heartbeatValue NOTIFY heartbeatChanged)
    Q_PROPERTY(qint64 heartbeatAgeMs READ heartbeatAgeMs NOTIFY heartbeatChanged)

    // ── 设备名单（多台工装卡同时上线）─────────────────────────────────
    // 产线一批 10 台，每台一张 SD 工装卡；卡上的 device_name 固定、下一批复用。
    // 名单来自云端（同一 productId 下的全部设备），**不需要 PC 知道三元组** ——
    // device_secret 是设备连云用的，PC 走 CAM 密钥直接问云。
    //
    // 每项：{ card: 1, deviceName: "1000000001", online: true }
    // card = 工装卡号，按 deviceName 升序编号（1 起），与卡上贴的标签对应。
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    Q_PROPERTY(bool devicesLoading READ devicesLoading NOTIFY devicesChanged)

public:
    explicit CloudClient(QObject *parent = nullptr);

    QString mode() const;
    QString productId() const { return productId_; }
    void setProductId(const QString &value);
    QString deviceName() const { return deviceName_; }
    void setDeviceName(const QString &value);
    bool busy() const { return inFlight_; }
    bool online() const { return online_; }
    int heartbeatValue() const { return heartbeatValue_; }
    qint64 heartbeatAgeMs() const;
    QVariantList devices() const { return devices_; }
    bool devicesLoading() const { return devicesInFlight_; }

    // 刷新设备名单。productId 取当前值（= 选定产品的 ProductId），所以切产品后
    // 重新调一次就自动过滤成该产品的设备。
    Q_INVOKABLE void refreshDevices();

    // —— 6 条产测指令。返回本次 RequestId，结果经 commandFinished /
    //    commandTimeout / commandFailed 信号回来（按 RequestId 对应）。
    Q_INVOKABLE int writeStage(int stage, const QString &timestamp17);
    Q_INVOKABLE int clearPartition(int scope);
    Q_INVOKABLE int peripheralTest(int item, int operation, int param1, int param2,
                                   const QString &text);
    // fields 键名与物模型一致：Sn/Mac/ProductKey/DeviceName/DeviceSecret/
    // ProductSecret/Uuid/Language。空字段不下发（设备端语义=保持原值）。
    // 两个 Secret 传**明文**，本层负责 b64url 编码后下发（物模型硬要求）。
    Q_INVOKABLE int writeIdentity(const QVariantMap &fields);
    Q_INVOKABLE int writeSuid(const QString &suid);
    // 产测定时关机（PtestShutdown）。设备收到即回 ProductTestResult(Command=5)，
    // delaySec 后请求 MCU 关机握手；PC 以下发成功为完成，不等真断电。
    Q_INVOKABLE int shutdownDevice(int delaySec);

    // 通用 action（非产测指令，无 RequestId、不回 ProductTestResult，
    // 如 SetDefaultDevConfigs 恢复出厂、SetDeviceTime 时间同步）。不走指令
    // 队列，云端受理即算完成（打通期口径；后续可让固件在产测态补回执再收紧）。
    // 结果经 genericActionDone(actionId, ok, error) 回来。
    Q_INVOKABLE void invokeGenericAction(const QString &actionId, const QVariantMap &params);

    // 工具：密钥校验比对用 CRC32（8 位大写 hex）；b64url 编码（无填充）
    Q_INVOKABLE QString crc32Hex(const QString &text) const;
    Q_INVOKABLE QString b64Url(const QString &text) const;

    // 读产测信息汇总（结果经 infoUpdated 回来；空闲时也可调）
    Q_INVOKABLE void refreshInfo();

    // 重读 cloud_config.json（拿到密钥后不用重启软件）
    Q_INVOKABLE void reloadConfig();

signals:
    void modeChanged();
    void deviceChanged();
    void busyChanged();
    void onlineChanged();
    void heartbeatChanged();
    void devicesChanged();
    // 调试页日志（已带时间戳前缀）
    void logLine(const QString &line);
    void commandFinished(int requestId, int command, int item, int code,
                         const QString &detail);
    void commandTimeout(int requestId);
    void commandFailed(int requestId, const QString &error);
    void infoUpdated(const QVariantMap &info);
    void genericActionDone(const QString &actionId, bool ok, const QString &error);

private:
    struct PendingCommand {
        int requestId {0};
        QString actionId;
        QJsonObject params;
        int timeoutMs {10000};
    };

    int enqueue(const QString &actionId, QJsonObject params, int timeoutMs);
    void pump();
    void pollOnce();
    void loadConfig();
    void updateOnline(const CloudReply &reply);
    void setOnline(bool value);
    void log(const QString &line);
    static QString compact(const QJsonObject &obj);

    std::unique_ptr<ICloudTransport> transport_;
    QString productId_;
    QString deviceName_;
    QVariantList devices_;
    bool devicesInFlight_ {false};

    QList<PendingCommand> queue_;
    PendingCommand current_;
    bool inFlight_ {false};
    bool online_ {false};
    int heartbeatValue_ {-1};
    qint64 heartbeatLastMs_ {0};   // 0 = 尚未读到心跳
    qint64 deadlineMs_ {0};
    QTimer pollTimer_;
    QTimer idlePollTimer_;
    int nextRequestId_ {1};
};
