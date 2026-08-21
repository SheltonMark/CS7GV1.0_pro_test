#!/usr/bin/env bash
# 发布升级包到工厂内网共享目录（在 Git Bash 里跑）：
#   ./tools/publish_update.sh //192.168.1.10/ptest_update
#   ./tools/publish_update.sh /d/ptest_update          # 本地目录也行（先验流程）
#
# 产出（工位 PC 的 UpdateClient 按这个结构取）：
#   <目标>/manifest.json    版本 + 每文件 sha256/大小
#   <目标>/files/...        与 dist 同构的文件树
#
# 同时把 manifest.json 写回本机 dist/ —— 客户端下次 check 用它算差异，
# 不用重新哈希整个安装目录。
#
# ⚠️ 现场配置永不进清单（升级绝不能覆盖工位自己的配置/进度/账号）。
set -euo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$HERE/dist"
TARGET="${1:?用法: publish_update.sh <目标共享目录>}"
# 统一成正斜杠（PowerShell/cmd 传进来的是反斜杠）
TARGET="${TARGET//\\//}"
# 转绝对路径：下面会 cd 进 dist，相对目标会拷错地方。
# ⚠️ 绝对路径有三种长相都要认：/d/xxx（MSYS）、D:/xxx（盘符）、//server/share（UNC）。
#    早先只认 "/" 开头，用户传 D:/ptest_publish 被当成相对路径，拼成了
#    A:/…/ptest_pc_client/D:/ptest_publish（实测踩过）。
case "$TARGET" in
    /*|[A-Za-z]:/*) ;;
    *) TARGET="$PWD/$TARGET" ;;
esac

[ -f "$DIST/ProductTestTool.exe" ] || { echo "FAIL: dist 里没有 exe，先 build.sh"; exit 1; }

# 版本号唯一来源 = CMakeLists 的 project(VERSION x.y.z)
VERSION=$(sed -n 's/^project(.*VERSION \([0-9.]*\).*/\1/p' "$HERE/CMakeLists.txt")
[ -n "$VERSION" ] || { echo "FAIL: 从 CMakeLists.txt 解析不出版本号"; exit 1; }

# 排除清单：现场配置 + 运行态 + 日志 + 清单自身
EXCLUDE='^(cloud_config\.json|accounts\.json|factory_config\.json|station_progress\.json|profiles\.json|manifest\.json|apply_update\.cmd|logs/|update\.staged/)'

echo "[publish] v$VERSION -> $TARGET"
mkdir -p "$TARGET/files"

MANIFEST="$TARGET/manifest.json.tmp"
{
    echo '{'
    echo "  \"version\": \"$VERSION\","
    echo '  "files": ['
    first=1
    cd "$DIST"
    # -printf 不跨平台，这里用 find+循环；千余文件、几分钟内完成
    find . -type f | sed 's|^\./||' | sort | while IFS= read -r rel; do
        case "$rel" in
            cloud_config.json|accounts.json|factory_config.json|station_progress.json|profiles.json|manifest.json|apply_update.cmd|app.lock) continue ;;
            logs/*|update.staged/*) continue ;;
        esac
        sha=$(sha256sum "$rel" | cut -d' ' -f1)
        size=$(stat -c %s "$rel")
        [ $first -eq 1 ] && first=0 || echo ','
        printf '    {"path": "%s", "sha256": "%s", "size": %s}' "$rel" "$sha" "$size"
        # 顺手把文件拷到目标（保持目录结构）
        mkdir -p "$TARGET/files/$(dirname "$rel")"
        cp -f "$rel" "$TARGET/files/$rel"
    done
    echo ''
    echo '  ]'
    echo '}'
} > "$MANIFEST"

# 原子就位：客户端可能正在读 manifest.json，别让它读到写了一半的
mv -f "$MANIFEST" "$TARGET/manifest.json"
cp -f "$TARGET/manifest.json" "$DIST/manifest.json"

# ── 让 files/ 成为"可直接拷走的完整安装"（首装 = 资源管理器拷 files\ 到本地）──
# 这两个文件**不进 manifest**：升级流程永不下载/覆盖它们，只有首装能带走。
#   factory_config.json  模板（updateSource 已预填），来自 resources/ 而不是
#                        dist/ —— dist 里那份是开发机自己的现场配置
#   manifest.json        首装机器有了它，第一次检查更新就不用哈希整个安装目录
cp -f "$HERE/resources/factory_config.json" "$TARGET/files/factory_config.json"
cp -f "$TARGET/manifest.json" "$TARGET/files/manifest.json"

echo "[publish] done: $(grep -c '"path"' "$TARGET/manifest.json") files"
