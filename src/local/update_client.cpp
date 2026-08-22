#include "update_client.hpp"

#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QMetaObject>
#include <QProcess>
#include <QTextStream>
#include <QThread>

#include <thread>

#ifdef Q_OS_WIN
#include <windows.h>
#endif

#include "factory_config.hpp"
#include "stream_log.hpp"

namespace {

QString InstallDir()
{
    return QCoreApplication::applicationDirPath();
}

QString StagingDir()
{
    return InstallDir() + QStringLiteral("/update.staged");
}

// 简单版本比较：按 '.' 分段数值比。返回 >0 表示 a 新于 b。
int CompareVersion(const QString &a, const QString &b)
{
    const QStringList as = a.split(QLatin1Char('.'));
    const QStringList bs = b.split(QLatin1Char('.'));
    const int n = qMax(as.size(), bs.size());
    for (int i = 0; i < n; ++i) {
        const int av = i < as.size() ? as.at(i).toInt() : 0;
        const int bv = i < bs.size() ? bs.at(i).toInt() : 0;
        if (av != bv)
            return av - bv;
    }
    return 0;
}

} // namespace

UpdateClient::UpdateClient(QObject *parent)
    : QObject(parent)
{
}

UpdateClient::~UpdateClient() = default;

void UpdateClient::setState(State s, const QString &error)
{
    state_ = s;
    error_ = error;
    emit stateChanged();
}

QString UpdateClient::hashFile(const QString &absPath)
{
    QFile f(absPath);
    if (!f.open(QIODevice::ReadOnly))
        return QString();
    QCryptographicHash h(QCryptographicHash::Sha256);
    if (!h.addData(&f))
        return QString();
    return QString::fromLatin1(h.result().toHex());
}

bool UpdateClient::parseManifest(const QByteArray &raw, QString *version,
                                 QList<FileEntry> *files, QString *error)
{
    QJsonParseError perr;
    const QJsonDocument doc = QJsonDocument::fromJson(raw, &perr);
    if (doc.isNull()) {
        *error = QStringLiteral("manifest.json 解析失败：") + perr.errorString();
        return false;
    }
    const QJsonObject root = doc.object();
    *version = root.value(QStringLiteral("version")).toString();
    if (version->isEmpty()) {
        *error = QStringLiteral("manifest.json 缺 version 字段");
        return false;
    }
    for (const QJsonValue &v : root.value(QStringLiteral("files")).toArray()) {
        const QJsonObject o = v.toObject();
        FileEntry e;
        e.path = o.value(QStringLiteral("path")).toString();
        e.sha256 = o.value(QStringLiteral("sha256")).toString();
        e.size = qint64(o.value(QStringLiteral("size")).toDouble());
        // 路径穿越防御：清单来自共享目录，别让 "..\..\xx" 写到安装目录之外
        if (e.path.isEmpty() || e.sha256.isEmpty()
            || e.path.contains(QStringLiteral("..")))
            continue;
        files->append(e);
    }
    if (files->isEmpty()) {
        *error = QStringLiteral("manifest.json 没有有效的文件条目");
        return false;
    }
    return true;
}

