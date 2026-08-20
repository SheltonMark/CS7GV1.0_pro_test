#include "tencent_api_transport.hpp"

#include <QDateTime>
#include <QJsonArray>
#include <QJsonDocument>
#include <QNetworkReply>
#include <QNetworkRequest>
#include <QUrl>

#include "tc3_signer.hpp"

#include <utility>

namespace {

constexpr char kHost[] = "iotexplorer.tencentcloudapi.com";
constexpr char kService[] = "iotexplorer";
constexpr char kVersion[] = "2019-04-23";
// HTTP 层超时。指令的"等设备上报"超时是另一回事，由 CloudClient 管。
constexpr int kHttpTimeoutMs = 10000;

} // namespace

TencentApiTransport::TencentApiTransport(TencentApiConfig config, QObject *parent)
    : QObject(parent)
    , config_(std::move(config))
{
}

void TencentApiTransport::post(const QString &action, const QJsonObject &params,
                               CloudReplyHandler done)
{
    const QByteArray payload = QJsonDocument(params).toJson(QJsonDocument::Compact);
    const Tc3Signature sig =
        Tc3Signer::sign(config_.secretId, config_.secretKey, QLatin1String(kService),
                        QLatin1String(kHost), payload, QDateTime::currentDateTimeUtc());

    QNetworkRequest request(QUrl(QStringLiteral("https://") + QLatin1String(kHost)));
    // content-type 必须与签名里的规范头逐字节一致（见 Tc3Signer）
    request.setHeader(QNetworkRequest::ContentTypeHeader,
                      QStringLiteral("application/json; charset=utf-8"));
    request.setRawHeader("Authorization", sig.authorization);
    request.setRawHeader("X-TC-Action", action.toUtf8());
    request.setRawHeader("X-TC-Version", kVersion);
    request.setRawHeader("X-TC-Timestamp", QByteArray::number(sig.timestamp));
    request.setRawHeader("X-TC-Region", config_.region.toUtf8());
    request.setTransferTimeout(kHttpTimeoutMs);

    QNetworkReply *reply = nam_.post(request, payload);
    // 以 this 为 context：传输层被替换/销毁时自动断连，回调不会打到已析构对象
    connect(reply, &QNetworkReply::finished, this, [reply, done, action]() {
        reply->deleteLater();
        const QJsonObject response =
            QJsonDocument::fromJson(reply->readAll()).object()
                .value(QStringLiteral("Response")).toObject();
        // 业务错误优先于网络错误：4xx 时 body 里的 Error.Message 更准
        const QJsonObject error = response.value(QStringLiteral("Error")).toObject();
        if (!error.isEmpty()) {
            done(CloudReply::failure(action + QStringLiteral(": ") +
                                     error.value(QStringLiteral("Code")).toString() +
                                     QStringLiteral(" ") +
                                     error.value(QStringLiteral("Message")).toString()));
            return;
        }
        if (reply->error() != QNetworkReply::NoError) {
            done(CloudReply::failure(action + QStringLiteral(": ") + reply->errorString()));
            return;
        }
        done(CloudReply::success(response));
    });
}

void TencentApiTransport::invokeAction(const QString &productId, const QString &deviceName,
                                       const QString &actionId, const QJsonObject &inputParams,
                                       CloudReplyHandler done)
{
    // InputParams 是"JSON 字符串"不是对象——云 API 的约定，传对象会报参数错误
    const QJsonObject params{
        {QStringLiteral("ProductId"), productId},
        {QStringLiteral("DeviceName"), deviceName},
        {QStringLiteral("ActionId"), actionId},
        {QStringLiteral("InputParams"),
         QString::fromUtf8(QJsonDocument(inputParams).toJson(QJsonDocument::Compact))},
    };
    post(QStringLiteral("CallDeviceActionAsync"), params, std::move(done));
}

void TencentApiTransport::readDeviceData(const QString &productId, const QString &deviceName,
                                         CloudReplyHandler done)
{
    const QJsonObject params{
        {QStringLiteral("ProductId"), productId},
        {QStringLiteral("DeviceName"), deviceName},
    };
    post(QStringLiteral("DescribeDeviceData"), params,
         [done](const CloudReply &reply) {
             if (!reply.ok) {
                 done(reply);
                 return;
             }
             // Data 字段本身是 JSON 字符串：{"Prop":{"Value":…,"LastUpdate":…},…}
             // 解开一层即为接口约定的规格化形状。
             const QByteArray raw =
                 reply.data.value(QStringLiteral("Data")).toString().toUtf8();
             done(CloudReply::success(QJsonDocument::fromJson(raw).object()));
         });
}

void TencentApiTransport::describeDevices(const QString &productId, CloudReplyHandler done)
{
    // 产线一次最多十几台工装卡，一页足够。Limit 上限 100（云 API 约定），
    // 真超了再补分页 —— 现在补等于写不会被执行的代码。
    const QJsonObject params{
        {QStringLiteral("ProductId"), productId},
        {QStringLiteral("Offset"), 0},
        {QStringLiteral("Limit"), 100},
    };
    post(QStringLiteral("DescribeDevices"), params,
         [done](const CloudReply &reply) {
             if (!reply.ok) {
                 done(reply);
                 return;
             }
             // 应答形状：{ "Devices": [ {"DeviceName":…, "Status": 0|1, …} ], "Total": n }
             // Status 1=在线 0=离线（腾讯 IoT Explorer 约定）。
             QJsonArray out;
             const QJsonArray devices =
                 reply.data.value(QStringLiteral("Devices")).toArray();
             for (const QJsonValue &v : devices) {
                 const QJsonObject d = v.toObject();
                 const QString name = d.value(QStringLiteral("DeviceName")).toString();
                 if (name.isEmpty())
                     continue;
                 out.append(QJsonObject{
                     {QStringLiteral("deviceName"), name},
                     {QStringLiteral("online"),
                      d.value(QStringLiteral("Status")).toInt() == 1},
                 });
             }
             done(CloudReply::success(QJsonObject{{QStringLiteral("devices"), out}}));
         });
}
