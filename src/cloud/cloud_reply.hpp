#pragma once

#include <QJsonObject>
#include <QString>
#include <functional>
#include <utility>

// 云传输层的统一应答。ok=false 时 error 面向日志/调试页，data 为空。
// data 的形状由各调用约定（见 ICloudTransport 注释），传输层负责规格化——
// 上层(CloudClient)不感知走的是 Mock 还是真云。
struct CloudReply {
    bool ok {false};
    QString error;
    QJsonObject data;

    static CloudReply success(QJsonObject payload)
    {
        return {true, QString(), std::move(payload)};
    }

    static CloudReply failure(QString reason)
    {
        return {false, std::move(reason), QJsonObject()};
    }
};

using CloudReplyHandler = std::function<void(const CloudReply &)>;