void UpdateClient::check()
{
    if (busy_)
        return;
    const QString src = FactoryConfig::instance()->updateSource();
    if (src.isEmpty()) {
        setState(Error, QStringLiteral(
            "未配置升级源 —— 在 factory_config.json 的 updateSource 填工厂内网"
            "共享目录（如 \\\\192.168.1.10\\ptest_update）"));
        return;
    }
    if (src.startsWith(QStringLiteral("http"), Qt::CaseInsensitive)) {
        setState(Error, QStringLiteral(
            "升级源暂只支持共享目录（UNC 路径），不支持 http —— 把共享目录路径"
            "填进 updateSource 即可"));
        return;
    }

    busy_ = true;
    progress_ = 0.0;
    emit progressChanged();
    setState(Checking);
    StreamLog::append(QStringLiteral("[升级] 检查更新，源=%1").arg(src));

    // 哈希本地文件要读几百 MB，绝不能在 UI 线程干
    QThread *worker = QThread::create([this, src]() {
        QString err;

        // ① 远端 manifest
        QFile rf(src + QStringLiteral("/manifest.json"));
        if (!rf.open(QIODevice::ReadOnly)) {
            QMetaObject::invokeMethod(this, [this, src]() {
                busy_ = false;
                setState(Error, QStringLiteral(
                    "读不到升级源的 manifest.json（%1）—— 确认共享目录可访问、"
                    "且已用 publish_update.sh 发布过").arg(src));
            });
            return;
        }
        const QByteArray remoteRaw = rf.readAll();
        QString remoteVer;
        QList<FileEntry> remoteFiles;
        if (!parseManifest(remoteRaw, &remoteVer, &remoteFiles, &err)) {
            QMetaObject::invokeMethod(this, [this, err]() {
                busy_ = false;
                setState(Error, err);
            });
            return;
        }

        // ② 版本比较。远端不比本地新就到此为止 —— 不用去哈希几百 MB
        const QString localVer = QCoreApplication::applicationVersion();
        if (CompareVersion(remoteVer, localVer) <= 0) {
            QMetaObject::invokeMethod(this, [this, remoteVer]() {
                busy_ = false;
                remote_version_ = remoteVer;
                setState(UpToDate);
                StreamLog::append(QStringLiteral("[升级] 已是最新（本地 v%1，服务器 v%2）")
                    .arg(QCoreApplication::applicationVersion(), remoteVer));
            });
            return;
        }

        // ③ 差异清单：优先用本地 manifest 的哈希（publish 时写入 dist），
        //    没有就现算本地文件的 sha256 —— 慢（要读整个安装目录）但只发生在
        //    "第一次从手工拷贝包升级"这一回。
        QHash<QString, QString> localHash;
        QFile lf(InstallDir() + QStringLiteral("/manifest.json"));
        if (lf.open(QIODevice::ReadOnly)) {
            QString lv;
            QList<FileEntry> lfiles;
            QString lerr;
            if (parseManifest(lf.readAll(), &lv, &lfiles, &lerr)) {
                for (const FileEntry &e : lfiles)
                    localHash.insert(e.path, e.sha256);
            }
        }

        QList<FileEntry> diff;
        qint64 bytes = 0;
        for (const FileEntry &e : remoteFiles) {
            QString local = localHash.value(e.path);
            if (local.isEmpty()) {
                // 本地清单没有这文件：可能是新增文件，也可能没有本地清单 —— 现算
                const QString abs = InstallDir() + QLatin1Char('/') + e.path;
                local = QFile::exists(abs) ? hashFile(abs) : QString();
            }
            if (local != e.sha256) {
                diff.append(e);
                bytes += e.size;
            }
        }

        QMetaObject::invokeMethod(this, [this, remoteVer, remoteRaw, diff, bytes]() {
            busy_ = false;
            remote_version_ = remoteVer;
            remote_manifest_raw_ = remoteRaw;
            diff_ = diff;
            diff_count_ = diff.size();
            diff_bytes_ = bytes;
            if (diff.isEmpty()) {
                // 版本号更新但文件全一致：只差清单本身（比如首次发布）——
                // 直接当就绪处理，apply 会把新 manifest 落下去
                setState(Staged);
            } else {
                setState(Available);
            }
            StreamLog::append(QStringLiteral("[升级] 发现 v%1，差异 %2 个文件 %3 MB")
                .arg(remote_version_).arg(diff_count_)
                .arg(QString::number(diff_bytes_ / 1048576.0, 'f', 1)));
        });
    });
    connect(worker, &QThread::finished, worker, &QObject::deleteLater);
    worker->start();
}

