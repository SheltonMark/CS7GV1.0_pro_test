#pragma once

#include <QJsonObject>
#include <QString>

#include "cloud_reply.hpp"

// PC→云 传输接口。实现渐进替换（架构定案 2026-08-17）：
//   MockTransport       本地假设备——没有密钥/真机时 UI 与指令闭环即可联调
//   TencentApiTransport 腾讯云 API 3.0 直连（跳过腾达后台的打通期方案）
//   （规划）TendaBackendTransport 走公司后台，接鉴权时新增，上层零改动
//
// 语义约定：
// - invokeAction：物模型 action 下发。回调 ok 只代表「云端已受理」；真正的
//   执行结果走 readDeviceData 轮询 ProductTestResult（按 RequestId 关联）——
//   两级应答，别混。
// - readDeviceData：读设备最新上报属性。data 规格化为
//     { "<PropertyId>": {"Value": <值>, "LastUpdate": <ms>}, ... }
//   与腾讯 DescribeDeviceData 的 Data 字段同构；Mock 也产出同一形状，
//   这样轮询代码对两种传输一字不改。
// - describeDevices：列该产品下的设备名单 + 实时状态。data 规格化为
//     { "devices": [ {"deviceName": "...", "status": 0|1|2|3,
//                       "online": true|false}, ... ] }
//   status：0=离线、1=在线、2=状态未知、3=未激活。online 是兼容上层流程的派生值。
//   腾讯 DescribeDevices 只负责拿名单（其 Status 实测为 null），实现层会并发调用
//   DescribeDevice 补齐每台状态；不要用 readDeviceData 的心跳年龄冒充云端在线状态。
class ICloudTransport {
public:
    virtual ~ICloudTransport() = default;

    virtual QString name() const = 0;

    virtual void invokeAction(const QString &productId, const QString &deviceName,
                              const QString &actionId, const QJsonObject &inputParams,
                              CloudReplyHandler done) = 0;

    virtual void readDeviceData(const QString &productId, const QString &deviceName,
                                CloudReplyHandler done) = 0;

    virtual void describeDevices(const QString &productId, CloudReplyHandler done) = 0;
};
