#include "account_store.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QFile>
#include <QJsonArray>
#include <QMessageAuthenticationCode>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QSaveFile>
#include <QVariantMap>

namespace {

constexpr int kIterations = 200000;
constexpr int kSaltBytes = 16;
constexpr int kKeyBytes = 32;

QString StorePath()
{
    return QCoreApplication::applicationDirPath() + QStringLiteral("/accounts.json");
}

bool RoleValid(const QString &role)
{
    return role == QLatin1String("super") || role == QLatin1String("engineer")
           || role == QLatin1String("tech");
}

} // namespace

AccountStore::AccountStore(QObject *parent)
    : QObject(parent)
    , path_(StorePath())
{
    load();
}

// PBKDF2-HMAC-SHA256。Qt 没有现成的 PBKDF2，按 RFC 8018 手写 —— 只需要
// dkLen <= hLen 的情形（32 字节），所以只算第一个块，不用拼接循环。
QByteArray AccountStore::derive(const QString &password, const QByteArray &salt)
{
    const QByteArray pwd = password.toUtf8();
    QByteArray block = salt;
    block.append(char(0)).append(char(0)).append(char(0)).append(char(1));  // INT(1)

    QByteArray u = QMessageAuthenticationCode::hash(
        block, pwd, QCryptographicHash::Sha256);
    QByteArray result = u;
    for (int i = 1; i < kIterations; ++i) {
        u = QMessageAuthenticationCode::hash(u, pwd, QCryptographicHash::Sha256);
        for (int j = 0; j < result.size(); ++j)
            result[j] = result[j] ^ u[j];
    }
    return result.left(kKeyBytes);
}

// 逐字节全比完再返回，不提前 break —— 提前退出会让比较耗时随"前几位对了多少"变化，
// 那是可测量的侧信道。产线场景威胁不高，但这个写法不额外花成本。
bool AccountStore::constantTimeEquals(const QByteArray &a, const QByteArray &b)
{
    if (a.size() != b.size())
        return false;
    unsigned char diff = 0;
    for (int i = 0; i < a.size(); ++i)
        diff |= static_cast<unsigned char>(a[i] ^ b[i]);
    return diff == 0;
}

int AccountStore::indexOf(const QString &id) const
{
    for (int i = 0; i < accounts_.size(); ++i)
        if (accounts_.at(i).id == id)
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
            {QStringLiteral("id"), a.id},
            {QStringLiteral("name"), a.name},
            {QStringLiteral("role"), a.role},
        });
    }
    return out;
}

bool AccountStore::empty() const
{
    return accounts_.isEmpty();
}

QVariantMap AccountStore::verify(const QString &id, const QString &password) const
{
    const int i = indexOf(id);
    if (i < 0)
        return QVariantMap();
    const Account &a = accounts_.at(i);
    if (!constantTimeEquals(derive(password, a.salt), a.hash))
        return QVariantMap();
    return QVariantMap{
        {QStringLiteral("id"), a.id},
        {QStringLiteral("name"), a.name},
        {QStringLiteral("role"), a.role},
    };
}

QString AccountStore::upsert(const QString &id, const QString &name,
                             const QString &role, const QString &password)
{
    const QString trimmedId = id.trimmed();
    if (trimmedId.isEmpty())
        return QStringLiteral("工号不能为空");
    if (name.trimmed().isEmpty())
        return QStringLiteral("姓名不能为空");
    if (!RoleValid(role))
        return QStringLiteral("角色无效");

    const int i = indexOf(trimmedId);
    if (i < 0 && password.isEmpty())
        return QStringLiteral("新建账号必须设密码");

    // 不许把最后一个超级用户降级 —— 与 remove() 同一道门，否则管理界面进不去了
    if (i >= 0 && accounts_.at(i).role == QLatin1String("super")
        && role != QLatin1String("super") && superCount() <= 1) {
        return QStringLiteral("至少要保留一个超级用户");
    }

    Account a;
    if (i >= 0)
        a = accounts_.at(i);
    a.id = trimmedId;
    a.name = name.trimmed();
    a.role = role;
    if (!password.isEmpty()) {
        a.salt.resize(kSaltBytes);
        QRandomGenerator::system()->generate(
            reinterpret_cast<quint32 *>(a.salt.data()),
            reinterpret_cast<quint32 *>(a.salt.data() + kSaltBytes));
        a.hash = derive(password, a.salt);
    }

    if (i >= 0)
        accounts_[i] = a;
    else
        accounts_.append(a);
    save();
    emit accountsChanged();
    return QString();
}

QString AccountStore::remove(const QString &id)
{
    const int i = indexOf(id);
    if (i < 0)
        return QStringLiteral("账号不存在");
    if (accounts_.at(i).role == QLatin1String("super") && superCount() <= 1)
        return QStringLiteral("至少要保留一个超级用户");
    accounts_.removeAt(i);
    save();
    emit accountsChanged();
    return QString();
}

void AccountStore::migrateLegacyIfEmpty()
{
    if (!accounts_.isEmpty())
        return;
    // 早先写在 MockData.qml 里的三个账号。沿用工号与姓名，密码统一 1234
    //（用户 2026-08-21 定）—— 产线已经在用这几个工号，换掉等于要重新培训。
    struct Legacy { const char *id; const char *name; const char *role; };
    static const Legacy kLegacy[] = {
        {"0045009", "马顺涛", "super"},
        {"0038165", "肖洁", "engineer"},
        {"9000001", "示例技术员", "tech"},
    };
    for (const Legacy &l : kLegacy) {
        upsert(QString::fromUtf8(l.id), QString::fromUtf8(l.name),
               QString::fromUtf8(l.role), QStringLiteral("1234"));
    }
}

void AccountStore::load()
{
    QFile f(path_);
    if (!f.open(QIODevice::ReadOnly))
        return;                      // 首次运行没有文件，不是错误
    const QJsonArray arr = QJsonDocument::fromJson(f.readAll()).array();
    for (const QJsonValue &v : arr) {
        const QJsonObject o = v.toObject();
        Account a;
        a.id = o.value(QStringLiteral("id")).toString();
        a.name = o.value(QStringLiteral("name")).toString();
        a.role = o.value(QStringLiteral("role")).toString();
        a.salt = QByteArray::fromBase64(
            o.value(QStringLiteral("salt")).toString().toLatin1());
        a.hash = QByteArray::fromBase64(
            o.value(QStringLiteral("hash")).toString().toLatin1());
        if (!a.id.isEmpty() && RoleValid(a.role) && !a.salt.isEmpty()
            && !a.hash.isEmpty())
            accounts_.append(a);
    }
}

void AccountStore::save()
{
    QJsonArray arr;
    for (const Account &a : accounts_) {
        arr.append(QJsonObject{
            {QStringLiteral("id"), a.id},
            {QStringLiteral("name"), a.name},
            {QStringLiteral("role"), a.role},
            {QStringLiteral("salt"), QString::fromLatin1(a.salt.toBase64())},
            {QStringLiteral("hash"), QString::fromLatin1(a.hash.toBase64())},
        });
    }
    // QSaveFile：写一半断电不会留下损坏的 JSON —— 账号库损坏等于所有人登不进去
    QSaveFile f(path_);
    if (!f.open(QIODevice::WriteOnly))
        return;
    f.write(QJsonDocument(arr).toJson(QJsonDocument::Indented));
    f.commit();
}
