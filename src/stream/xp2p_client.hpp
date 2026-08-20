#pragma once

#include <QObject>
#include <QQmlEngine>
#include <QString>
#include <QTimer>

#include "tenda_cloud_client.hpp"

// 云拉流建联器（QML 单例）。CS6GV2.0 等无网口产品的调焦画面走这条路：
// 腾讯 XP2P SDK（app_interface.dll）在本机起一个 http-flv 转发服务，我们拿到
// 一个 http://127.0.0.1:PORT/ipc.flv?... 的**本机 URL**，再交给既有的
// VlcStreamPlayer 播放 —— 播放层与 XP2P 完全解耦（见 docs/拉流整合方案.md §3）。
//
// 建联序列照搬参考实现 D:\tendasecuritypc 的 TencentIotMgr / p2p_sample，四处
// 有意偏离（docs/拉流整合方案.md §7）：
//   1. DLL 用 LoadLibrary 动态加载而非链接导入库 —— 绕开 MSVC/MinGW 的 ABI
//      问题，且 SDK 缺失时优雅降级为"云拉流不可用"，不拖垮产测其余工位。
//   2. 就绪等待不用嵌套 QEventLoop（参考实现 waitXp2pReady 那样会在 QML 单线程
//      里引发重入/假死）—— 改为异步回调 + QTimer 超时。
//   3. start() 是异步两段式：先向腾达后台取 xp2p_info（TendaCloudClient），
//      拿到票据才 startService + setDeviceXp2pInfo。曾试过 SDK 自取
//      （setDeviceXp2pInfo(NULL)）想绕开后台登录，实测 rc=-1001 走不通 ——
//      自取查的是腾讯「物联网视频服务」，我们的设备在「物联网开发平台」。
//   4. app_id/app_key 不硬编码进业务逻辑，集中在一处常量 + 配置覆盖。
class Xp2pClient : public QObject {
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

    // Idle 未建联 / Connecting 建联中 / Playing 已就绪出 URL / Error 失败
    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(bool connecting READ connecting NOTIFY stateChanged)
    Q_PROPERTY(bool available READ available NOTIFY availableChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY errorTextChanged)
    Q_PROPERTY(QString liveUrl READ liveUrl NOTIFY liveUrlChanged)

public:
    enum State { Idle, Connecting, Playing, Error };
    Q_ENUM(State)

    explicit Xp2pClient(QObject *parent = nullptr);
    ~Xp2pClient() override;

    State state() const { return state_; }
    bool connecting() const { return state_ == Connecting; }
    // SDK 运行时是否加载成功（app_interface.dll 在不在、入口齐不齐）。
    // false 时按钮点了也白点，UI 据此提示"云拉流 SDK 未就绪"。
    bool available() const;
    QString errorText() const { return error_text_; }
    QString liveUrl() const { return live_url_; }

    // 建联并取直播 URL。productKey/deviceName 来自 cloud_config.json（经
    // CloudClient 暴露）。成功经 liveUrlReady 回来，失败经 errorTextChanged
    // + state=Error。重复调用同一设备则忽略。
    //
    // quality 只有两个在役取值：standard = 子码流，super = 主码流。别用
    // "high" —— 它只出现在腾讯 SDK 的通用 sample 里，参考实现（手机 APP 的
    // PC 版）的 mapLiveQuality() 从不发它。调焦默认 super：电池机空闲时子码
    // 流不一定在编，请求它会一直缓冲卡 0%，主码流才是确定在编的那一路。
    Q_INVOKABLE void start(const QString &productKey, const QString &deviceName,
                           const QString &quality = QStringLiteral("super"));
    // 停止建联并回收本机转发服务。切设备/离开工位/停止按钮都要调 ——
    // 同一设备的并发拉流有上限，不收会占着名额（docs/拉流整合方案.md §1.2）。
    Q_INVOKABLE void stop();

signals:
    void stateChanged();
    void availableChanged();
    void errorTextChanged();
    void liveUrlChanged();
    // 干净的本机 http-flv URL 已就绪，QML 把它塞给 LivePreview.sourceUrl
    void liveUrlReady(const QString &url);
    // 设备主动停推流 / 达到最大连接数被拒 / 链路断开 —— UI 应停播并提示
    void streamEnded(const QString &reason);

private:
    // XP2P 控制消息回调（SDK 线程触发）。static + 全局实例指针，回调里
    // 用 QMetaObject::invokeMethod 弹回本对象线程再处理（照搬参考实现）。
    static const char *msgCallback(const char *id, int type, const char *msg);
    void onXp2pMessage(const QString &deviceId, int type, const QString &msg);

    // 票据到手后的建联本体（startService + setDeviceXp2pInfo + 起超时）。
    // 与 start() 分开是因为取票据是异步的，不能在点按钮的那一刻阻塞 UI。
    void beginSession(const QString &xp2pInfo);

    void teardown();                 // 停服务、清状态，不改 state
    void setState(State s);
    void setErrorText(const QString &text);
    void fail(const QString &text);  // teardown + state=Error + errorText

    State state_ {Idle};
    QString error_text_;
    QString live_url_;

    // 当前在建/在播的设备标识（= deviceName，SDK 里的 id）。空 = 未建联。
    QString device_id_;
    // startService 是否真的成功过。device_id_ 早于异步取票据就已赋值，不能用它
    // 判断该不该 stopService。
    bool service_started_ {false};
    QString product_key_;
    QString quality_ {QStringLiteral("standard")};

    // 建联超时：DetectReady 迟迟不来就判失败（参考实现取 10s）
    QTimer timeout_timer_;

    // xp2p_info 的来源。取票据要走网络，故 start() 是异步两段式。
    TendaCloudClient tenda_;
};
