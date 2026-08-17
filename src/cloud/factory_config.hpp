#pragma once

#include <QJsonObject>
#include <QObject>
#include <QQmlEngine>
#include <QVariantList>

// 工厂配置（exe 同目录 factory_config.json）：产线可调参数 + 管理员的
// 测试项勾选。缺文件/缺键一律用内置默认值——文件里只需要写想改的键。
//
// 与 cloud_config.json 刻意分开：那个是密钥（不进 git、不外传），
// 这个是工艺参数（随包发给工厂、允许产线自己改、进 git 存默认值）。
//
// 单例双入口：C++ 侧 instance()（CloudClient 取超时/轮询参数），
// QML 侧同一实例（QML_SINGLETON + create），改一处两边同时生效。
class FactoryConfig : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // —— 流程参数
    Q_PROPERTY(int shutdownDelaySec READ shutdownDelaySec NOTIFY configChanged)
    Q_PROPERTY(int pollIntervalMs READ pollIntervalMs NOTIFY configChanged)
    // 心跳超时:设备心跳 LastUpdate 距今超过该秒数 = 离线(腾讯云在线状态有
    // 延迟,在线判定以设备心跳包为准 —— 2026-08-17 需求)
    Q_PROPERTY(int heartbeatTimeoutSec READ heartbeatTimeoutSec NOTIFY configChanged)
    // —— 指令超时（普通/写flash类/外设/4G含切卡）
    Q_PROPERTY(int timeoutNormalMs READ timeoutNormalMs NOTIFY configChanged)
    Q_PROPERTY(int timeoutFlashMs READ timeoutFlashMs NOTIFY configChanged)
    Q_PROPERTY(int timeoutPeripheralMs READ timeoutPeripheralMs NOTIFY configChanged)
    Q_PROPERTY(int timeoutCellularMs READ timeoutCellularMs NOTIFY configChanged)
    // —— 外设测试参数
    Q_PROPERTY(int sdTestSizeMb READ sdTestSizeMb NOTIFY configChanged)
    Q_PROPERTY(int whiteBrightness READ whiteBrightness NOTIFY configChanged)
    Q_PROPERTY(int ledBlinkMs READ ledBlinkMs NOTIFY configChanged)
    Q_PROPERTY(int speakerRepeat READ speakerRepeat NOTIFY configChanged)
    // —— 调焦 RTSP 直连(带网口产品,如 CS7GV1.0):%1 = 设备 IP。
    //    RTSP 比上云快,但只有调焦工位能插网线(其余工位已套壳)。
    Q_PROPERTY(QString rtspUrlTemplate READ rtspUrlTemplate NOTIFY configChanged)
    // —— 调焦设备发现(CP3 老协议 UDP 广播搜索,DeviceDiscovery 用)
    Q_PROPERTY(int discoverySendPort READ discoverySendPort NOTIFY configChanged)
    Q_PROPERTY(int discoveryListenPort READ discoveryListenPort NOTIFY configChanged)
    Q_PROPERTY(QString discoveryWord READ discoveryWord NOTIFY configChanged)
    Q_PROPERTY(int discoveryIntervalMs READ discoveryIntervalMs NOTIFY configChanged)

public:
    explicit FactoryConfig(QObject *parent = nullptr);

    static FactoryConfig *instance();
    static FactoryConfig *create(QQmlEngine *engine, QJSEngine *scriptEngine);

    int shutdownDelaySec() const;
    int pollIntervalMs() const;
    int heartbeatTimeoutSec() const;
    int timeoutNormalMs() const;
    int timeoutFlashMs() const;
    int timeoutPeripheralMs() const;
    int timeoutCellularMs() const;
    int sdTestSizeMb() const;
    int whiteBrightness() const;
    int ledBlinkMs() const;
    int speakerRepeat() const;
    QString rtspUrlTemplate() const;
    int discoverySendPort() const;
    int discoveryListenPort() const;
    QString discoveryWord() const;
    int discoveryIntervalMs() const;

    // 测试项勾选：productId × station("semi"/"finished") × group("auto"/"manual")。
    // auto 组的值 = 测试项位号(int)，manual 组 = 判定条目 key(string)。
    // 从未配置过该组 ⇒ 返回 fallback（调用方给"全选"缺省，语义 = 不配就全测）。
    Q_INVOKABLE QVariantList stationItems(const QString &productId, const QString &station,
                                          const QString &group,
                                          const QVariantList &fallback) const;

    // 管理员面板保存勾选（立即落盘 + 通知全部绑定方）
    Q_INVOKABLE void setStationItems(const QString &productId, const QString &station,
                                     const QString &group, const QVariantList &values);

    Q_INVOKABLE void reload();

signals:
    void configChanged();

private:
    void load();
    bool save();
    QString filePath() const;
    int topInt(const char *key, int fallback) const;
    int nestedInt(const char *section, const char *key, int fallback) const;
    QString topString(const char *key, const char *fallback) const;

    QJsonObject root_;
};
