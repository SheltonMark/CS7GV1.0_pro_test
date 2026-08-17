#pragma once

#include <QByteArray>
#include <QDateTime>
#include <QString>

// 腾讯云 API 3.0 的 TC3-HMAC-SHA256 签名。纯 Qt 实现（QCryptographicHash +
// QMessageAuthenticationCode），零第三方依赖。
//
// 独立成类的原因：签名一旦错，云端只回一句 AuthFailure.SignatureFailure，
// 什么中间量都不给——必须能在本地把 CanonicalRequest/StringToSign 逐段对拍。
struct Tc3Signature {
    QByteArray authorization;  // Authorization 头完整值
    qint64 timestamp {0};      // 同一时刻要放进 X-TC-Timestamp，两者必须一致
};

class Tc3Signer {
public:
    // service 例 "iotexplorer"，host 例 "iotexplorer.tencentcloudapi.com"。
    // 固定 POST / + content-type;host 两个签名头（官方最简形态）。
    static Tc3Signature sign(const QString &secretId, const QString &secretKey,
                             const QString &service, const QString &host,
                             const QByteArray &payload, const QDateTime &nowUtc);
};
