#include "local_settings.hpp"

namespace {

constexpr char kKeyUserId[] = "login/rememberedUserId";
constexpr char kKeyRemember[] = "login/remember";

} // namespace

LocalSettings::LocalSettings(QObject *parent)
    : QObject(parent)
    // 显式给组织/应用名，不依赖 QCoreApplication 的设置顺序 —— 单例可能在
    // main() 设置这些之前就被 QML 引擎实例化，那样键会落到错误的路径下。
    , settings_(QSettings::NativeFormat, QSettings::UserScope,
                QStringLiteral("Tenda"), QStringLiteral("ProductTest"))
{
}

QString LocalSettings::rememberedUserId() const
{
    if (!settings_.value(QLatin1String(kKeyRemember), true).toBool())
        return QString();
    return settings_.value(QLatin1String(kKeyUserId)).toString();
}

bool LocalSettings::rememberEnabled() const
{
    return settings_.value(QLatin1String(kKeyRemember), true).toBool();
}

void LocalSettings::setRememberedUserId(const QString &id, bool remember)
{
    settings_.setValue(QLatin1String(kKeyRemember), remember);
    if (remember && !id.isEmpty())
        settings_.setValue(QLatin1String(kKeyUserId), id);
    else
        settings_.remove(QLatin1String(kKeyUserId));   // 取消勾选就抹掉，不是留着
    settings_.sync();
}
