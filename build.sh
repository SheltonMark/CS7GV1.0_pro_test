#!/bin/sh
# 一键构建 + 部署。产物 = dist/ 整个文件夹（可直接拷到产线电脑双击运行）。
#
# 用法：sh build.sh
# 依赖：Qt 6.8.3 mingw + 配套工具链，装法见 README。
set -e

QT_ROOT=${QT_ROOT:-C:/Qt/6.8.3/mingw_64}
TOOLS=${TOOLS:-C:/Qt/Tools}
HERE=$(cd "$(dirname "$0")" && pwd)

# CMake 要 Windows 风格路径，PATH 要 POSIX 风格 —— 两者不能混，
# 混了表现为 "cmake: command not found"，很容易误判成没装。
to_posix() { printf '%s' "$1" | sed 's|^\([A-Za-z]\):|/\L\1|; s|\\|/|g'; }
QT_POSIX=$(to_posix "$QT_ROOT")
TOOLS_POSIX=$(to_posix "$TOOLS")

export PATH="$TOOLS_POSIX/CMake_64/bin:$TOOLS_POSIX/Ninja:$TOOLS_POSIX/mingw1310_64/bin:$QT_POSIX/bin:$PATH"

# ⚠️ 必须用 Qt 配套的 GCC 13.1.0。系统里若装了别的大版本 GCC（如 15.x），
# 混用会踩 C++ ABI 问题（异常处理、std::string 布局），且报错很隐蔽。
echo "[build] gcc  : $(gcc -dumpversion)"
echo "[build] qt   : $QT_ROOT"

BUILD="$HERE/build"
DIST="$HERE/dist"

# ⚠️ 最后一步要整体替换 dist/。若 dist/ 里的程序正在运行，它会锁住自己的 exe 和
# 已加载的 Qt DLL：rm 删掉没锁的部分后失败，set -e 就地中断 —— 留下一个被掏空的
# dist（上千文件已删、锁定的还在，连 exe 都只剩 .msys 待删存根），必须手工清理才
# 能再构建。放在编译前拦，省掉两分钟白等。
# 判据是"能否以写方式打开 exe"而非按进程名查：任何占用方都算，也不受 MSYS 改写
# tasklist 参数的影响（`//FI` 会被当路径处理）。
if [ -f "$DIST/ProductTestTool.exe" ] && ! ( : >> "$DIST/ProductTestTool.exe" ) 2>/dev/null; then
    echo "[build] FAIL dist/ProductTestTool.exe 被占用 —— 程序还在运行。" >&2
    echo "[build]      先关掉它再构建，否则 dist/ 会被删到一半然后中断。" >&2
    exit 1
fi

# ── 现场配置回抄，必须在动 dist 之前 ──────────────────────────────────────
# dist 里的 cloud_config.json 是产线/联调用的真密钥，不进 git，常常**只存在于
# dist**。下面确实有"从上一版 dist 抄回来"的逻辑（见 cloud_config 那一段），但它
# 有个前提：上一版 dist 还在。dist 一旦整个消失（手工删、或替换中途出错），
# 那份配置就永久丢了 —— 2026-08-20 实际丢过一次，密码只在命令行传过、无处可查。
#
# 所以每次构建先把它回抄到仓库根（已 gitignore），两处互为备份。根目录那份本来
# 就是构建的来源之一，回抄不会引入新语义，只是让它不再是孤本。
# 只回抄 cloud_config.json：仓库根本来就是它的来源之一，语义一致、且已 gitignore。
# factory_config.json 不回抄 —— 它的来源是 resources/，回抄到根会造出一个永不被读
# 的文件，还会变成未跟踪脏文件；丢了只是退回默认勾选，与丢密钥不是一个量级。
if [ -f "$DIST/cloud_config.json" ] \
   && ! cmp -s "$DIST/cloud_config.json" "$HERE/cloud_config.json" 2>/dev/null; then
    cp "$DIST/cloud_config.json" "$HERE/cloud_config.json"
    echo "[build] 备份现场配置到仓库根: cloud_config.json"
