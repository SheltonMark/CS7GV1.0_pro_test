// 产测 PC 客户端入口。
//
// 这里刻意只做四件事：定样式、钉深色、注版本、加载 QML。业务侧 C++
// （腾讯云链路/UDP 设备发现/工厂配置）在 src/cloud/；XP2P/Excel/SQLite 还没接。

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStyleHints>

int main(int argc, char *argv[])
{
    // —— 拉流解码策略（必须在 QGuiApplication 之前设：多媒体后端在插件加载
    //    时就读这些变量）——
    //
    // ⚠️ 不要强制软解。2026-08-19 用命令行 VLC 抓 -vv 日志才看清：设备主码流是
    // **2560x1472**（约 380 万像素），VLC 是靠 d3d11va 硬解（Intel UHD 630）才
    // 放得动的：
    //   d3d11va debug: va_pool_SetupDecoder id 173 2560x1472 count: 28
    //   avcodec: Using D3D11VA (Intel UHD Graphics 630) for hardware decoding
    // 我先前按"640x360 软解毫无压力"的错误假设把硬解整个关掉（置空
    // DECODING_HW_DEVICE_TYPES），在集显工位机上 CPU 根本喂不动这个分辨率
    // ⇒ 解码持续跟不上、帧全被丢 ⇒ 界面停在"已解析｜视频轨 1"永不出图。
    // 所以这里**保留 Qt 默认的硬解优先**，只放开 level 标签不匹配的容忍
    // （设备 SDP 报 level-id=180 即 Level 6.0，比 2560x1472 实际所需高得多，
    //  部分驱动会因此拒绝——允许不匹配后按实际分辨率建解码器即可）。
    qputenv("QT_FFMPEG_HW_ALLOW_PROFILE_MISMATCH", QByteArrayLiteral("1"));
    // 协议白名单必须**含 udp/rtp**：2026-08-19 实测把它们剔除想逼 TCP 回落，
    // 结果 FFmpeg 连 RTSP 会话都打不开（`Could not open file`、视频轨 0），
    // 比默认更糟——rtsp 解复用器初始化阶段就依赖这两个协议注册在册。
    // 强制 TCP 改由 URL 层解决（见 ViewFocus 的 rtspUrlTemplate 说明）。
    qputenv("QT_FFMPEG_PROTOCOL_WHITELIST",
            QByteArrayLiteral("file,crypto,data,http,https,tcp,tls,rtsp,rtp,udp,httpproxy"));
    // 拉流排障开关（产线默认关）：设 PTEST_STREAM_DEBUG=1 启动，
    // 后端会把解复用/解码细节打到 stderr，用来定位"黑屏到底黑在哪一层"。
    if (!qEnvironmentVariableIsEmpty("PTEST_STREAM_DEBUG"))
        qputenv("QT_FFMPEG_DEBUG", QByteArrayLiteral("1"));

    QGuiApplication app(argc, argv);

    app.setApplicationName(QStringLiteral("ProductTestTool"));
    app.setApplicationVersion(QStringLiteral(APP_VERSION));
    app.setOrganizationName(QStringLiteral("Tenda"));

    // 样式在代码里定，不靠 QT_QUICK_CONTROLS_CONF 环境变量 —— 部署到产线电脑上
    // 没人会去设环境变量，漏设就静默退回 Basic 样式，观感完全不同。
    // 深色主题与强调色仍来自资源里的 qtquickcontrols2.conf。
    QQuickStyle::setStyle(QStringLiteral("FluentWinUI3"));

    // 深色不跟随系统主题 —— FluentWinUI3 的 Dialog 在 Light 主题下背景**写死
    // white**（样式源码如此，钉 palette 拦不住），Win10 机器普遍被解析成
    // Light，弹窗全白底（实测：测试项配置弹窗 Win10 白 / Win11 深色系统黑）。
    // 强制 Dark 后所有机器走同一分支，观感一致。
    QGuiApplication::styleHints()->setColorScheme(Qt::ColorScheme::Dark);

    QQmlApplicationEngine engine;

    // 构建信息给 QML（关于页 + 顶栏 + 导航栏底部都要显示）。
    // 产线出批量误判要能追溯是哪个版本干的。
    auto *ctx = engine.rootContext();
    ctx->setContextProperty(QStringLiteral("appVersion"), QStringLiteral(APP_VERSION));
    ctx->setContextProperty(QStringLiteral("buildDate"),  QStringLiteral(APP_BUILD_DATE));
    ctx->setContextProperty(QStringLiteral("buildType"),  QStringLiteral(APP_BUILD_TYPE));
    ctx->setContextProperty(QStringLiteral("qtVersion"),  QString::fromLatin1(qVersion()));
    // 安装目录：批次文件页要据此定位随包发的 sample/ 样例文件。
    // QML 侧没有取程序目录的 API，只能从这里注入。
    ctx->setContextProperty(QStringLiteral("applicationDirPath"),
                            QCoreApplication::applicationDirPath());

    engine.loadFromModule("ptest", "Main");
    if (engine.rootObjects().isEmpty())
        return -1;

    return app.exec();
}
