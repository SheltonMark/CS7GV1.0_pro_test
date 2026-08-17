#include "tc3_signer.hpp"

#include <QCryptographicHash>
#include <QMessageAuthenticationCode>

namespace {

QByteArray hmacSha256(const QByteArray &key, const QByteArray &message)
{
    return QMessageAuthenticationCode::hash(message, key, QCryptographicHash::Sha256);
}

QByteArray sha256Hex(const QByteArray &data)
{
    return QCryptographicHash::hash(data, QCryptographicHash::Sha256).toHex();
}

} // namespace

Tc3Signature Tc3Signer::sign(const QString &secretId, const QString &secretKey,
                             const QString &service, const QString &host,
                             const QByteArray &payload, const QDateTime &nowUtc)
{
    // ⚠️ 日期必须取 UTC —— 取本地日期在时区边界（北京时间 0-8 点）会算出
    // 与服务器不同的 credential scope，报签名错误且极难排查。
    const qint64 timestamp = nowUtc.toSecsSinceEpoch();
    const QByteArray date = nowUtc.toString(QStringLiteral("yyyy-MM-dd")).toUtf8();

    // 1. 规范请求串。头部键值、顺序、结尾换行都参与哈希，一个字符都不能差；
    //    这里的 content-type 必须与实际发送的完全一致（含 charset）。
    const QByteArray canonicalRequest =
        "POST\n"
        "/\n"
        "\n"
        "content-type:application/json; charset=utf-8\n"
        "host:" + host.toUtf8() + "\n"
        "\n"
        "content-type;host\n" +
        sha256Hex(payload);

    // 2. 待签串
    const QByteArray scope = date + "/" + service.toUtf8() + "/tc3_request";
    const QByteArray stringToSign =
        "TC3-HMAC-SHA256\n" +
        QByteArray::number(timestamp) + "\n" +
        scope + "\n" +
        sha256Hex(canonicalRequest);

    // 3. 派生签名密钥（TC3 + SecretKey 起链）
    const QByteArray secretDate = hmacSha256("TC3" + secretKey.toUtf8(), date);
    const QByteArray secretService = hmacSha256(secretDate, service.toUtf8());
    const QByteArray secretSigning = hmacSha256(secretService, "tc3_request");
    const QByteArray signature = hmacSha256(secretSigning, stringToSign).toHex();

    Tc3Signature result;
    result.timestamp = timestamp;
    result.authorization =
        "TC3-HMAC-SHA256 Credential=" + secretId.toUtf8() + "/" + scope +
        ", SignedHeaders=content-type;host, Signature=" + signature;
    return result;
}