fi

# CMake 生成期会往 build/qmltypes 写文件但不保证先建目录，
# 干净构建时会报 "Cannot open file for write"。先建出来。
mkdir -p "$BUILD/qmltypes"

# 干净构建时 CMake 在 Git Bash 下探不到资源编译器，报
# "CMAKE_RC_COMPILER not set"，所以显式指给它。
cmake -G Ninja -S "$HERE" -B "$BUILD" \
      -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_PREFIX_PATH="$QT_ROOT" \
      -DCMAKE_CXX_COMPILER=g++ \
      -DCMAKE_RC_COMPILER="$TOOLS/mingw1310_64/bin/windres.exe" >/dev/null

cmake --build "$BUILD"

# ⚠️ 先部署到新目录再整体替换，不要 rm -rf dist 后立刻往同一路径写。
# dist 有 1300+ 文件，在大簇/网络盘上删除不会立即落地，windeployqt 会撞上
# 残留目录并中途失败（报 "Cannot create directory +Imagine"），
# 留下一个缺插件的残缺 dist —— 而且 windeployqt 仍返回 0，不会中断构建。
STAGE="$HERE/dist.stage.$$"
rm -rf "$STAGE"

# 先扫掉别的 PID 留下的暂存目录。构建被打断（Ctrl-C、进程被杀、工具超时）时
# 收不了尾，就会留下一个**整包大小（约 357MB）**的孤儿，而下次构建 PID 不同、
# 上面那行 rm 只清自己那个，永远清不到它 —— 攒几次就吃掉几个 G。
for orphan in "$HERE"/dist.stage.*; do
    [ -d "$orphan" ] && [ "$orphan" != "$STAGE" ] || continue
    echo "[build] 清理残留暂存目录: $(basename "$orphan")"
    rm -rf "$orphan"
done

# 本次构建自己的收尾：正常路径在末尾 mv 走了就不剩东西，异常退出/被打断时
# 靠这个 trap 兜住。EXIT 覆盖 return/exit，INT/TERM 覆盖 Ctrl-C 与被杀。
trap 'rm -rf "$STAGE"' EXIT INT TERM

mkdir -p "$STAGE"
cp "$BUILD/ProductTestTool.exe" "$STAGE/"

# 收集运行期依赖。--qmldir 让它扫 QML 里用到的模块。
windeployqt.exe --release --qmldir "$HERE/qml" "$STAGE/ProductTestTool.exe" >/dev/null

DIST_WORK="$STAGE"

# 删掉用不到的 Controls 样式（省约 13MB）。
# ⚠️ Windows 与 Fusion 两个基础样式不能删 —— FluentWinUI3 建立在它们之上，
#    删任一个程序直接起不来（实测）。
rm -f  "$DIST_WORK"/Qt6QuickControls2Imagine.dll \
       "$DIST_WORK"/Qt6QuickControls2Universal.dll \
       "$DIST_WORK"/Qt6QuickControls2Material.dll
rm -rf "$DIST_WORK"/qml/QtQuick/Controls/Imagine \
       "$DIST_WORK"/qml/QtQuick/Controls/Universal \
       "$DIST_WORK"/qml/QtQuick/Controls/Material \
       "$DIST_WORK"/qml/QtQuick/Controls/macOS \
       "$DIST_WORK"/qml/QtQuick/Controls/iOS \
       "$DIST_WORK"/translations

# 样例批次文件随包发 —— 同事拿到包就能试「导入 InputData1」，
# 不用先去产线要一份真文件。放 sample/ 与程序目录分开，不会被误当配置。
mkdir -p "$DIST_WORK/sample"
cp "$HERE/resources/sample/inputdata1_sample.txt" "$DIST_WORK/sample/"

