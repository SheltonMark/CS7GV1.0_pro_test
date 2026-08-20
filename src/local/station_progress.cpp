#include "station_progress.hpp"

#include <QCoreApplication>
#include <QDir>
#include <QFile>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>
#include <QVariantMap>

namespace {

// 与 exe 同目录，和 factory_config.json 一样是"现场可看可删"的文件。
// 放这里而不是 AppData：产线机常是共用账号/还原环境，AppData 不一定留得住，
// 而且出问题时让工人找 AppData 不现实。
QString StorePath()
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/station_progress.json");
}

} // namespace

StationProgress::StationProgress(QObject *parent)
    : QObject(parent)
    , path_(StorePath())
{
    load();
}

StationProgress::~StationProgress()
{
    if (dirty_)
        save();
}

QString StationProgress::keyOf(const QString &productId, const QString &deviceName)
{
    return productId + QLatin1Char('/') + deviceName;
}

bool StationProgress::isDone(const QString &productId, const QString &deviceName,
                             const QString &station) const
{
    if (deviceName.isEmpty() || station.isEmpty())
        return false;
    return done_.value(keyOf(productId, deviceName)).value(station, false);
}

void StationProgress::setDone(const QString &productId, const QString &deviceName,
                              const QString &station, bool done)
{
    if (deviceName.isEmpty() || station.isEmpty())
        return;
    const QString key = keyOf(productId, deviceName);
    auto &stations = done_[key];
    if (stations.value(station, false) == done)
        return;
    if (done)
        stations.insert(station, true);
    else
        stations.remove(station);
    if (stations.isEmpty())
        done_.remove(key);
    dirty_ = true;
    save();          // 立刻落盘：产线随时可能断电，攒着写等于没存
    emit changed();
}

void StationProgress::syncFromDevice(const QString &productId, const QString &deviceName,
                                     const QString &focusTime, const QString &semiTime,
                                     const QString &finishTime, const QString &inspectTime)
{
    if (deviceName.isEmpty())
        return;

    // 设备侧标识才是权威。以它为准双向校正：
    //   设备有、本地无 → 补上（换 PC / 本地被删后自愈）
    //   设备无、本地有 → 清掉（否则工人以为测过了，漏测）
    const QString key = keyOf(productId, deviceName);
    auto &stations = done_[key];
    bool touched = false;

    const struct { const char *station; const QString &stamp; } pairs[] = {
        {"focus", focusTime}, {"semi", semiTime},
        {"finished", finishTime}, {"inspect", inspectTime},
    };
    for (const auto &p : pairs) {
        const QString station = QString::fromLatin1(p.station);
        const bool onDevice = !p.stamp.isEmpty();
        if (stations.value(station, false) == onDevice)
            continue;
        if (onDevice)
            stations.insert(station, true);
        else
            stations.remove(station);
        touched = true;
    }

    if (stations.isEmpty())
        done_.remove(key);
    if (!touched)
        return;
    dirty_ = true;
    save();
    emit changed();
}

QString StationProgress::nextPending(const QString &productId, const QString &station,
                                    const QVariantList &devices, const QString &after) const
{
    if (devices.isEmpty() || station.isEmpty())
        return QString();

    // after 在名单里的位置；不在（或为空）就从头开始
    int start = -1;
    for (int i = 0; i < devices.size(); ++i) {
        if (devices.at(i).toMap().value(QStringLiteral("deviceName")).toString() == after) {
            start = i;
            break;
        }
    }

    // 从 after 的下一个起绕一圈。绕回是必要的：工人不一定严格按卡号顺序放机器，
    // 单向走到底会在中途留下没测的机器却提示"全做完了"。
    const int n = devices.size();
    for (int step = 1; step <= n; ++step) {
        const QVariantMap d = devices.at((start + step) % n).toMap();
        const QString name = d.value(QStringLiteral("deviceName")).toString();
        if (name.isEmpty())
            continue;
        if (!d.value(QStringLiteral("online")).toBool())
            continue;                          // 离线的跳过：切过去也没法测
        if (isDone(productId, name, station))
            continue;                          // 本工位已做完的跳过
        return name;
    }
    return QString();
}

void StationProgress::clearProduct(const QString &productId)
{
    const QString prefix = productId + QLatin1Char('/');
    bool touched = false;
    for (auto it = done_.begin(); it != done_.end();) {
        if (it.key().startsWith(prefix)) {
            it = done_.erase(it);
            touched = true;
        } else {
            ++it;
        }
    }
    if (!touched)
        return;
    dirty_ = true;
    save();
    emit changed();
}

void StationProgress::load()
{
    QFile f(path_);
    if (!f.open(QIODevice::ReadOnly))
        return;                       // 首次运行没有文件，不是错误
    const QJsonObject root = QJsonDocument::fromJson(f.readAll()).object();
    for (auto it = root.constBegin(); it != root.constEnd(); ++it) {
        const QJsonObject stations = it.value().toObject();
        QHash<QString, bool> m;
        for (auto s = stations.constBegin(); s != stations.constEnd(); ++s) {
            if (s.value().toBool())
                m.insert(s.key(), true);
        }
        if (!m.isEmpty())
            done_.insert(it.key(), m);
    }
}

void StationProgress::save()
{
    QJsonObject root;
    for (auto it = done_.constBegin(); it != done_.constEnd(); ++it) {
        QJsonObject stations;
        for (auto s = it.value().constBegin(); s != it.value().constEnd(); ++s)
            stations.insert(s.key(), true);
        root.insert(it.key(), stations);
    }
    // QSaveFile：写一半断电不会留下损坏的 JSON（原地写会）。
    QSaveFile f(path_);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(root).toJson(QJsonDocument::Indented));
    if (f.commit())
        dirty_ = false;
}
