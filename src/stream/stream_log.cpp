#include "stream_log.hpp"

#include <QClipboard>
#include <QDateTime>
#include <QGuiApplication>
#include <QMetaObject>
#include <QMutex>
#include <QMutexLocker>

#include <cstdio>

namespace {

// 环形上限：排障面板只看最近的，别让长时间跑把内存吃了
constexpr int kMaxLines = 300;

QMutex g_mutex;
QStringList g_lines;
StreamLog *g_instance = nullptr;

} // namespace

StreamLog::StreamLog(QObject *parent)
    : QObject(parent)
{
    QMutexLocker lock(&g_mutex);
    g_instance = this;
}

StreamLog::~StreamLog()
{
    QMutexLocker lock(&g_mutex);
    if (g_instance == this)
        g_instance = nullptr;
}

QStringList StreamLog::lines() const
{
    QMutexLocker lock(&g_mutex);
    return g_lines;
}

int StreamLog::count() const
{
    QMutexLocker lock(&g_mutex);
    return static_cast<int>(g_lines.size());
}

void StreamLog::clear()
{
    {
        QMutexLocker lock(&g_mutex);
        g_lines.clear();
    }
    emit linesChanged();
}

QString StreamLog::asText() const
{
    QMutexLocker lock(&g_mutex);
    return g_lines.join(QChar::fromLatin1('\n'));
}

void StreamLog::copyToClipboard() const
{
    if (QClipboard *cb = QGuiApplication::clipboard())
        cb->setText(asText());
}

void StreamLog::append(const QString &line)
{
    const QString stamped =
        QDateTime::currentDateTime().toString(QStringLiteral("HH:mm:ss.zzz"))
        + QLatin1Char(' ') + line;

    // 先落 stderr（=日志文件），再进内存 —— 即便进程随后崩了，文件里也有。
    std::fprintf(stderr, "%s\n", qPrintable(stamped));
    std::fflush(stderr);

    StreamLog *inst = nullptr;
    {
        QMutexLocker lock(&g_mutex);
        g_lines.append(stamped);
        while (g_lines.size() > kMaxLines)
            g_lines.removeFirst();
        inst = g_instance;
    }
    if (!inst)
        return;
    // 任意线程都可能调到这里，信号必须弹回单例所在线程再发
    QMetaObject::invokeMethod(inst, [inst] { emit inst->linesChanged(); },
                              Qt::QueuedConnection);
}
