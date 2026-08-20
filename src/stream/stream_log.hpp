#pragma once

#include <QObject>
#include <QStringList>
#include <QtQml/qqmlregistration.h>

// 拉流排障日志汇聚点。
//
// 为什么要有这个：产测软件是 WIN32_EXECUTABLE（无控制台），fprintf(stderr)
// 在双击运行时**没有任何去处** —— 排障期写的日志全丢了。这里做两件事：
//   1) 每条都镜像到 stderr（main.cpp 已把 stderr 重定向到 logs/*.log 落盘）；
//   2) 存最近 N 条给 QML 显示，产线现场/远程只能截图时也能拿到信息。
//
// append() 允许任意线程调（SDK 回调线程、libvlc 解码线程都会写），内部加锁并
// 把信号弹回本对象线程。
class StreamLog : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QStringList lines READ lines NOTIFY linesChanged)
    Q_PROPERTY(int count READ count NOTIFY linesChanged)

public:
    explicit StreamLog(QObject *parent = nullptr);
    ~StreamLog() override;

    QStringList lines() const;
    int count() const;

    Q_INVOKABLE void clear();
    // 全部日志拼成一段文本，给"复制"按钮用（现场发我们分析）
    Q_INVOKABLE QString asText() const;
    // 直接进系统剪贴板。QML 侧没有剪贴板接口，早先靠一个隐藏 TextArea 的
    // selectAll()+copy() 代劳 —— 那要求控件常驻存活，日志面板因此没法真正
    // 收起/销毁。放到 C++ 就没这个牵连了。
    Q_INVOKABLE void copyToClipboard() const;
    // 给 QML 用的写日志入口（静态 append 在 QML 里调不到）。排障期 QML 侧也要能
    // 往同一条日志里写，否则"界面上什么都没发生"这类问题只能靠猜。
    Q_INVOKABLE void log(const QString &line) { append(line); }

    // 线程安全。前缀建议用 [xp2p]/[vlc] 之类，便于筛。
    static void append(const QString &line);

signals:
    void linesChanged();

private:
    void appendInternal(const QString &line);
};
