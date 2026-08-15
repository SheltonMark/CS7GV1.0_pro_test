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
        rm -rf "$STAGE"
        exit 1
    fi
done

# 原子替换
rm -rf "$DIST"
mv "$STAGE" "$DIST"

# 用真实字节数，不用 du —— dist 是上千个小文件，在大簇盘（如 A:）上
# du 报的"占用"会比实际大十几倍，看着像 1.2G 其实只有 81MB。
# 也是交付要打 zip 而不是直接拷文件夹的原因。
REAL_MB=$(find "$DIST" -type f -printf '%s\n' | awk '{s+=$1} END {printf "%.0f", s/1048576}')
echo "[build] dist : $DIST  (${REAL_MB} MB 实际, $(find "$DIST" -type f | wc -l) files)"
echo "[build] run  : $DIST/ProductTestTool.exe"
