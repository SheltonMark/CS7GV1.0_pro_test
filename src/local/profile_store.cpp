#include "profile_store.hpp"

#include <QCoreApplication>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace {

QString StorePath()
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/profiles.json");
}

// 工位序列。现有两个型号完全一致，新增型号默认给同一套 —— 管理员不用手敲。
QVariantList MakeDefaultStations()
{
    return QVariantList{
        QVariantMap{{"key", "focus"},    {"title", "调焦"},   {"sub", "工位 1"}},
        QVariantMap{{"key", "semi"},     {"title", "准成品"}, {"sub", "工位 2"}},
        QVariantMap{{"key", "finished"}, {"title", "成品"},   {"sub", "工位 2"}},
        QVariantMap{{"key", "inspect"},  {"title", "检查"},   {"sub", "工位 3"}},
        QVariantMap{{"key", "repair"},   {"title", "维修"},   {"sub", "按需"}},
    };
}

// 测试项位 → 中文名。位序与物模型 SupportedItems 一致（设备端 cloud_property_mapper）。
// bit1 红外灯 / bit3 日夜切换：CS7G 这类全彩夜视产品没有这两样硬件（用白光补光，
// 既无 IR 灯也无 IR-CUT），所以内置型号的 items 里不含它们 —— 但列表里要给出来，
// 别的型号可能有。
struct ItemDef { int bit; const char *label; };
constexpr ItemDef kItems[] = {
    {0,  "指示灯"},   {1,  "红外灯"}, {2,  "白光灯"},  {3,  "日夜切换"},
    {4,  "复位按键"}, {5,  "电池"},   {6,  "云台"},    {7,  "喇叭"},
    {8,  "咪头"},     {9,  "4G"},     {10, "SD 卡"},
};

} // namespace

ProfileStore::ProfileStore(QObject *parent)
    : QObject(parent)
    , path_(StorePath())
{
    load();
    seedBuiltinsIfMissing();
}

int ProfileStore::indexOf(const QString &name) const
{
    for (int i = 0; i < profiles_.size(); ++i)
        if (profiles_.at(i).toMap().value(QStringLiteral("name")).toString() == name)
            return i;
    return -1;
}

QVariantList ProfileStore::defaultStations() const
{
    return MakeDefaultStations();
}

QVariantList ProfileStore::allItems() const
{
    QVariantList out;
    for (const ItemDef &d : kItems) {
        out.append(QVariantMap{
            {QStringLiteral("bit"), d.bit},
            {QStringLiteral("label"), QString::fromUtf8(d.label)},
        });
    }
    return out;
}

QString ProfileStore::upsert(const QVariantMap &profile)
{
    const QString name = profile.value(QStringLiteral("name")).toString().trimmed();
    const QString productId =
        profile.value(QStringLiteral("productId")).toString().trimmed();
    if (name.isEmpty())
        return QStringLiteral("型号名不能为空");
    if (productId.isEmpty())
        return QStringLiteral("ProductId 不能为空 —— 设备名单、产测指令、拉流都靠它");

    QVariantMap p = profile;
    p[QStringLiteral("name")] = name;
    p[QStringLiteral("productId")] = productId;
    // 缺省值兜住：界面漏传字段不该让整条 profile 失效
    if (!p.contains(QStringLiteral("desc")))
        p[QStringLiteral("desc")] = QString();
    if (!p.contains(QStringLiteral("enabled")))
        p[QStringLiteral("enabled")] = true;
    if (!p.contains(QStringLiteral("focusRtsp")))
        p[QStringLiteral("focusRtsp")] = false;
    if (!p.contains(QStringLiteral("items")))
        p[QStringLiteral("items")] = QVariantList();
    if (!p.contains(QStringLiteral("stations"))
        || p.value(QStringLiteral("stations")).toList().isEmpty()) {
        // 没有工位的型号点进去会是一片空白，直接给默认序列
        p[QStringLiteral("stations")] = MakeDefaultStations();
    }

    const int i = indexOf(name);
    if (i >= 0)
        profiles_[i] = p;
    else
        profiles_.append(p);
    save();
    emit profilesChanged();
    return QString();
}

QString ProfileStore::remove(const QString &name)
{
    const int i = indexOf(name);
    if (i < 0)
        return QStringLiteral("型号不存在");
    if (profiles_.size() <= 1)
        return QStringLiteral("至少要保留一个型号 —— 否则产品选择页会是空的");
    profiles_.removeAt(i);
    save();
    emit profilesChanged();
    return QString();
}

void ProfileStore::seedBuiltinsIfMissing()
{
    if (!profiles_.isEmpty())
        return;
    // 与原先 MockData.qml:20-42 那两条**逐字段一致** —— 升级到本版本的机器不能看到
    // 空的产品选择页。
    const QVariantList items{0, 2, 4, 5, 6, 7, 8, 9, 10};
    profiles_.append(QVariantMap{
        {QStringLiteral("name"), QStringLiteral("CS7GV1.0")},
        {QStringLiteral("desc"), QStringLiteral("低功耗电池 IPC · 带网口")},
        {QStringLiteral("productId"), QStringLiteral("5KHBENFCX2")},
        {QStringLiteral("enabled"), true},
        {QStringLiteral("focusRtsp"), true},
        {QStringLiteral("items"), items},
        {QStringLiteral("stations"), MakeDefaultStations()},
    });
    profiles_.append(QVariantMap{
        {QStringLiteral("name"), QStringLiteral("CS6GV2.0")},
        {QStringLiteral("desc"), QStringLiteral("低功耗电池 IPC · 无网口")},
        // ⚠️ 暂借 CS7G 的测试产品；拿到 CS6G 正式 ProductId 后在界面里改这一项
        {QStringLiteral("productId"), QStringLiteral("5KHBENFCX2")},
        {QStringLiteral("enabled"), true},
        {QStringLiteral("focusRtsp"), false},
        {QStringLiteral("items"), items},
        {QStringLiteral("stations"), MakeDefaultStations()},
    });
    save();
    emit profilesChanged();
}

void ProfileStore::load()
{
    QFile f(path_);
    if (!f.open(QIODevice::ReadOnly))
        return;                      // 首次运行没有文件，由 seed 补
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (const QJsonValue &v : arr) {
        const QVariantMap p = v.toObject().toVariantMap();
        // 缺 name 或 productId 的条目直接丢：留着会让产品选择页出现点不动的空卡片
        if (p.value(QStringLiteral("name")).toString().isEmpty()
            || p.value(QStringLiteral("productId")).toString().isEmpty())
            continue;
        profiles_.append(p);
    }
}

void ProfileStore::save()
{
    QJsonArray arr;
    for (const QVariant &v : profiles_)
        arr.append(QJsonObject::fromVariantMap(v.toMap()));
    // QSaveFile：写一半断电不会留下损坏的 JSON —— 型号表损坏等于软件进不去
    QSaveFile f(path_);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    f.commit();
}
