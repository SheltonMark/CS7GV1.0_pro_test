#include "file_io.hpp"

#include <QFile>
#include <QFileInfo>
#include <QTextStream>

QString FileIo::readText(const QUrl &url) {
    last_error_.clear();
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly | QIODevice::Text)) {
        last_error_ = QStringLiteral("打不开文件：") + file.errorString();
        return {};
    }
    QTextStream in(&file);
    // InputData 的列都是 ASCII（MAC/SN/密钥/SSID），按 UTF-8 读即可；
    // 万一产线给的是 GBK，ASCII 部分也不会乱。
    in.setEncoding(QStringConverter::Utf8);
    return in.readAll();
}

bool FileIo::writeText(const QUrl &url, const QString &text) {
    last_error_.clear();
    const QString path = url.isLocalFile() ? url.toLocalFile() : url.toString();
    QFile file(path);
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        last_error_ = QStringLiteral("无法写入：") + file.errorString();
        return false;
    }
    QString out = text;
    out.replace(QLatin1String("\r\n"), QLatin1String("\n"));
    out.replace(QLatin1Char('\n'), QLatin1String("\r\n"));
    const QByteArray bytes = out.toUtf8();
    if (file.write(bytes) != bytes.size()) {
        last_error_ = QStringLiteral("写入不完整：") + file.errorString();
        return false;
    }
    file.close();
    return true;
}

QString FileIo::fileName(const QUrl &url) const {
    return QFileInfo(url.isLocalFile() ? url.toLocalFile() : url.toString()).fileName();
}
