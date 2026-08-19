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
    // 拉流引擎已切换为 libvlc（src/stream/vlc_stream_player，2026-08-19 定案：
    // Qt Multimedia 对设备 2560x1472 H265 RTSP "已解析却零帧"，且不支持云拉流
    // 要用的 http-flv 直播）。此前在这里调 QT_FFMPEG_* 环境变量的若干尝试
    // （强制软解/协议白名单）均已随引擎切换移除；排障开关 PTEST_STREAM_DEBUG=1
    // 保留——现在它放行 libvlc 的全量日志（见 VlcStreamPlayer 的 LogCb）。

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
