#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QSet>
#include <QString>
#include <QTimer>
#include <QUdpSocket>
#include <QVariantList>

// 调焦工位局域网设备发现（CP3 老产测协议，按 D:\CP3_pro_test 源码核实）：
//
//   PC → 设备   UDP 广播 255.255.255.255:7320，载荷 = 搜索字
//               "td_adjustlenstest"（长度含结尾 '\0'），搜索期间循环重发；
//   设备 → PC   UDP 回 7319，载荷 = "<ip>;<mac>"（分号分隔，MAC 取 17 字符）。
//
// 端口/搜索字/重发周期全走 FactoryConfig（factory_config.json 可改），
// 多摄机型搜索字带 &1/&2 后缀选通道 —— 改配置，不改代码。
//
// ⚠️ 前提：设备端要有广播应答服务（监听 7320、认搜索字、回 ip;mac）。
//    老 CP3 固件自带；新 battery_ipc 固件是否已移植待确认 —— 没有则
//    这里恒搜不到，调焦页只能走手动 IP 兜底。
//
// 非单例：只有调焦页用，随页面实例化，7319 端口仅在搜索期间占用。
class DeviceDiscovery : public QObject {
    Q_OBJECT
    QML_ELEMENT

    Q_PROPERTY(bool searching READ searching NOTIFY searchingChanged)
    // 发现列表，元素 {ip, mac}；按 ip 去重，收到应答即增量追加
    Q_PROPERTY(QVariantList devices READ devices NOTIFY devicesChanged)
    // 起搜失败原因（7319 被占/被安全软件拦）。工人要看到"为什么没反应"
    Q_PROPERTY(QString lastError READ lastError NOTIFY lastErrorChanged)

public:
    explicit DeviceDiscovery(QObject *parent = nullptr);

    bool searching() const { return searching_; }
    QVariantList devices() const { return devices_; }
    QString lastError() const { return lastError_; }

    Q_INVOKABLE void start();
    Q_INVOKABLE void stop();
    Q_INVOKABLE void clear();

signals:
    void searchingChanged();
    void devicesChanged();
    void lastErrorChanged();

private:
    void sendProbe();
    void readReplies();
    void setError(const QString &text);

    QUdpSocket sendSocket_;
    QUdpSocket listenSocket_;
    QTimer probeTimer_;
    QVariantList devices_;
    QSet<QString> knownIps_;   // devices_ 的 ip 索引，去重 O(1)
    QByteArray probeWord_;     // 本轮搜索字（start 时从配置取，含 '\0'）
    quint16 sendPort_ {0};
    bool searching_ {false};
    QString lastError_;
};
