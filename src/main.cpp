// 产测 PC 客户端入口。
//
// 这里刻意只做三件事：定样式、注版本、加载 QML。真实项目的 C++ 侧
// （协议/XP2P/播放/Excel/SQLite/流程引擎）都还不在，界面是纯壳。

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    app.setApplicationName(QStringLiteral("ProductTestTool"));
    app.setApplicationVersion(QStringLiteral(APP_VERSION));
    app.setOrganizationName(QStringLiteral("Tenda"));

    // 样式在代码里定，不靠 QT_QUICK_CONTROLS_CONF 环境变量 —— 部署到产线电脑上
    // 没人会去设环境变量，漏设就静默退回 Basic 样式，观感完全不同。
    // 深色主题与强调色仍来自资源里的 qtquickcontrols2.conf。
    QQuickStyle::setStyle(QStringLiteral("FluentWinUI3"));

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