void UpdateClient::download()
{
    if (busy_ || state_ != Available)
        return;
    const QString src = FactoryConfig::instance()->updateSource();

    busy_ = true;
    progress_ = 0.0;
    emit progressChanged();
    setState(Downloading);

    const QList<FileEntry> files = diff_;
    const qint64 total = diff_bytes_ > 0 ? diff_bytes_ : 1;
    const QByteArray manifestRaw = remote_manifest_raw_;

    QThread *worker = QThread::create([this, src, files, total, manifestRaw]() {
        const QString staging = StagingDir();
        QDir().mkpath(staging);

        qint64 done = 0;
        for (const FileEntry &e : files) {
            const QString from = src + QStringLiteral("/files/") + e.path;
            const QString to = staging + QLatin1Char('/') + e.path;
            QDir().mkpath(QFileInfo(to).absolutePath());
            QFile::remove(to);           // 上次没走完的残留
            if (!QFile::copy(from, to)) {
                QMetaObject::invokeMethod(this, [this, e]() {
                    busy_ = false;
                    setState(Error, QStringLiteral("拷贝失败：%1 —— 检查共享目录连接")
                                        .arg(e.path));
                });
                return;
            }
            // 逐文件校验：内网拷贝也会坏，坏文件绝不能进安装目录
            if (hashFile(to) != e.sha256) {
                QMetaObject::invokeMethod(this, [this, e]() {
                    busy_ = false;
                    setState(Error, QStringLiteral(
                        "校验不过：%1 —— 文件在传输中损坏，重试下载").arg(e.path));
                });
                return;
            }
            done += e.size;
            const double p = double(done) / double(total);
            QMetaObject::invokeMethod(this, [this, p]() {
                progress_ = p;
                emit progressChanged();
            });
        }

        // 远端 manifest 原样落进 staged —— apply 后它就是新的本地清单，
        // 下次升级的差异计算靠它（不用再哈希整个安装目录）
        QFile mf(staging + QStringLiteral("/manifest.json"));
        if (mf.open(QIODevice::WriteOnly))
            mf.write(manifestRaw);

        QMetaObject::invokeMethod(this, [this]() {
            busy_ = false;
            setState(Staged);
            StreamLog::append(QStringLiteral("[升级] 下载完成并逐文件校验通过，待安装"));
        });
    });
    connect(worker, &QThread::finished, worker, &QObject::deleteLater);
    worker->start();
}

