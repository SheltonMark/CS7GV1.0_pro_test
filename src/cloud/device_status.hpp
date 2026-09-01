#pragma once

#include <QJsonValue>

constexpr int kDeviceStatusOffline = 0;
constexpr int kDeviceStatusOnline = 1;
constexpr int kDeviceStatusUnknown = 2;
constexpr int kDeviceStatusUnactivated = 3;

int normalizeTencentDeviceStatus(const QJsonValue &value);
