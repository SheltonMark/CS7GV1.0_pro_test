#include "device_status.hpp"

#include <QJsonValue>

#include <cstdio>

namespace {

bool expectStatus(const QJsonValue &input, int expected, const char *caseName)
{
    const int actual = normalizeTencentDeviceStatus(input);
    if (actual == expected)
        return true;

    std::fprintf(stderr, "%s: expected %d, got %d\n", caseName, expected, actual);
    return false;
}

} // namespace

int main()
{
    bool ok = true;
    ok = expectStatus(QJsonValue(0), kDeviceStatusOffline, "offline") && ok;
    ok = expectStatus(QJsonValue(1), kDeviceStatusOnline, "online") && ok;
    ok = expectStatus(QJsonValue(2), kDeviceStatusUnknown, "cloud lookup failed") && ok;
    ok = expectStatus(QJsonValue(3), kDeviceStatusUnactivated, "unactivated") && ok;
    ok = expectStatus(QJsonValue(QJsonValue::Null), kDeviceStatusUnknown, "null") && ok;
    ok = expectStatus(QJsonValue(QJsonValue::Undefined), kDeviceStatusUnknown,
                      "missing") && ok;
    ok = expectStatus(QJsonValue(99), kDeviceStatusUnknown, "out of range") && ok;
    ok = expectStatus(QJsonValue(QStringLiteral("1")), kDeviceStatusUnknown,
                      "wrong JSON type") && ok;
    return ok ? 0 : 1;
}
