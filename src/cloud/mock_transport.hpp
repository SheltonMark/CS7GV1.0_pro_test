#pragma once

#include <QJsonObject>
#include <QObject>

#include "i_cloud_transport.hpp"

// 本地假设备：不出网，在内存里维护一台"设备"的产测状态。
//
// 意义：没有云 API 密钥、没有真机时，UI/指令流水/轮询闭环就能完整联调；
// 也是断网演示/培训的兜底。行为对齐设备端 ProductTestService 的语义
// （受理与执行分离、单结果槽、CS7G 能力位图），让上层代码对 Mock 与真云一字不改。
class MockTransport : public QObject, public ICloudTransport {
    Q_OBJECT

public:
    explicit MockTransport(QObject *parent = nullptr);

    QString name() const override { return QStringLiteral("mock"); }

    void invokeAction(const QString &productId, const QString &deviceName,
                      const QString &actionId, const QJsonObject &inputParams,
                      CloudReplyHandler done) override;

    void readDeviceData(const QString &productId, const QString &deviceName,
                        CloudReplyHandler done) override;

private:
    void execute(const QString &actionId, const QJsonObject &p);
    void setResult(int requestId, int command, int item, int code, const QString &detail);
    static QString nowStamp17();

    // 假设备状态（字段名与物模型 ProductTestInfo / ProductTestResult 一致）
    QJsonObject info_;
    QJsonObject result_;
    bool hasResult_ {false};
    int heartbeat_ {0};   // 每次读上报自增，模拟固件 5s 一拍的心跳计数
};
