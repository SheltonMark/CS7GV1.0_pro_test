#include "device_status.hpp"

int normalizeTencentDeviceStatus(const QJsonValue &value)
{
    if (!value.isDouble())
        return kDeviceStatusUnknown;

    const int status = value.toInt(kDeviceStatusUnknown);
    if (status < kDeviceStatusOffline || status > kDeviceStatusUnactivated)
        return kDeviceStatusUnknown;
    return status;
}
