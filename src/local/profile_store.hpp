#pragma once

#include <QObject>
#include <QString>
#include <QVariantList>
#include <QVariantMap>
#include <QtQml/qqmlregistration.h>

// 产品型号表（profile），落 exe 同目录 profiles.json。
//
// 原先硬编码在 MockData.qml 里 —— 加个型号要改 QML 再重新构建，产线和管理员都做不到。
// 现在超级用户/工程师能在产品选择页直接加（2026-08-21 用户定）。
//
// 一条 profile 的既定格式（沿用 MockData 里那套字段，不新造概念）：
//   name       显示名，也是 SN 的型号段（如 "CS7GV1.0"）
//   desc       一句话说明
//   productId  腾讯云 IoT Explorer 的 ProductId —— 设备名单、产测指令、拉流都靠它
//   enabled    false 时卡片置灰不可选（型号已停产/未就绪）
//   focusRtsp  调焦工位能否走 RTSP 直拉（有网口的裸机才能，装壳后一律走云）
//   items      本型号支持的测试项位（与物模型 SupportedItems 的位序一致）
//   stations   工位序列（key/title/sub），工位由产品决定，不同型号可以不同
//
// ⚠️ 首次运行时把 MockData 里那两条内置型号写进来（seedBuiltinsIfMissing），
//    否则升级到本版本的机器会看到一个空的产品选择页。
class ProfileStore : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    Q_PROPERTY(QVariantList profiles READ profiles NOTIFY profilesChanged)

public:
    explicit ProfileStore(QObject *parent = nullptr);

    QVariantList profiles() const { return profiles_; }

    // 增/改：按 **name** 定位，不是 productId。
    // ⚠️ 为什么不用 productId 当身份：现有两个型号 CS7GV1.0 与 CS6GV2.0 **共用同一个
    //    productId**（CS6G 暂借 CS7G 的测试产品，正式 id 还没拿到）。拿 productId
    //    当键会把两条当成同一条，改一个另一个跟着变。name 是型号名、也是 SN 的
    //    型号段，天然唯一。
    // 返回空串 = 成功，否则是给界面的错误原因。
    // stations 传 [{key,title,sub}]；items 传测试项位数组。
    Q_INVOKABLE QString upsert(const QVariantMap &profile);
    Q_INVOKABLE QString remove(const QString &name);

    // 新增时给界面的默认工位序列 —— 和现有两个型号一致，管理员不用手敲。
    Q_INVOKABLE QVariantList defaultStations() const;
    // 全部可选测试项（位 + 中文名），给新增界面勾选用
    Q_INVOKABLE QVariantList allItems() const;

signals:
    void profilesChanged();

private:
    int indexOf(const QString &name) const;
    void load();
    void save();
    void seedBuiltinsIfMissing();

    QVariantList profiles_;
    QString path_;
};