# 云配置：sample 始终随包发（产线机照着填）；仓库根若有 cloud_config.json
#（本机联调密钥，已 gitignore）也带进 dist。注意用 if 而不是 && —— set -e
# 下 [ -f ] && cp 在文件缺失时会把整个构建判失败。
cp "$HERE/resources/cloud_config.sample.json" "$DIST_WORK/"
if [ -f "$HERE/cloud_config.json" ]; then
    cp "$HERE/cloud_config.json" "$DIST_WORK/"
fi

# 工厂配置（工艺参数+测试项勾选默认值）随包发，产线可直接改
cp "$HERE/resources/factory_config.json" "$DIST_WORK/"

# 保留上一版 dist 的现场配置，优先级最高（2026-08-19 实证：整目录替换把手放
# 的密钥文件删了，软件静默回落 Mock 假设备——"界面全过实则没连云"最难察觉）。
#   cloud_config.json    产线密钥（不进 git，常被直接放在 dist）
#                        ⚠️ 这一步只在"上一版 dist 还在"时管用。dist 整个消失的
#                        情况由构建开头的"回抄到仓库根"兜住，两者配合才完整。
#   factory_config.json  管理员在软件里勾选的测试项会写回此文件，重建不能清
if [ -f "$DIST/cloud_config.json" ]; then
    cp "$DIST/cloud_config.json" "$DIST_WORK/"
fi
if [ -f "$DIST/factory_config.json" ]; then
    cp "$DIST/factory_config.json" "$DIST_WORK/"
fi

# VLC 运行时（拉流引擎，约 137MB）。Qt Multimedia 对 RTSP/H265 大流与 http-flv
# 直播都不行（2026-08-19 定案换 libvlc，详见 src/stream/vlc_stream_player.hpp）。
# 优先沿用上一版 dist 里的（网络盘上少拷 130MB）；没有才从本机 VLC 取，
# 来源可用环境变量 VLC_RUNTIME 覆盖。缺失只警告不断链——包照出，拉流报错。
VLC_RUNTIME=${VLC_RUNTIME:-/d/tools/VLC}
if [ -f "$DIST/vlc/libvlc.dll" ]; then
    mkdir -p "$DIST_WORK/vlc"
    cp -r "$DIST/vlc/." "$DIST_WORK/vlc/"
elif [ -f "$VLC_RUNTIME/libvlc.dll" ]; then
    mkdir -p "$DIST_WORK/vlc/plugins"
    cp "$VLC_RUNTIME/libvlc.dll" "$VLC_RUNTIME/libvlccore.dll" "$DIST_WORK/vlc/"
    cp -r "$VLC_RUNTIME/plugins/." "$DIST_WORK/vlc/plugins/"
    echo "[build] vlc  : bundled from $VLC_RUNTIME"
else
    echo "[build] WARN: VLC runtime not found ($VLC_RUNTIME) — 拉流将不可用" >&2
fi

# ── HEVC-in-FLV 解复用：必须是 ffmpeg 6.1+ 的 libavcodec_plugin.dll ───────────
# 本机 VLC（3.0.x）自带的是 ffmpeg 4.4，FLV 解复用器不认 HEVC，云拉流会
# "缓冲 100% 但一帧不出"（README 第 28 条）。参考实现 D:\tendasecuritypc 的
# VLC-Qt 运行时里那份是 ffmpeg 8 静态编译版，ABI 与 3.0.x 兼容（同 vlc_entry
# 入口、同 66 个 libvlccore 导入符号），直接换文件即可。
#
# 这一步**不能只靠"沿用上一版 dist"**：dist 被清掉就会悄悄退回 ffmpeg 4.4，
# 画面消失且毫无线索。所以每次构建都显式校验版本串，不对就去参考实现取。
HEVC_PLUGIN_SRC=${HEVC_PLUGIN_SRC:-/d/tendasecuritypc/3rdpart/VLCQT/bin/plugins/codec/libavcodec_plugin.dll}
VLC_CODEC_DST="$DIST_WORK/vlc/plugins/codec/libavcodec_plugin.dll"
if [ -f "$VLC_CODEC_DST" ]; then
    # 判据取"有没有扩展视频标签头解析"（ex_header，E-RTMP/HEVC 那条路），不要按
    # 版本串判：ffmpeg-8 的二进制里同时含 Lavf57/Lavf62 等多个串，按老版本号
    # 匹配会永远命中、每次构建白拷 125MB。
    if ! grep -qa 'ex_header' "$VLC_CODEC_DST" 2>/dev/null; then
        if [ -f "$HEVC_PLUGIN_SRC" ]; then
            cp "$HEVC_PLUGIN_SRC" "$VLC_CODEC_DST"
            echo "[build] vlc  : libavcodec_plugin 换成 ffmpeg-8（HEVC-in-FLV 需要）"
        else
            echo "[build] WARN: 缺 ffmpeg-8 版 libavcodec_plugin（$HEVC_PLUGIN_SRC）" >&2
            echo "[build]       云拉流将卡在'缓冲 100% 不出画面'，见 README 第 28 条" >&2
        fi
    fi
