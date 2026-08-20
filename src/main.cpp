// 产测 PC 客户端入口。
//
// 这里刻意只做四件事：定样式、钉深色、注版本、加载 QML。业务侧 C++
// （腾讯云链路/UDP 设备发现/工厂配置）在 src/cloud/；拉流在 src/stream/
// （libvlc 播放 + XP2P 云建联）；Excel/SQLite 还没接。

#include <QDateTime>
#include <QDir>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include <QStyleHints>

#include <cstdio>

namespace {

// 日志落盘。程序是 WIN32_EXECUTABLE（无控制台），双击运行时 stderr 没有去处，
// 拉流排障最需要的那些原生输出（libvlc 的 LogCb、XP2P SDK 的 setLogEnable、
// 我们自己的 fprintf）会**全部丢掉**。这里把 stderr 整体重定向到
// dist/logs/ptest_<时间>.log，一次解决三方来源。
//
// 只保留最近 kKeepLogs 个文件：产线机器长期跑，不清会无限堆积。
constexpr int kKeepLogs = 20;

void InstallFileLog()
{
    const QString dir = QCoreApplication::applicationDirPath() + QStringLiteral("/logs");
    QDir().mkpath(dir);

    // 轮转：按名字排序删旧的（文件名带时间戳，字典序即时间序）
    QDir d(dir);
    const QStringList olds =
        d.entryList({QStringLiteral("ptest_*.log")}, QDir::Files, QDir::Name);
    for (int i = 0; i < olds.size() - (kKeepLogs - 1); ++i)
        d.remove(olds.at(i));

    const QString path = dir + QStringLiteral("/ptest_")
        + QDateTime::currentDateTime().toString(QStringLiteral("yyyyMMdd_HHmmss"))
        + QStringLiteral(".log");

    // freopen 而不是自建 QFile：要连 C 运行时的 stderr 一起劫走，
    // 否则第三方库直接写 stderr 的那部分还是丢。
    if (std::freopen(path.toLocal8Bit().constData(), "w", stderr) == nullptr)
        return;
    std::setvbuf(stderr, nullptr, _IOLBF, 4096);   // 行缓冲：崩了也不丢已写的行

    // Qt 自己的 qDebug/qWarning 默认也走 stderr，这样一并进文件。
    qInstallMessageHandler([](QtMsgType type, const QMessageLogContext &,
                              const QString &msg) {
        const char *tag = type == QtDebugMsg    ? "D"
                        : type == QtInfoMsg     ? "I"
                        : type == QtWarningMsg  ? "W"
                        : type == QtCriticalMsg ? "C" : "F";
        std::fprintf(stderr, "[qt][%s] %s\n", tag, qPrintable(msg));
    });

    std::fprintf(stderr, "[log] %s\n", qPrintable(path));
}

} // namespace

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

    // 尽早装：越早重定向，越少日志漏在外面。必须在 QGuiApplication 之后
    // （要用 applicationDirPath）。
    InstallFileLog();
    std::fprintf(stderr, "[log] ProductTestTool %s (%s, %s)\n", APP_VERSION,
                 APP_BUILD_TYPE, APP_BUILD_DATE);

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
