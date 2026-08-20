#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QtQml/qqmlregistration.h>

// 操作者账号库（工号 + 姓名 + 角色 + 密码哈希），落 exe 同目录 accounts.json。
//
// 为什么密码存哈希而不是明文：这个文件**随软件包发给所有工位**，而账号权限是有实际
// 后果的 —— canSkipItem（跳过测试项）、云调试页（能下发任意物模型 action）。明文
// 等于所有人拿到包就拿到全部权限。
//   PBKDF2-HMAC-SHA256，每账号独立 16 字节 salt，20 万轮。
//   轮数取值理由：产线机多为低配，20 万轮在 i3 上约 60~90ms，登录时人感觉不到，
//   而离线爆破成本比明文/单轮 MD5 高数个量级。
//
// 为什么不能手工改这个文件：密码是哈希，没人能手算。增删账号走软件内的管理界面
// （超级用户可见）。换台 PC 就把 accounts.json 拷过去 —— 用户 2026-08-21 定的口径。
//
// ⚠️ 不进 git（含哈希与工号，属于人员信息），按 cloud_config.json 那套：
//    .gitignore 挡住 + build.sh 构建时回抄仓库根做备份。
class AccountStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // 账号列表（不含哈希/salt）：[{ id, name, role }]，给管理界面显示
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    // 库里一个账号都没有 = 首次运行，要强制建超级用户
    Q_PROPERTY(bool empty READ empty NOTIFY accountsChanged)

public:
    explicit AccountStore(QObject *parent = nullptr);

    QVariantList accounts() const;
    bool empty() const;

    // 登录校验。成功返回 { id, name, role }；失败返回空 map。
    // ⚠️ 不区分"工号不存在"与"密码错" —— 都回空，界面统一提示"工号或密码不正确"。
    //    区分开等于告诉试密码的人哪些工号是有效的。
    Q_INVOKABLE QVariantMap verify(const QString &id, const QString &password) const;

    // 增/改。id 已存在 = 改（密码留空则不动密码，只改姓名/角色）。
    // 返回空串 = 成功；否则是给界面显示的错误原因。
    Q_INVOKABLE QString upsert(const QString &id, const QString &name,
                               const QString &role, const QString &password);
    // 删。返回空串 = 成功。⚠️ 拒绝删掉最后一个超级用户 —— 否则账号库会锁死，
    //    没人能再进管理界面（产线上等于要重装）。
    Q_INVOKABLE QString remove(const QString &id);

    // 首启迁移：把早先写在 QML 里的三个 mock 账号搬成正式账号，沿用工号与姓名，
    // 密码统一 1234（用户 2026-08-21 定）。只在库为空时执行一次。
    Q_INVOKABLE void migrateLegacyIfEmpty();

signals:
    void accountsChanged();

private:
    struct Account {
        QString id;
        QString name;
        QString role;      // super | engineer | tech
        QByteArray salt;   // 原始字节
        QByteArray hash;   // 原始字节
    };

    static QByteArray derive(const QString &password, const QByteArray &salt);
    static bool constantTimeEquals(const QByteArray &a, const QByteArray &b);
    int indexOf(const QString &id) const;
    int superCount() const;
    void load();
    void save();

    QList<Account> accounts_;
    QString path_;
};
