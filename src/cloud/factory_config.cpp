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
