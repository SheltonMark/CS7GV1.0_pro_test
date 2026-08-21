#include "operator_login.hpp"

#include "account_store.hpp"
#include "stream_log.hpp"

OperatorLogin::OperatorLogin(QObject *parent)
    : QObject(parent)
{
    // 只为了拿 domain（cloud_config.json 的 tenda.domain）。其中的 account/password
    // 是取票据用的，这里一概不碰。
    cloud_.loadConfig();
}

void OperatorLogin::setBusy(bool value)
{
    if (busy_ == value)
        return;
    busy_ = value;
    emit busyChanged();
}

void OperatorLogin::login(const QString &phone, const QString &password)
{
    const QString p = phone.trimmed();
    if (p.isEmpty() || password.isEmpty()) {
        emit failed(QStringLiteral("请输入手机号和密码"));
        return;
    }
    if (busy_)
        return;                 // 防连点：云端往返 1~3 秒，期间按钮已置灰，这里再兜一层

    // ⚠️ 先查本地授权、再走云端，顺序是有意的：
    //    没被授权的人根本不该产生一次云端登录请求（那是对腾达云的无谓打扰，也会把
    //    未授权者的密码送出去）。代价是"未授权"的提示比"密码错"更早出现 —— 这不算
    //    信息泄露：授权表本来就随包发，谁在表里不是秘密。
    const QVariantMap authorized = AccountStore().authorize(p);
    if (authorized.isEmpty()) {
        StreamLog::append(QStringLiteral("[登录] 未授权的手机号（掩码 %1）")
                              .arg(AccountStore::maskPhone(p)));
        emit failed(QStringLiteral("该账号未获授权，请联系管理员添加"));
        return;
    }

    setBusy(true);
    StreamLog::append(QStringLiteral("[登录] 向腾达云验证身份（掩码 %1）")
                          .arg(AccountStore::maskPhone(p)));
    // keepAsSession=true：登录成功后，取 xp2p_info 一律用这位登录者的身份 ——
    // cloud_config.json 里不再需要账号密码（2026-08-21 用户定案）。
    cloud_.verifyCredential(p, password, true,
                            [this, authorized](bool ok, const QString &err) {
        setBusy(false);
        if (!ok) {
            StreamLog::append(QStringLiteral("[登录] 云端验证失败：") + err);
            emit failed(err);
            return;
        }
        StreamLog::append(QStringLiteral("[登录] 通过，角色 %1")
                              .arg(authorized.value(QStringLiteral("role")).toString()));
        emit succeeded(authorized);
    });
}
