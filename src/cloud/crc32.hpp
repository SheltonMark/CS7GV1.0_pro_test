#pragma once

#include <QByteArray>
#include <QChar>
#include <QString>

// zlib 兼容 CRC32（多项式 0xEDB88320，反射式），输出 8 位大写 hex。
//
// 用途 = 产测密钥校验口径（评审 §2.6）：设备不回密钥明文，只回
// SecretCrc32 = CRC32(DeviceSecret明文 + ProductSecret明文)；
// PC 用 InputData1 里的明文本地算同款 CRC32 比对，证明"写进去的就是这条"。
// CloudClient(比对) 与 MockTransport(模拟设备侧计算) 共用本实现。
inline quint32 PtestCrc32(const QByteArray &data)
{
    quint32 crc = 0xFFFFFFFFu;
    for (const unsigned char byte : data) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return crc ^ 0xFFFFFFFFu;
}

inline QString PtestCrc32Hex(const QString &text)
{
    return QString::number(PtestCrc32(text.toUtf8()), 16)
        .toUpper()
        .rightJustified(8, QLatin1Char('0'));
}
