#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// 操作者授权表（**不是**密码库）。
//
// 身份与权限分开（2026-08-21 用户定案）：
//   身份 —— 腾达云负责。工人用自己的腾达账号（手机号+密码）登录，人事已经在维护
//           这份数据，离职即失效，全产线所有 PC 同时生效，不需要逐台删账号。
//   权限 —— 本表负责。只记"这个手机号在本软件里是什么角色"。
//
// ⚠️ 本表里**一个密码都不存**（连哈希都不存）—— 密码永远在腾达云那边校验。所以
//    accounts.json 随包发也没有可用于登录的东西，这正是选这套方案的理由。
//
// 登录 = 两步都过：
//   ① 腾达云验手机号+密码（失败就报云端的原因：密码错/未注册/账号停用）
//   ② 本表查 sha256(手机号) 拿 role —— 查不到就是"未获授权"，即使他有腾达账号
//   两种失败必须分开报：前者工人自己重试，后者得找管理员。
//
// 手机号存 sha256 而非明文：只为了"别在文件里明文存手机号"。这里不需要 PBKDF2 那种
// 抗爆破强度 —— 手机号空间本来就小，何况同一条记录里的 phoneMask 已经泄露了大部分
// 位。花 20 万轮在这里是白费。
class AccountStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // [{ phoneMask, role, name }]，给管理页显示。不含 phoneHash —— 界面不需要，
    // 少一处泄露面。
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)

public:
    explicit AccountStore(QObject *parent = nullptr);

    QVariantList accounts() const;

    // 云端已验过身份，这里只查授权。返回 { name, role, phoneMask }；
    // 未获授权返回空 map。
    Q_INVOKABLE QVariantMap authorize(const QString &phone) const;

    // 增/改。phone 已存在 = 改姓名/角色。返回空串 = 成功，否则是给界面的错误原因。
    Q_INVOKABLE QString upsert(const QString &phone, const QString &name,
                               const QString &role);
    // 改已有账号的姓名/角色，按**掩码**定位。
    // ⚠️ 必须有这个接口，不能拿掩码去调 upsert：upsert 会对传入的字符串算哈希，
    //    而掩码（138****8000）的哈希与原号不同 —— 那样会新增一条而不是修改。
    //    手机号本身不可改（表里只有哈希，原号取不回来），要换号只能移出再添加。
    Q_INVOKABLE QString updateByMask(const QString &phoneMask, const QString &name,
                                     const QString &role);

    // 删。⚠️ 拒绝删掉最后一个超级用户 —— 否则管理页再也进不去，产线上等于要重装。
    Q_INVOKABLE QString remove(const QString &phoneMask);

    // 掩码给界面显示（哈希不可逆，管理员得能认出这是谁）。138****8000 这种。
    Q_INVOKABLE static QString maskPhone(const QString &phone);

signals:
    void accountsChanged();

private:
    struct Account {
        QString phoneHash;
        QString phoneMask;
        QString role;      // super | engineer | tech
        QString name;
    };

    static QString hashPhone(const QString &phone);
    int indexOfHash(const QString &hash) const;
    int indexOfMask(const QString &mask) const;
    int superCount() const;
    void load();
    void save();
    // 预置管理员。交付包里就带这两条，所以新机器第一次登录必须是他们 ——
    // 不做"第一个登录的人自动成为管理员"，那样任何有腾达账号的人都能拿到管理员。
    // 换管理员就重新打个包（用户口径：几乎不换）。
    void seedBuiltinsIfMissing();

    QList<Account> accounts_;
    QString path_;
};
