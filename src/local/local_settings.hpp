#pragma once

#include <QObject>
#include <QSettings>
#include <QString>
#include <QtQml/qqmlregistration.h>

// 本机偏好（只属于这台电脑，**绝不随软件包发出去**）。
//
// 为什么不能用"exe 同目录的 json"那套：本项目其余配置（cloud_config.json /
// factory_config.json / station_progress.json）都放 exe 同目录，因为它们是
// **现场配置**，要跟着包一起发、也要能被工人看到和改。但"上次登录的工号"是
// 操作员个人痕迹 —— 放同目录就会被 build.sh 打进 dist、再随 zip 发给别人，
// 别人一打开看到的是我的工号（2026-08-21 实际发生）。
//
// 所以用 QSettings：Windows 上落到当前用户的注册表
// HKCU\Software\Tenda\ProductTest，换台机器/换个账户自然是空的，也不会进 zip。
class LocalSettings : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit LocalSettings(QObject *parent = nullptr);

    // 上次登录的工号。空串 = 没记过（首次运行 / 关掉了"记住工号"）。
    Q_INVOKABLE QString rememberedUserId() const;
    // remember=false 时**清掉**已存的值，不是只停止写入 —— 工人取消勾选的意思是
    // "别在这台机器上留我的工号"，留着旧值等于没取消。
    Q_INVOKABLE void setRememberedUserId(const QString &id, bool remember);
    Q_INVOKABLE bool rememberEnabled() const;

private:
    QSettings settings_;
};
