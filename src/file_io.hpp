#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QUrl>

// 批次文件读写。
//
// 为什么要下沉到 C++：QML 没有文件写入 API（读可以用 XMLHttpRequest 硬凑，
// 但对本地文件的行为在各平台不一致，写则完全没有）。这里只做纯文本读/写两件事，
// **解析与呈现全留在 QML** —— InputData 的列语义还没和产线定死，
// 放在 QML 里改一行就能调整，不必重编。
class FileIo : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit FileIo(QObject *parent = nullptr) : QObject(parent) {}

    // 读文本文件。失败返回空串，原因见 lastError()。
    Q_INVOKABLE QString readText(const QUrl &url);

    // 写文本文件。产线的下游工具（打印系统）多在 Windows 上处理，
    // 行尾统一 CRLF，避免有的编辑器把整个文件显示成一行。
    Q_INVOKABLE bool writeText(const QUrl &url, const QString &text);

    Q_INVOKABLE QString lastError() const { return last_error_; }

    // 取文件名（QML 里从 URL 拿显示名，省得自己切字符串）
    Q_INVOKABLE QString fileName(const QUrl &url) const;

private:
    QString last_error_;
};
