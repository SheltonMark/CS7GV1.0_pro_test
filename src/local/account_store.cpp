#include "account_store.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QSaveFile>

namespace {

QString StorePath()
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/accounts.json");
}

bool RoleValid(const QString &role)
{
    return role == QLatin1String("super") || role == QLatin1String("engineer")
           || role == QLatin1String("tech");
}

// 预置管理员（2026-08-21 用户给定）。写死在这里而不是配置文件里：配置文件能被现场
// 改，那等于谁都能给自己开管理员。换人就重新打包 —— 用户口径是几乎不换。
struct Builtin { const char *phone; const char *name; const char *role; };
constexpr Builtin kBuiltins[] = {
    {"18868110537", "超级管理员", "super"},
    {"18813932014", "工程师",     "engineer"},
};

} // namespace

AccountStore::AccountStore(QObject *parent)
    : QObject(parent)
    , path_(StorePath())
{
    load();
    seedBuiltinsIfMissing();
}

QString AccountStore::hashPhone(const QString &phone)
{
    return QString::fromLatin1(
        QCryptographicHash::hash(phone.trimmed().toUtf8(),
                                 QCryptographicHash::Sha256).toHex());
}

QString AccountStore::maskPhone(const QString &phone)
{
    const QString p = phone.trimmed();
    if (p.size() < 7)
        return p;                       // 短号/非手机号：原样显示，掩码没有意义
    return p.left(3) + QStringLiteral("****") + p.right(4);
}

int AccountStore::indexOfHash(const QString &hash) const
{
    for (int i = 0; i < accounts_.size(); ++i)
        if (accounts_.at(i).phoneHash == hash)
            return i;
    return -1;
}

int AccountStore::indexOfMask(const QString &mask) const
{
    for (int i = 0; i < accounts_.size(); ++i)
        if (accounts_.at(i).phoneMask == mask)
            return i;
    return -1;
}

int AccountStore::superCount() const
{
    int n = 0;
    for (const Account &a : accounts_)
        if (a.role == QLatin1String("super"))
            ++n;
    return n;
}

QVariantList AccountStore::accounts() const
{
    QVariantList out;
    for (const Account &a : accounts_) {
        out.append(QVariantMap{
            {QStringLiteral("phoneMask"), a.phoneMask},
            {QStringLiteral("role"), a.role},
            {QStringLiteral("name"), a.name},
        });
    }
    return out;
}

QVariantMap AccountStore::authorize(const QString &phone) const
{
    const int i = indexOfHash(hashPhone(phone));
    if (i < 0)
        return QVariantMap();
    const Account &a = accounts_.at(i);
    // id 用掩码：Session.user.id 会显示在顶栏，不该摆完整手机号
    return QVariantMap{
        {QStringLiteral("id"), a.phoneMask},
        {QStringLiteral("name"), a.name},
        {QStringLiteral("role"), a.role},
        {QStringLiteral("phoneMask"), a.phoneMask},
    };
}

QString AccountStore::upsert(const QString &phone, const QString &name,
                             const QString &role)
{
    const QString p = phone.trimmed();
    if (p.isEmpty())
        return QStringLiteral("手机号不能为空");
    if (name.trimmed().isEmpty())
        return QStringLiteral("姓名不能为空");
    if (!RoleValid(role))
        return QStringLiteral("角色无效");

    const QString hash = hashPhone(p);
    const int i = indexOfHash(hash);

    // 不许把最后一个超级用户降级 —— 与 remove() 同一道门
    if (i >= 0 && accounts_.at(i).role == QLatin1String("super")
        && role != QLatin1String("super") && superCount() <= 1) {
        return QStringLiteral("至少要保留一个超级用户");
    }

    Account a;
    a.phoneHash = hash;
    a.phoneMask = maskPhone(p);
    a.name = name.trimmed();
    a.role = role;
    if (i >= 0)
        accounts_[i] = a;
    else
        accounts_.append(a);
    save();
    emit accountsChanged();
    return QString();
}

QString AccountStore::updateByMask(const QString &phoneMask, const QString &name,
                                   const QString &role)
{
    if (name.trimmed().isEmpty())
        return QStringLiteral("姓名不能为空");
    if (!RoleValid(role))
        return QStringLiteral("角色无效");

    const int i = indexOfMask(phoneMask);
    if (i < 0)
        return QStringLiteral("账号不存在");

    // 同 upsert：不许把最后一个超级用户降级，否则管理页进不去了
    if (accounts_.at(i).role == QLatin1String("super")
        && role != QLatin1String("super") && superCount() <= 1) {
        return QStringLiteral("至少要保留一个超级用户");
    }

    // 只改姓名与角色，phoneHash/phoneMask 原样保留
    accounts_[i].name = name.trimmed();
    accounts_[i].role = role;
    save();
    emit accountsChanged();
    return QString();
}

QString AccountStore::remove(const QString &phoneMask)
{
    // 按掩码删：界面上只有掩码（哈希不给 QML，少一处泄露面）。
    // 掩码理论上可能重复（同前三位+同后四位），概率极低；真撞上就删到第一条，
    // 管理员会看到列表没如期变化并重试 —— 不值得为此把哈希暴露给界面。
    const int i = indexOfMask(phoneMask);
    if (i < 0)
        return QStringLiteral("账号不存在");
    if (accounts_.at(i).role == QLatin1String("super") && superCount() <= 1)
        return QStringLiteral("至少要保留一个超级用户");
    accounts_.removeAt(i);
    save();
    emit accountsChanged();
    return QString();
}

void AccountStore::seedBuiltinsIfMissing()
{
    bool touched = false;
    for (const Builtin &b : kBuiltins) {
        const QString phone = QString::fromUtf8(b.phone);
        if (indexOfHash(hashPhone(phone)) >= 0)
            continue;                    // 已在表里（可能被改过姓名/角色，不动）
        Account a;
        a.phoneHash = hashPhone(phone);
        a.phoneMask = maskPhone(phone);
        a.name = QString::fromUtf8(b.name);
        a.role = QString::fromUtf8(b.role);
        accounts_.append(a);
        touched = true;
    }
    if (!touched)
        return;
    save();
    emit accountsChanged();
}

void AccountStore::load()
{
    QFile f(path_);
    if (!f.open(QIODevice::ReadOnly))
        return;                          // 首次运行没有文件，不是错误
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Account a;
        a.phoneHash = o.value(QStringLiteral("phoneHash")).toString();
        a.phoneMask = o.value(QStringLiteral("phoneMask")).toString();
        a.role = o.value(QStringLiteral("role")).toString();
        a.name = o.value(QStringLiteral("name")).toString();
        if (!a.phoneHash.isEmpty() && RoleValid(a.role))
            accounts_.append(a);
    }
}

void AccountStore::save()
{
    QJsonArray arr;
    for (const Account &a : accounts_) {
        arr.append(QJsonObject{
            {QStringLiteral("phoneHash"), a.phoneHash},
            {QStringLiteral("phoneMask"), a.phoneMask},
            {QStringLiteral("role"), a.role},
            {QStringLiteral("name"), a.name},
        });
    }
    // QSaveFile：写一半断电不会留下损坏的 JSON —— 授权表损坏等于所有人登不进去
    QSaveFile f(path_);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    f.commit();
}
