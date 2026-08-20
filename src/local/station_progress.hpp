#pragma once

#include <QHash>
#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// 各工装卡在各工位的完成状态（顶栏设备浮层上的绿/红点）。
//
// 为什么本地存而不是每次问云：**写标识成功的那一刻我们本来就知道**（工位页回读
// 核对通过即为完成，见 ViewFocus / ViewFinished）。存本地只是为了软件重启后不丢，
// 不是为了获取这个信息 —— 所以这里一次云调用都不增加。
//
// 与设备真值的关系：设备侧的 FocusTime / SemiTime / FinishTime 才是权威。切设备时
// CloudClient.refreshInfo() 本来就会拉一次上报，那份应答里就带这三个时间戳，
// 用 syncFromDevice() 顺手校正即可 —— 同样零额外调用，且能自愈：
//   - 本地被删/换了台 PC → 一读上报就补回来
//   - 本地说做完了但设备上没有 → 以设备为准清掉，不让工人漏测
//
// key = productId + "/" + deviceName：不同产品的同名设备互不干扰（工装卡按产品
// 分组，理论上不会重名，但 key 带上产品更安全，也便于将来按产品清理）。
class StationProgress : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    explicit StationProgress(QObject *parent = nullptr);
    ~StationProgress() override;

    // station 用工位 key（focus/semi/finished/inspect/repair），与 profile 一致。
    Q_INVOKABLE bool isDone(const QString &productId, const QString &deviceName,
                           const QString &station) const;
    Q_INVOKABLE void setDone(const QString &productId, const QString &deviceName,
                             const QString &station, bool done);

    // 用设备上报的四个时间戳校正本地缓存。空字符串 = 设备上没有该标识。
    // 覆盖 focus/semi/finished/inspect —— 这四个工位设备侧都有对应标识，所以
    // 本地缓存永远能被校正回真值。repair 不在其中：维修不是"完成"语义，没有标识。
    Q_INVOKABLE void syncFromDevice(const QString &productId, const QString &deviceName,
                                    const QString &focusTime, const QString &semiTime,
                                    const QString &finishTime, const QString &inspectTime);

    // 换批次用：清掉某产品下所有设备的进度。工装卡下一批复用，不清会带着上一批
    // 的绿点，工人会以为已经测过（这是产线上最危险的一种误判）。
    Q_INVOKABLE void clearProduct(const QString &productId);

    // 本工位的下一台 = 从 after 之后起、按名单顺序找第一个「本工位未完成且在线」的
    // 设备；找不到就从头再找一轮（工人可能跳着放，别让它只能单向走到底）。
    // devices 传 CloudClient.devices（已按 deviceName 升序编好卡号）。
    // 返回空串 = 没有可去的下一台（全做完了，或剩下的都离线）。
    //
    // 为什么放 C++：跳过规则有三条（未完成、在线、绕回），写在 QML 里每个工位页
    // 都要复制一遍，且改一处漏一处。
    Q_INVOKABLE QString nextPending(const QString &productId, const QString &station,
                                    const QVariantList &devices,
                                    const QString &after) const;

signals:
    // 任何一格变化都发这个信号：浮层里十个点全靠它刷新，粒度不值得再细分。
    void changed();

private:
    static QString keyOf(const QString &productId, const QString &deviceName);
    void load();
    void save();

    // key → (station → done)
    QHash<QString, QHash<QString, bool>> done_;
    QString path_;
    bool dirty_ {false};
};
