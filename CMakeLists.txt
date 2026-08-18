cmake_minimum_required(VERSION 3.21)

# 产测 PC 客户端。目前只有 UI 外观，C++ 业务层（协议/XP2P/播放/Excel/
# SQLite/流程引擎）尚未实现，数据全来自 MockData.qml。
#
# 版本号是产线工具的硬要求：界面要看得到，将来每条产测记录也要带上它，
# 否则批量误判无法追溯是哪个版本干的。此处是唯一来源。
project(ptest_pc_client VERSION 0.1.8 LANGUAGES CXX)

find_package(Qt6 6.7 REQUIRED COMPONENTS Quick QuickControls2 Network Multimedia)

qt_standard_project_setup(REQUIRES 6.7)

# 构建日期注入。用 configure 时刻的日期，不用 __DATE__ —— 后者依赖
# 编译器 locale、格式不稳，且增量构建时可能不刷新。
string(TIMESTAMP BUILD_DATE "%Y-%m-%d" UTC)

# exe 图标 + 版本资源。configure_file 把 project(VERSION) 的三段号填进
# Application.rc.in 生成真正的 .rc；版本号唯一来源仍是上面的 project()，
# 这里只是转译格式，不重复定义。
# CMAKE_SOURCE_DIR 在 Windows 上是反斜杠路径，windres 解析 rc 里的字符串
# 会把 \A \r 等当转义序列吃掉——转成正斜杠再喂给 configure_file。
file(TO_CMAKE_PATH "${CMAKE_SOURCE_DIR}" SOURCE_DIR_FWDSLASH)
configure_file(
    ${CMAKE_SOURCE_DIR}/resources/Application.rc.in
    ${CMAKE_BINARY_DIR}/Application.rc
    @ONLY)

qt_add_executable(app_ptest src/main.cpp ${CMAKE_BINARY_DIR}/Application.rc)

# ⚠️ src/ 必须进包含路径。qt_add_qml_module 生成的类型注册文件用
# `#if __has_include(<file_io.hpp>)` 尖括号查找带 QML_ELEMENT 的头，
# 找不到就静默跳过 include、然后报 "'FileIo' was not declared in this scope"
# —— 错误信息指向生成的文件，看不出根因是包含路径。
# ⚠️ 带 QML_ELEMENT 的头所在目录都必须单独列进来——注册文件按**文件名**
# 尖括号查找（<cloud_client.hpp> 而非 <cloud/cloud_client.hpp>），
# 少列的表现是 "'CloudClient' was not declared in this scope"。
target_include_directories(app_ptest PRIVATE src src/cloud)

# qt_add_qml_module 只带进 Qml 依赖；QGuiApplication 来自 Gui、
# QQuickStyle 来自 QuickControls2，必须显式链，否则连头文件都找不到。
target_link_libraries(app_ptest PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    Qt6::Network
    Qt6::Multimedia)

# ⚠️ 这两段 set_source_files_properties 必须写在 qt_add_qml_module **之前**。
# 写在后面 CMake 不报错、构建也过，但属性静默失效 —— 单例不会被注册成单例，
# 运行期 Theme.brand / Theme.radius 全是 undefined，颜色圆角间距整体丢失。
# 且这个坑只在编译版出现，qml.exe 预览用的是手写 qmldir，看不出来。

# pragma Singleton 只是 QML 侧声明，构建系统这边也必须标。
set_source_files_properties(
    qml/Theme.qml qml/TypeScale.qml qml/Icons.qml qml/MockData.qml qml/Session.qml
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
        qml/Session.qml
        # 组件
        qml/Icon.qml
        qml/AppButton.qml
        qml/Card.qml
        qml/ConfirmDialog.qml
        qml/SequentialTestPanel.qml
        qml/FieldRow.qml
        qml/TestItemRow.qml
        qml/ResultBanner.qml
        qml/NavRail.qml
        qml/TopBar.qml
        qml/StepList.qml
        qml/LivePreview.qml
        qml/DeviceDiscoveryPanel.qml
        qml/Toast.qml
        qml/LiveFullscreen.qml
        # 页面
        qml/ViewFocus.qml
        qml/ViewFinished.qml
        qml/ViewInspect.qml
        qml/ViewRepair.qml
        qml/ViewPending.qml
        qml/ViewBatchFiles.qml
        qml/ViewAbout.qml
        qml/ViewCloudDebug.qml
        qml/ProductGate.qml
        qml/ViewLogin.qml
    SOURCES
        # 批次文件读写。QML 无文件写入 API，只把读/写下沉到 C++，
        # 解析与列语义留在 QML（列定义还没和产线定死，改 QML 不必重编 C++）。
        src/file_io.hpp
        src/file_io.cpp
        # 云链路层（2026-08-17 起）：CloudClient 是 QML 单例入口，指令串行 +
        # RequestId 闭环；传输可切换（Mock / 腾讯云 API3.0 直连），由 exe 同目录
        # cloud_config.json 决定，密钥文件不进 git。
        src/cloud/cloud_reply.hpp
        src/cloud/crc32.hpp
        src/cloud/i_cloud_transport.hpp
        src/cloud/tc3_signer.hpp
        src/cloud/tc3_signer.cpp
        src/cloud/mock_transport.hpp
        src/cloud/mock_transport.cpp
        src/cloud/tencent_api_transport.hpp
        src/cloud/tencent_api_transport.cpp
        src/cloud/cloud_client.hpp
        src/cloud/cloud_client.cpp
        src/cloud/factory_config.hpp
        src/cloud/factory_config.cpp
        # 调焦设备发现:UDP 广播搜索(CP3 老协议 7320/7319),ViewFocus 页用
        src/cloud/device_discovery.hpp
        src/cloud/device_discovery.cpp
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
