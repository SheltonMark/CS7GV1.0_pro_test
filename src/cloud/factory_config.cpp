#include "factory_config.hpp"

#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>

namespace {

FactoryConfig *g_instance = nullptr;

} // namespace

FactoryConfig::FactoryConfig(QObject *parent)
    : QObject(parent)
{
    load();
}

FactoryConfig *FactoryConfig::instance()
{
    if (g_instance == nullptr)
        g_instance = new FactoryConfig();
    return g_instance;
}

FactoryConfig *FactoryConfig::create(QQmlEngine *engine, QJSEngine *scriptEngine)
{
    Q_UNUSED(engine)
    Q_UNUSED(scriptEngine)
    FactoryConfig *inst = instance();
    // C++ 侧持有所有权：QML 引擎销毁时不能把共享单例删掉
    QQmlEngine::setObjectOwnership(inst, QQmlEngine::CppOwnership);
    return inst;
}

QString FactoryConfig::filePath() const
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/factory_config.json");
}

void FactoryConfig::load()
{
    root_ = QJsonObject();
    QFile file(filePath());
    if (file.open(QIODevice::ReadOnly))
        root_ = QJsonDocument::fromJson(file.readAll()).object();
}

bool FactoryConfig::save()
{
    QFile file(filePath());
    if (!file.open(QIODevice::WriteOnly | QIODevice::Truncate))
        return false;
    file.write(QJsonDocument(root_).toJson(QJsonDocument::Indented));
    return true;
}

void FactoryConfig::reload()
{
    load();
    emit configChanged();
}

int FactoryConfig::topInt(const char *key, int fallback) const
{
    const QJsonValue v = root_.value(QLatin1String(key));
    return v.isDouble() ? v.toInt(fallback) : fallback;
}

int FactoryConfig::nestedInt(const char *section, const char *key, int fallback) const
{
    const QJsonValue v =
        root_.value(QLatin1String(section)).toObject().value(QLatin1String(key));
    return v.isDouble() ? v.toInt(fallback) : fallback;
}

QString FactoryConfig::topString(const char *key, const char *fallback) const
{
    const QJsonValue v = root_.value(QLatin1String(key));
    return v.isString() ? v.toString() : QLatin1String(fallback);
}

int FactoryConfig::shutdownDelaySec() const { return topInt("shutdownDelaySec", 120); }
int FactoryConfig::pollIntervalMs() const { return topInt("pollIntervalMs", 500); }
int FactoryConfig::heartbeatTimeoutSec() const { return topInt("heartbeatTimeoutSec", 15); }
int FactoryConfig::timeoutNormalMs() const { return nestedInt("timeouts", "normalMs", 10000); }
int FactoryConfig::timeoutFlashMs() const { return nestedInt("timeouts", "flashMs", 15000); }
int FactoryConfig::timeoutPeripheralMs() const { return nestedInt("timeouts", "peripheralMs", 15000); }
int FactoryConfig::timeoutCellularMs() const { return nestedInt("timeouts", "cellularMs", 40000); }
int FactoryConfig::sdTestSizeMb() const { return nestedInt("peripheral", "sdTestSizeMb", 1); }
int FactoryConfig::whiteBrightness() const { return nestedInt("peripheral", "whiteBrightness", 100); }
int FactoryConfig::ledBlinkMs() const { return nestedInt("peripheral", "ledBlinkMs", 500); }
int FactoryConfig::speakerRepeat() const { return nestedInt("peripheral", "speakerRepeat", 1); }

QString FactoryConfig::rtspUrlTemplate() const
{
    // 路径 /tenda 按老 CP3 源码核实(DlgFocusing.cpp:771);双摄机型是
    // /tenda/ch1、/tenda/ch2 —— 换机型改 factory_config.json,不用改代码。
    return topString("rtspUrlTemplate", "rtsp://%1:554/tenda");
}

QString FactoryConfig::updateSource() const
{
    // 默认空 = 在线升级未开通。工厂在 factory_config.json 里填内网共享目录
    //（UNC 路径），各工位 PC 从那里比对差异、只拉变化的文件。
    return topString("updateSource", "");
}

// —— 调焦设备发现(端口/搜索字按老 CP3 源码 DlgFocusing.cpp 核实)
// PC→设备 广播端口(SENT_UDP_PORT_BROAD)
int FactoryConfig::discoverySendPort() const { return topInt("discoverySendPort", 7320); }
// 设备→PC 应答端口(TRANSMIT_UDP_PORT_BROAD;协议定死回这里,不回源端口)
int FactoryConfig::discoveryListenPort() const { return topInt("discoveryListenPort", 7319); }

QString FactoryConfig::discoveryWord() const
{
    // 广播搜索字;多摄机型带 &1/&2 后缀选通道(DlgFocusing.cpp:1136-1144)
    return topString("discoveryWord", "td_adjustlenstest");
}

int FactoryConfig::discoveryIntervalMs() const
{
    // 搜索期间重发周期。老代码是 while(TRUE)+sendto 不间断猛发,
    // 没必要 —— 设备应答毫秒级,800ms 一发足够,还不刷爆局域网
    return topInt("discoveryIntervalMs", 800);
}

QVariantList FactoryConfig::stationItems(const QString &productId, const QString &station,
                                         const QString &group,
                                         const QVariantList &fallback) const
{
    const QJsonValue v = root_.value(QStringLiteral("stationItems")).toObject()
                             .value(productId).toObject()
                             .value(station).toObject()
                             .value(group);
    if (!v.isArray())
        return fallback;  // 从未配置 = 全选（fallback 由调用方给）
    return v.toArray().toVariantList();
}

void FactoryConfig::setStationItems(const QString &productId, const QString &station,
                                    const QString &group, const QVariantList &values)
{
    // QJsonObject 取出即副本：逐层读出→改→逐层写回
    QJsonObject all = root_.value(QStringLiteral("stationItems")).toObject();
    QJsonObject product = all.value(productId).toObject();
    QJsonObject stationObj = product.value(station).toObject();
    stationObj.insert(group, QJsonArray::fromVariantList(values));
    product.insert(station, stationObj);
    all.insert(productId, product);
    root_.insert(QStringLiteral("stationItems"), all);
    save();
    emit configChanged();
}
