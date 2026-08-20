#pragma once

#include <QHash>
#include <QJsonArray>
#include <QJsonObject>
#include <QObject>
#include <QStringList>

#include "i_cloud_transport.hpp"

// 本地假设备：不出网，在内存里维护一台"设备"的产测状态。
//
// 意义：没有云 API 密钥、没有真机时，UI/指令流水/轮询闭环就能完整联调；
// 也是断网演示/培训的兜底。行为对齐设备端 ProductTestService 的语义
// （受理与执行分离、单结果槽、CS7G 能力位图），让上层代码对 Mock 与真云一字不改。
class MockTransport : public QObject, public ICloudTransport {
    Q_OBJECT

public:
    explicit MockTransport(QObject *parent = nullptr);

    QString name() const override { return QStringLiteral("mock"); }

    void invokeAction(const QString &productId, const QString &deviceName,
                      const QString &actionId, const QJsonObject &inputParams,
                      CloudReplyHandler done) override;

    void readDeviceData(const QString &productId, const QString &deviceName,
                        CloudReplyHandler done) override;

    void describeDevices(const QString &productId, CloudReplyHandler done) override;

private:
    void execute(const QString &actionId, const QJsonObject &p);
    void setResult(int requestId, int command, int item, int code, const QString &detail);
    static QString nowStamp17();

    // 假设备状态（字段名与物模型 ProductTestInfo / ProductTestResult 一致）
    // ⚠️ 假设备状态要**按 deviceName 隔离**。
    //    早先只有一份 info_/result_ 且把 deviceName 参数整个忽略掉，十台假设备
    //    共用同一份 —— 在 01 号写完调焦标识后切到 02 号，读上报拿到的还是那份带
    //    FocusTime 的数据，于是 02 号也被判成"本工位已完成"：绿点误亮，自动跳台
    //    也因为"全都做完了"而不动。多设备一上来就暴露了这个假设。
    //
    //    做法是"换入换出"而不是把 info_ 改成 map：execute()/setResult() 等内部
    //    函数全都直接操作 info_/result_/logLines_，改成 map 要动一大片、容易引入
    //    新错。入口处按 deviceName 切换：与上次不同就先把当前状态存回 saved_，
    //    再把目标设备的状态取出来 —— 内部函数一行不用改。
    struct DeviceState {
        QJsonObject info;
        QJsonObject result;
        bool hasResult {false};
        int heartbeat {0};
        QStringList logLines;
        int logSeq {1};
    };
    QHash<QString, DeviceState> saved_;
    QString current_;
    void switchTo(const QString &deviceName);

    // 假设备状态（字段名与物模型 ProductTestInfo / ProductTestResult 一致）
    QJsonObject info_;
    QJsonObject result_;
    bool hasResult_ {false};
    int heartbeat_ {0};   // 每次读上报自增，模拟固件 5s 一拍的心跳计数
    // 阶段4 日志展示假数据（物模型 v3：PtestLastError / PtestLogTail）
    QJsonObject lastError_;  // 固定一条"上云失败"样例——真机语义=最近一条非指令类失败，粘滞
    QStringList logLines_;   // ptest.log 尾部；每执行一条指令追加一行
    int logSeq_ {1};         // Text 每变一次自增——QML 靠它决定要不要刷新文本

    // ── 假名单：模拟"10 台工装卡同时上线" ──────────────────────────────
    // 为什么需要：真云那边名单是真的（10 张卡的 device_name 早就建在控制台上），
    // 但台面上只有 1 台通电，查出来是"1 在线 + 9 离线"，验不了满载时的版面 ——
    // 尤其"不许滚动"这条在 10 台全在线时才见真章。
    // 环境变量 PTEST_MOCK_DEVICES 可覆盖台数（默认 10），
    // PTEST_MOCK_OFFLINE 指定哪几号离线（逗号分隔，如 "3,7"），用来验混合态。
    QJsonArray roster_;
    void buildRoster();
};
