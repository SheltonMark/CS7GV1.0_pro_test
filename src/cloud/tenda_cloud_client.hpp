#pragma once

#include <QByteArray>
#include <QNetworkAccessManager>
#include <QObject>
#include <QString>

#include <functional>

// 腾达后台取 xp2p_info。云拉流绕不开这一步：
//
// xp2p_info 是设备的**每会话 P2P 票据**（形似 token，每次拉流都变），XP2P SDK
// 拿它才有到设备的路由。曾试过让 SDK 自取（setQcloudApiCred + setDeviceXp2pInfo
// (NULL)），实测 rc=-1001 —— SDK 自取查的是腾讯「物联网视频服务」，而我们的
// 设备在「物联网开发平台」(IoT Explorer)，两个平台的产品空间不重叠，自取必然
// 落空。日志实证见 README 第 26 条。小程序拉流要人工粘贴的那串就是它。
//
// 接口契约照抄参考实现 D:\tendasecuritypc（RequestManage::GetXP2PINFO）：
//   GET  <domain>/td/td-device-api/se-device/p2pToken/get/v1?product_key=..&sn=..
//   头   sig = md5(Terminal + ts + SIGSALT)、Authorization: Bearer <access_token>、
//        Provider: C，以及 App-Id / Project-Id / AppSource / pcv / AppVersion
//   回   code==0 时取 data.value
// 实测：少了 Authorization 报 100012「Header头部信息有误」（不是签名的问题，
// 别被这句话带偏去查 sig）；带上格式合法但无效的 token 则报 100412
//「Token解析失败」—— 说明头齐了，只差真 token。
//
// access_token 要账号密码换（check/v2 查 encrypt_mode → password/v2 换 token）。
// 产测工具原本没有腾达云账号（ViewLogin 那套是工位口令，与云账号无关），
// 所以账号密码和域名都放 cloud_config.json 的 "tenda" 段，不硬编码、不进 git。
class TendaCloudClient : public QObject {
    Q_OBJECT

public:
    explicit TendaCloudClient(QObject *parent = nullptr);

    // 结果回调：ok=false 时 valueOrError 是给工人看的中文原因
    using Handler = std::function<void(bool ok, const QString &valueOrError)>;

    // 重读 cloud_config.json 的 "tenda" 段（改完配置不用重启软件）
    void loadConfig();

    // 配好了吗：手工粘贴的 xp2pInfo 或"账号+密码"齐一样算配好
    bool configured() const;
    // 未配好时给 UI 的一句话说明（缺什么、写到哪个文件的哪个字段）
    QString configHint() const;

    // 取 xp2p_info。productKey = 产品 ID，sn = 设备名（参考实现就是把 iotId
    // 拆成 productKey/deviceName 直接传，见 TencentIotMgr.cpp:170）。
    // 有手工粘贴值时直接回它；否则按需登录后请求，token 失效会自动重登一次。
    void fetchXp2pInfo(const QString &productKey, const QString &sn, Handler done);

private:
    // 账号密码换 access_token：check/v2 拿 encrypt_mode，再 password/v2
    void login(std::function<void(bool ok, const QString &error)> done);
    void requestP2pToken(const QString &productKey, const QString &sn,
                         bool allowRelogin, Handler done);

    // 通用头。withApp=false 用于 check/v2（参考实现那一步不带 App-Id 三件套）
    void applyHeaders(QNetworkRequest &request, bool withApp, bool withAuth) const;

    QString domain_;
    QString account_;
    QString password_;      // 只在内存里，绝不写日志
    QString manual_info_;   // cloud_config.json 里手工粘贴的 xp2pInfo
    QString access_token_;   // 登录后缓存，失效再换
    QString terminal_;

    QNetworkAccessManager nam_;
};