fi

# 云拉流 SDK（腾讯 XP2P，app_interface.dll，约 1.7MB，静态链好依赖、自包含）。
# 无网口产品（CS6GV2.0）调焦画面走它建联取本机 http-flv URL，见
# src/stream/xp2p_client.cpp 与 docs/拉流整合方案.md。优先沿用上一版 dist/xp2p/；
# 没有才从参考工程取，来源可用环境变量 XP2P_RUNTIME 覆盖。缺失只警告不断链——
# 包照出，云拉流按钮点了提示"SDK 未就绪"，RTSP 产品不受影响。
XP2P_RUNTIME=${XP2P_RUNTIME:-/d/tendasecuritypc/3rdpart/p2p_sample/lib/windows/x64/Release}
if [ -f "$DIST/xp2p/app_interface.dll" ]; then
    mkdir -p "$DIST_WORK/xp2p"
    cp -r "$DIST/xp2p/." "$DIST_WORK/xp2p/"
elif [ -f "$XP2P_RUNTIME/app_interface.dll" ]; then
    mkdir -p "$DIST_WORK/xp2p"
    cp "$XP2P_RUNTIME/app_interface.dll" "$DIST_WORK/xp2p/"
    echo "[build] xp2p : bundled from $XP2P_RUNTIME"
else
    echo "[build] WARN: XP2P runtime not found ($XP2P_RUNTIME) — 云拉流将不可用" >&2
fi

# MSVC 运行时兜底：app_interface.dll 链的是 MSVCP140 / VCRUNTIME140[_1]
#（objdump -p 实证）。产线电脑不一定装了 VC++ 可再发行组件，缺了 LoadLibrary
# 会失败、云拉流点了就报"SDK 未就绪"。放到与 app_interface.dll **同目录**，靠
# DLL 搜索顺序兜住，不依赖系统装没装。
# ⚠️ 这段必须独立于上面的 if/elif —— 沿用上一版 dist/xp2p 那条分支若不补，
#    第一次带运行时构建出的包，重建后反而会丢掉运行时（实证踩过）。缺就补，
#    已有不重复拷。
if [ -f "$DIST_WORK/xp2p/app_interface.dll" ]; then
    for rt in msvcp140.dll vcruntime140.dll vcruntime140_1.dll; do
        if [ -f "$DIST_WORK/xp2p/$rt" ]; then
            continue
        elif [ -f "/c/Windows/System32/$rt" ]; then
            cp "/c/Windows/System32/$rt" "$DIST_WORK/xp2p/"
        else
            echo "[build] WARN: 缺 MSVC 运行时 $rt — 无 VC++ 组件的产线机云拉流会加载失败" >&2
        fi
    done
fi

# 注意：opengl32sw.dll（约 20MB）是软件 OpenGL 兜底，故意保留。
# 产线电脑常是低配机/显卡驱动不全/远程桌面登录，缺它会白屏或崩，
# 省这 20MB 不值得拿停线风险换。

