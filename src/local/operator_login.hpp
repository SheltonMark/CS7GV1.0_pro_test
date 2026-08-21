#pragma once

#include <QObject>
#include <QString>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

#include "account_store.hpp"
#include "tenda_cloud_client.hpp"

// 操作者登录：腾达云验身份 + 本地授权表查角色（2026-08-21 定案）。
//
// 为什么要这一层：TendaCloudClient 是 Xp2pClient 的内部成员、没有暴露给 QML，而它
// 现有的 login() 用的是 cloud_config.json 里那对**取票据**用的固定凭据 —— 与"工人
// 当场输入的手机号密码"完全是两回事。这里持有自己的 TendaCloudClient 实例，只用它的
// verifyCredential()（不缓存 token，不碰取票据那条链）。
//
// 两步都过才算登录成功，失败原因必须分开报：
//   云端失败 → 密码错 / 未注册 / 账号停用，工人自己能处理
//   本地未授权 → 有腾达账号但没被加进本软件，必须找管理员
// 混成一句"登录失败"会让工人和管理员互相推。
class OperatorLogin : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit OperatorLogin(QObject *parent = nullptr);

    bool busy() const { return busy_; }

    // 发起登录。结果走 succeeded/failed 信号 —— 云端往返要 1~3 秒，不能同步等。
    Q_INVOKABLE void login(const QString &phone, const QString &password);

    // 退出登录：清掉进程级云身份 token。**必须调**，不能只清 Session.user ——
    // 登录 token 供取拉流票据用，不清等于"已退出的人的云身份"还在被软件使用。
    Q_INVOKABLE void logout();

signals:
    void busyChanged();
    // user = { id(掩码), name, role, phoneMask }，可直接赋给 Session.user
    void succeeded(const QVariantMap &user);
    void failed(const QString &reason);

private:
    void setBusy(bool value);

    TendaCloudClient cloud_;
    // 成员而非每次临时构造：AccountStore 的构造会重读 accounts.json 并重跑一次
    // 预置检查，每次登录都来一遍是白花的 I/O。
    AccountStore store_;
    bool busy_ {false};
};
