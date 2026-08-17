#include "device_discovery.hpp"

#include "factory_config.hpp"

#include <QHostAddress>
#include <QNetworkInterface>
#include <QVariantMap>

DeviceDiscovery::DeviceDiscovery(QObject *parent)
    : QObject(parent)
{
    connect(&probeTimer_, &QTimer::timeout, this, &DeviceDiscovery::sendProbe);
    connect(&listenSocket_, &QUdpSocket::readyRead, this, &DeviceDiscovery::readReplies);
}

void DeviceDiscovery::start()
{
    if (searching_)
        return;
    setError(QString());

    // 参数在每轮搜索开始时取一次：改了 factory_config.json 重开搜索即生效；
    // 搜索进行中不换参数（半轮换端口只会制造诡异现象）。
    const FactoryConfig *cfg = FactoryConfig::instance();
    const int sendPort = cfg->discoverySendPort();
    const int listenPort = cfg->discoveryListenPort();
    if (sendPort <= 0 || sendPort > 65535 || listenPort <= 0 || listenPort > 65535) {
        setError(QStringLiteral("discovery 端口配置非法：%1/%2（检查 factory_config.json）")
                     .arg(sendPort).arg(listenPort));
        return;
    }
    sendPort_ = quint16(sendPort);
    // 载荷长度 = strlen+1，结尾 '\0' 一并发出 —— 设备端按 C 字符串整包比较，
    // 老 PC 端就是这么发的（DlgFocusing.cpp:1165），不带会比不中。
    probeWord_ = cfg->discoveryWord().toUtf8();
    probeWord_.append('\0');

    // 应答固定回 7319（协议定死，不回源端口），必须真 bind 上才收得到。
    // ShareAddress|ReuseAddressHint：软件被双开时第二个实例也能 bind 成功
    //（Windows 上广播包两个实例都收得到），不至于一点搜索就报错。
    if (!listenSocket_.bind(QHostAddress::AnyIPv4, quint16(listenPort),
                            QUdpSocket::ShareAddress | QUdpSocket::ReuseAddressHint)) {
        setError(QStringLiteral("监听端口 %1 绑定失败：%2")
                     .arg(listenPort).arg(listenSocket_.errorString()));
        return;
    }

    searching_ = true;
    emit searchingChanged();

    // 点了按钮立刻发第一发，不等首个周期 —— 设备应答通常毫秒级，
    // 干等 800ms 会让"搜索很慢"的错觉坐实
    sendProbe();
    probeTimer_.start(cfg->discoveryIntervalMs());
}

void DeviceDiscovery::stop()
{
    if (!searching_)
        return;
    probeTimer_.stop();
    listenSocket_.close();   // 释放 7319 —— 不搜索时不占公共端口
    searching_ = false;
    emit searchingChanged();
}

void DeviceDiscovery::clear()
{
    if (devices_.isEmpty())
        return;
    devices_.clear();
    knownIps_.clear();
    emit devicesChanged();
}

void DeviceDiscovery::sendProbe()
{
    // 老代码只发 255.255.255.255；这里再对每块网卡的子网定向广播补一发：
    // 产线 PC 常是 WiFi（默认路由）+ 有线（直连设备）双网卡，全局广播由
    // 系统挑网卡发出，可能只走了 WiFi —— 设备挂在有线侧就永远搜不到。
    // 设备端收到的载荷与端口完全一致，协议兼容。
    sendSocket_.writeDatagram(probeWord_, QHostAddress::Broadcast, sendPort_);
    const QList<QNetworkInterface> ifaces = QNetworkInterface::allInterfaces();
    for (const QNetworkInterface &iface : ifaces) {
        const auto flags = iface.flags();
        if (!(flags & QNetworkInterface::IsUp) || (flags & QNetworkInterface::IsLoopBack))
            continue;
        const QList<QNetworkAddressEntry> entries = iface.addressEntries();
        for (const QNetworkAddressEntry &entry : entries) {
            const QHostAddress bcast = entry.broadcast();  // IPv6 无广播地址，是 null
            if (!bcast.isNull())
                sendSocket_.writeDatagram(probeWord_, bcast, sendPort_);
        }
    }
}

void DeviceDiscovery::readReplies()
{
    while (listenSocket_.hasPendingDatagrams()) {
        QByteArray data;
        data.resize(int(listenSocket_.pendingDatagramSize()));
        listenSocket_.readDatagram(data.data(), data.size());

        // 设备按 C 字符串发，可能带结尾 '\0'，先截到首个 '\0'
        const qsizetype nul = data.indexOf('\0');
        if (nul >= 0)
            data.truncate(nul);

        // 载荷 "<ip>;<mac>"。7319 是普通端口，可能收到无关杂包 ——
        // 格式不符/IP 非法一律静默丢弃，不能让杂包污染列表
        const QString text = QString::fromUtf8(data).trimmed();
        const qsizetype sep = text.indexOf(QLatin1Char(';'));
        if (sep <= 0)
            continue;
        const QString ip = text.left(sep).trimmed();
        // MAC 固定取 17 字符（AA:BB:CC:DD:EE:FF）—— 老协议如此
        //（DlgFocusing.cpp:458-464），后面可能跟别的字节
        const QString mac = text.mid(sep + 1).trimmed().left(17);
        if (QHostAddress(ip).isNull() || knownIps_.contains(ip))
            continue;   // 非法 IP，或已在列表（按 ip 去重）

        knownIps_.insert(ip);
        devices_.append(QVariantMap { { QStringLiteral("ip"), ip },
                                      { QStringLiteral("mac"), mac } });
        emit devicesChanged();
    }
}

void DeviceDiscovery::setError(const QString &text)
{
    if (lastError_ == text)
        return;
    lastError_ = text;
    emit lastErrorChanged();
}
