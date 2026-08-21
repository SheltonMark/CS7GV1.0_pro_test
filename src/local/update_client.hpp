#pragma once

#include <QObject>
#include <QString>
#include <QtQml/qqmlregistration.h>

// 在线升级（工厂内网共享目录，2026-08-21 需求：不再逐台手工拷 358MB 的包）。
//
// 升级源 = factory_config.json 的 updateSource（UNC 路径，如
// \\192.168.1.10\ptest_update），目录结构由 tools/publish_update.sh 生成：
//   manifest.json          版本号 + 每个文件的 sha256/大小
//   files/<相对路径>        与 dist 同构的文件树
//
// 三步走，全部异步（哈希/拷贝在工作线程，UI 不卡）：
//   check()    读远端 manifest，比版本；再与本地 manifest 逐文件比 sha256，
//              算出**差异清单** —— VLC 运行时 300+MB 几乎从不变，逐文件差分把
//              一次升级从 358MB 降到几十 MB。
//   download() 只拷差异文件到 update.staged/，每个文件拷完立刻按 manifest 的
//              sha256 校验 —— 内网拷贝也会坏（网络闪断/磁盘满），坏文件绝不能
//              进安装目录。
//   apply()    生成 apply_update.cmd 后退出程序：Windows 上 exe 覆盖不了运行中
//              的自己，必须由外部脚本等进程退出后再替换、再拉起新版。
//
// 现场配置永不覆盖：cloud_config/accounts/factory_config/station_progress/
// profiles 这些不进 manifest（publish 脚本排除），apply 只按清单拷贝、不做删除。
//
// v1 边界（记录在案）：只支持共享目录不支持 http；manifest 未做签名（内网可控，
// 防的是传输损坏不是投毒 —— 要出厂就必须补验签）。
class UpdateClient : public QObject
{
    Q_OBJECT
    QML_ELEMENT
    QML_SINGLETON

public:
    // Idle 未查 / Checking 查询中 / UpToDate 已最新 / Available 有更新
    // Downloading 下载中 / Staged 就绪可安装 / Error 出错（看 errorText）
    enum State { Idle, Checking, UpToDate, Available, Downloading, Staged, Error };
    Q_ENUM(State)

    Q_PROPERTY(State state READ state NOTIFY stateChanged)
    Q_PROPERTY(QString errorText READ errorText NOTIFY stateChanged)
    Q_PROPERTY(QString remoteVersion READ remoteVersion NOTIFY stateChanged)
    // 差异清单摘要：要下载几个文件、共多少字节（给按钮文案用）
    Q_PROPERTY(int diffCount READ diffCount NOTIFY stateChanged)
    Q_PROPERTY(qint64 diffBytes READ diffBytes NOTIFY stateChanged)
    // 下载进度 0.0~1.0（按字节）
    Q_PROPERTY(double progress READ progress NOTIFY progressChanged)

    explicit UpdateClient(QObject *parent = nullptr);
    ~UpdateClient() override;

    State state() const { return state_; }
    QString errorText() const { return error_; }
    QString remoteVersion() const { return remote_version_; }
    int diffCount() const { return diff_count_; }
    qint64 diffBytes() const { return diff_bytes_; }
    double progress() const { return progress_; }

    Q_INVOKABLE void check();
    Q_INVOKABLE void download();
    // 生成升级脚本并退出程序（脚本等本进程退出后替换文件、拉起新版）
    Q_INVOKABLE void apply();

signals:
    void stateChanged();
    void progressChanged();

private:
    struct FileEntry {
        QString path;      // 相对安装目录
        QString sha256;
        qint64 size {0};
    };

    void setState(State s, const QString &error = QString());
    static QString hashFile(const QString &absPath);          // sha256 hex，失败回空
    static bool parseManifest(const QByteArray &raw, QString *version,
                              QList<FileEntry> *files, QString *error);

    State state_ {Idle};
    QString error_;
    QString remote_version_;
    QList<FileEntry> diff_;          // check() 算出的差异清单
    int diff_count_ {0};
    qint64 diff_bytes_ {0};
    double progress_ {0.0};
    QByteArray remote_manifest_raw_; // 下载完原样落进 staged，apply 后成为本地 manifest
    // 工作线程活着时禁止再点（check/download 都在后台跑）
    bool busy_ {false};
};