# 部署完整性自检。windeployqt 中途失败时仍返回 0，不查就会交付一个
# 缺插件的包 —— 表现为双击后闪退/白屏，且日志里只有一行 module not found。
for must in \
    "$DIST_WORK/Qt6Core.dll" \
    "$DIST_WORK/Qt6Quick.dll" \
    "$DIST_WORK/qml/QtQuick/Controls/qtquickcontrols2plugin.dll" \
    "$DIST_WORK/qml/QtQuick/Controls/FluentWinUI3/qtquickcontrols2fluentwinui3styleplugin.dll" \
    "$DIST_WORK/qml/QtQuick/Controls/Windows" \
    "$DIST_WORK/qml/QtQuick/Controls/Fusion" ; do
    if [ ! -e "$must" ]; then
        echo "[build] FAIL 部署不完整，缺: $must" >&2
        exit 1   # 暂存目录由 trap 清理
    fi
done

# 替换 dist。两条路：
#
# 首选「先把旧的挪开、新的就位、再删旧的」—— 这样 mv 失败还能回滚，不会出现
# "旧的已删、新的没就位"的空手状态（实测踩过，只能整包重建）。
#
# 但整目录重命名在 Windows 下有个硬限制：**目录内只要有一个打开的句柄就不允许
# rename**，报 `Device or resource busy`。程序跑着时 dist/logs/*.log 正被写，
# 就会撞上。第 34 行那个 exe 占用检查挡不住这个 —— 它只测 exe，且检查与 mv 之间
# 有时间差（构建要几十秒，期间完全可能有人把程序起来）。
# 所以退路是原来那套 `rm -rf` 再 mv：它逐个删文件，锁住的跳过，能过。
trap - EXIT INT TERM          # 从这里起 STAGE 要变成 DIST，别再让 trap 删它
OLD="$HERE/dist.old.$$"
rm -rf "$OLD"
if [ -d "$DIST" ] && mv "$DIST" "$OLD" 2>/dev/null; then
    # 安全路径：旧的已挪到 OLD，出错可回滚
    if ! mv "$STAGE" "$DIST"; then
        echo "[build] FAIL 无法就位 dist，已回滚到上一版" >&2
        mv "$OLD" "$DIST"
        rm -rf "$STAGE"
        exit 1
    fi
    rm -rf "$OLD"
elif [ -d "$DIST" ]; then
    # 挪不动 = dist 里有文件被占用。**到此为止，一个字节都不要动。**
    #
    # 别试图退回 `rm -rf dist` —— 实测它同样删不掉被独占的文件，只会把 dist
    # 删残了才失败，比直接停下来坏得多（2026-08-20 就是这个状态：程序在跑、
    # dist/logs/*.log 被写着，旧 dist 被删掉一半）。
    #
    # 这一步顺带就是最可靠的占用探测：第 34 行只测 exe，测不到 logs 里的日志，
    # 而且那个检查与这里隔着几十秒的构建时间，中间完全可能有人把程序起起来。
    echo "[build] FAIL dist 里有文件被占用，无法替换 —— 程序还在运行？" >&2
    echo "[build]      关掉 dist/ProductTestTool.exe 再构建。" >&2
    echo "[build]      旧 dist 未被改动，暂存目录已清理，本次构建无副作用。" >&2
    rm -rf "$STAGE"
    exit 1
else
    # dist 压根不存在（首次构建，或被手工删过）
    if ! mv "$STAGE" "$DIST"; then
        echo "[build] FAIL 无法就位 dist" >&2
        rm -rf "$STAGE"
        exit 1
    fi
fi

# 用真实字节数，不用 du —— dist 是上千个小文件，在大簇盘（如 A:）上
# du 报的"占用"会比实际大十几倍，看着像 1.2G 其实只有 81MB。
# 也是交付要打 zip 而不是直接拷文件夹的原因。
REAL_MB=$(find "$DIST" -type f -printf '%s\n' | awk '{s+=$1} END {printf "%.0f", s/1048576}')
echo "[build] dist : $DIST  (${REAL_MB} MB 实际, $(find "$DIST" -type f | wc -l) files)"
echo "[build] run  : $DIST/ProductTestTool.exe"
