cmake_minimum_required(VERSION 3.21)

# 产测 PC 客户端。目前只有 UI 外观，C++ 业务层（协议/XP2P/播放/Excel/
# SQLite/流程引擎）尚未实现，数据全来自 MockData.qml。
#
# 版本号是产线工具的硬要求：界面要看得到，将来每条产测记录也要带上它，
# 否则批量误判无法追溯是哪个版本干的。此处是唯一来源。
project(ptest_pc_client VERSION 0.1.0 LANGUAGES CXX)

find_package(Qt6 6.7 REQUIRED COMPONENTS Quick QuickControls2)

qt_standard_project_setup(REQUIRES 6.7)

# 构建日期注入。用 configure 时刻的日期，不用 __DATE__ —— 后者依赖
# 编译器 locale、格式不稳，且增量构建时可能不刷新。
string(TIMESTAMP BUILD_DATE "%Y-%m-%d" UTC)

qt_add_executable(app_ptest src/main.cpp)

# qt_add_qml_module 只带进 Qml 依赖；QGuiApplication 来自 Gui、
# QQuickStyle 来自 QuickControls2，必须显式链，否则连头文件都找不到。
target_link_libraries(app_ptest PRIVATE
    Qt6::Quick
    Qt6::QuickControls2)

# ⚠️ 这两段 set_source_files_properties 必须写在 qt_add_qml_module **之前**。
# 写在后面 CMake 不报错、构建也过，但属性静默失效 —— 单例不会被注册成单例，
# 运行期 Theme.brand / Theme.radius 全是 undefined，颜色圆角间距整体丢失。
# 且这个坑只在编译版出现，qml.exe 预览用的是手写 qmldir，看不出来。

# pragma Singleton 只是 QML 侧声明，构建系统这边也必须标。
set_source_files_properties(
    qml/Theme.qml qml/TypeScale.qml qml/Icons.qml qml/MockData.qml
    PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

# logo 在 resources/ 但 QML 落在 qrc:/qt/qml/ptest/qml/ 下，
# 别名必须带 qml/ 前缀，否则图片被放到上一层、QML 里 "logo.png" 找不到。
set_source_files_properties(resources/logo.png
    PROPERTIES QT_RESOURCE_ALIAS qml/logo.png)

qt_add_qml_module(app_ptest
    URI ptest
    VERSION 1.0
    QML_FILES
        qml/Main.qml
        # 单例
        qml/Theme.qml
        qml/TypeScale.qml
        qml/Icons.qml
        qml/MockData.qml
        # 组件
        qml/Icon.qml
        qml/AppButton.qml
        qml/Card.qml
        qml/FieldRow.qml
        qml/TestItemRow.qml
        qml/ResultBanner.qml
        qml/NavRail.qml
        qml/TopBar.qml
        qml/StepList.qml
        # 页面
        qml/ViewFocus.qml
        qml/ViewFinished.qml
        qml/ViewInspect.qml
        qml/ViewRepair.qml
        qml/ViewProfile.qml
        qml/ViewAbout.qml
    RESOURCES
        # logo 与 QML 同目录，QML 里直接写 "logo.png" 即可
        resources/logo.png
)

# 样式配置随二进制走。Qt Quick Controls 默认读 :/qtquickcontrols2.conf，
# 打进资源后部署目录不必再摆这个文件、也不用设环境变量。
qt_add_resources(app_ptest "conf"
    PREFIX "/"
    BASE resources
    FILES resources/qtquickcontrols2.conf)

target_compile_definitions(app_ptest PRIVATE
    APP_VERSION="${PROJECT_VERSION}"
    APP_BUILD_DATE="${BUILD_DATE}"
    APP_BUILD_TYPE="${CMAKE_BUILD_TYPE}")

set_target_properties(app_ptest PROPERTIES
    # 不带控制台窗口。产线工具的日志走文件，不靠黑框。
    WIN32_EXECUTABLE TRUE
    OUTPUT_NAME "ProductTestTool")

install(TARGETS app_ptest RUNTIME DESTINATION .)