void UpdateClient::apply()
{
    if (state_ != Staged)
        return;

    // Windows 上 exe 覆盖不了运行中的自己 —— 写一个脚本等本进程退出后干活：
    // 覆盖文件（xcopy 不删除，现场配置天然安全）→ 拉起新版 → 清理自己。
    const QString install = QDir::toNativeSeparators(InstallDir());
    const QString staging = QDir::toNativeSeparators(StagingDir());
    const QString script = QDir::toNativeSeparators(
        InstallDir() + QStringLiteral("/apply_update.cmd"));
    const QString pid = QString::number(QCoreApplication::applicationPid());

    QFile f(script);
    if (!f.open(QIODevice::WriteOnly)) {
        setState(Error, QStringLiteral("写不出升级脚本（安装目录只读？）"));
        return;
    }
    // 注意引号：安装路径可能带空格。脚本用 GBK 无所谓 —— 内容全 ASCII。
    const QString exe = install + QStringLiteral("\\ProductTestTool.exe");
    QTextStream ts(&f);
    // ⚠️ 等待判据是"exe 能不能被写"，**不是**"某个 PID 还在不在"。
    //    早先按 PID 等，2026-08-21 实测卡死：机器上开了两个实例，脚本等的那个
    //    PID 退了也没用（另一个照样锁着 exe），而且真出现过"点了安装但进程没退"，
    //    脚本就在 :wait 里转到天荒地老、staged 永远拷不进去。
    //    `2>nul (>>"file" call )` 是 cmd 里探文件是否被占用的标准手法：以追加方式
    //    打开但不写入，成功即说明没人锁着。
    //    再加 60 秒上限：宁可报错让人处理，也不要静默卡住。
    ts << "@echo off\r\n"
       << "title ProductTestTool update\r\n"
       << "echo Updating to v" << remote_version_ << " ...\r\n"
       << "echo The app will RESTART AUTOMATICALLY - do NOT start it manually.\r\n"
       << "set /a tries=0\r\n"
       << ":wait\r\n"
       << "2>nul (>>\"" << exe << "\" call ) && goto ready\r\n"
       << "set /a tries+=1\r\n"
       << "if %tries% GEQ 60 goto locked\r\n"
       << "echo waiting for the app to close... (%tries%/60)\r\n"
       << "ping -n 2 127.0.0.1 >nul\r\n"
       << "goto wait\r\n"
       << ":ready\r\n"
       << "echo applying files...\r\n"
       << "xcopy /E /Y /Q \"" << staging << "\\*\" \"" << install << "\\\"\r\n"
       << "if errorlevel 1 goto copyfail\r\n"
       << "rd /S /Q \"" << staging << "\"\r\n"
       << "echo done, restarting...\r\n"
       << "start \"\" \"" << exe << "\"\r\n"
       << "del \"%~f0\"\r\n"
       << "exit /b 0\r\n"
       // 失败分支都停住给人看 —— 静默失败比报错难查得多（这次就是）
       << ":locked\r\n"
       << "echo.\r\n"
       << "echo FAILED: the app is still running and locks the exe.\r\n"
       << "echo Close ALL ProductTestTool windows, then run this script again:\r\n"
       << "echo   " << script << "\r\n"
       << "pause\r\n"
       << "exit /b 1\r\n"
       << ":copyfail\r\n"
       << "echo.\r\n"
       << "echo FAILED to copy files. The update is kept at:\r\n"
       << "echo   " << staging << "\r\n"
       << "echo Close the app and run this script again.\r\n"
       << "pause\r\n"
       << "exit /b 1\r\n";
    f.close();

    // ⚠️ 必须查 startDetached 的返回值。早先不查，2026-08-21 实测出现"日志说
    //    已退出安装、脚本也写好了，但黑窗没出现、进程还在" —— 无从判断是脚本没
    //    启动还是没退出，白查一轮。
    qint64 childPid = 0;
    const bool spawned = QProcess::startDetached(
        QStringLiteral("cmd.exe"), {QStringLiteral("/c"), script}, install, &childPid);
    if (!spawned) {
        StreamLog::append(QStringLiteral("[升级] 启动安装脚本失败 —— 手动双击运行：%1")
                              .arg(script));
        setState(Error, QStringLiteral(
            "启动安装脚本失败。请关闭软件后手动双击运行：\n%1").arg(script));
        return;                     // 不退出 —— 退了工人就看不到这条提示
    }
    StreamLog::append(QStringLiteral("[升级] 安装脚本已启动 pid=%1，本进程退出安装 v%2")
                          .arg(childPid).arg(remote_version_));

    // 退出。⚠️ 不能只调 quit()：实测（2026-08-21）日志都打到"退出并安装"了，
    //    进程却一直活着 —— libvlc / XP2P 的工作线程会把退出拖死（要么事件循环
    //    没停，要么停了卡在析构 join），脚本在 :wait 里等 exe 解锁等不到。
    //    兜底不能用 QTimer —— 它依赖事件循环，而卡死的可能恰恰是循环退出后的
    //    析构阶段。用系统级线程：睡 1.5 秒还活着就 ExitProcess 硬退。
    //    硬退是安全的：现场状态（账号/进度/配置）都是改一次立刻落盘（QSaveFile），
    //    没有"退出时才保存"的数据；正常退出赢了这场竞赛的话，线程随进程消失。
    QCoreApplication::quit();
#ifdef Q_OS_WIN
    std::thread([]() {
        ::Sleep(1500);
        ::ExitProcess(0);
    }).detach();
#endif
}
