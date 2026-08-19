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
    // 强制软解。2026-08-19 现场：VLC 能出画面（花屏但有图），本软件全黑。
    // 设备 SDP 里 H265 是 `profile-id=1 level-id=180`，即 **Level 6.0** ——
    // 这个等级标签异常高，相当多的硬件解码器只认到 5.1，遇到 6.0 直接拒绝
    // 建解码器 ⇒ 一帧不出 ⇒ 纯黑（VLC 默认会回落软解，所以它有画面）。
    // Qt FFmpeg 后端存在 QT_FFMPEG_HW_ALLOW_PROFILE_MISMATCH 这个开关本身，
    // 就说明"硬解遇到 profile/level 不匹配"是它已知的坑。
    //
    // 产线取确定性而非省 CPU：工位机的显卡/驱动五花八门，软解一条
    // 640x360~1080p 的 H265 对近十年的 CPU 都是小事，而"这台能放那台黑屏"
    // 的排查成本高得多。空值 = 不启用任何硬解设备。
    qputenv("QT_FFMPEG_DECODING_HW_DEVICE_TYPES", QByteArray());
    // 双保险：万一将来改回硬解，也别因 level 标签不匹配就整个放弃。
    qputenv("QT_FFMPEG_HW_ALLOW_PROFILE_MISMATCH", QByteArrayLiteral("1"));
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
