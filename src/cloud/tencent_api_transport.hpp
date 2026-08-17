#pragma once

#include <QNetworkAccessManager>
#include <QObject>

#include "i_cloud_transport.hpp"

struct TencentApiConfig {
    QString secretId;
    QString secretKey;
    QString region {QStringLiteral("ap-guangzhou")};
};

// 腾讯云 API 3.0 直连（打通期方案，跳过腾达后台）：
//   下发 = CallDeviceActionAsync（受理即回，不等执行）
//   上行 = DescribeDeviceData 轮询（由 CloudClient 驱动节奏）
// 服务固定 iotexplorer（物联网开发平台，版本 2019-04-23）。
// 所需云侧权限即给管理员的最小策略清单（2026-08-17 已提供）。
class TencentApiTransport : public QObject, public ICloudTransport {
    Q_OBJECT

public:
    explicit TencentApiTransport(TencentApiConfig config, QObject *parent = nullptr);

    QString name() const override { return QStringLiteral("tencent"); }

    void invokeAction(const QString &productId, const QString &deviceName,
                      const QString &actionId, const QJsonObject &inputParams,
                      CloudReplyHandler done) override;

    void readDeviceData(const QString &productId, const QString &deviceName,
                        CloudReplyHandler done) override;

private:
    void post(const QString &action, const QJsonObject &params, CloudReplyHandler done);

    TencentApiConfig config_;
    QNetworkAccessManager nam_;
};
