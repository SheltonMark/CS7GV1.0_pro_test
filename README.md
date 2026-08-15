# 产测 PC 客户端

CS7G 系列低功耗电池 IPC 产线产测软件。Qt 6.8 + C++ + QML（FluentWinUI3 深色主题）。

**当前状态：只有 UI 外观，无业务逻辑。** 数据全部来自 `qml/MockData.qml`；协议
（腾达后台 HTTPS + 签名）、XP2P 拉流、Excel、SQLite、流程引擎都还没接。
协议契约见固件仓库 `battery_ipc/docs/product_test/产测物模型字段评审表.md`。

## 构建

```bash
sh build.sh
```

产物 = **`dist/` 整个文件夹**（~83 MB / 1106 文件），拷到任何 Win10/Win11 机器双击
`ProductTestTool.exe` 即可，不需要装 Qt。发给别人用 zip（压后 ~31 MB）：

```bash
cd dist && tar -a -c -f ../ProductTestTool_vX.Y.Z_日期.zip *
```

exe 本身只有 ~0.4 MB，其余全是 Qt 运行库 —— **单独拷 exe 跑不起来**。

### 环境（一次性）

```bash
pip install aqtinstall
cd /c/Qt   # 必须在可写目录下跑，否则 aqt 写日志权限失败
python -m aqt install-qt   windows desktop 6.8.3 win64_mingw \
    -m qtmultimedia qtimageformats qt5compat qtshadertools -O C:\Qt
python -m aqt install-tool windows desktop tools_mingw1310 -O C:\Qt
python -m aqt install-tool windows desktop tools_cmake     -O C:\Qt
python -m aqt install-tool windows desktop tools_ninja     -O C:\Qt
```

⚠️ 必须用 Qt 配套的 **GCC 13.1.0**（`tools_mingw1310`）。系统另装的 GCC 15.x
不能混用（C++ ABI），`build.sh` 已钉死并打印实际版本。

## 页面

导航顺序 = 产线流转顺序：**调焦 → 准成品 → 成品 → 检查 → 维修**，另有产品（多产品
profile + 测试项勾选）与关于（版本/联系人/企业微信跳转）。

- 测试项能力集三层收敛：**实际下发 = 产品 profile 勾选 ∩ 设备 SupportedItems**；
  勾了而设备未上报的标红「缺能力」提示查接线，**不静默跳过**。
- **整机产测通过的最终判据 = 四阶段时间戳齐全**（FocusTime/SemiTime/FinishTime/
  InspectTime 全非空，评审表 §4.10），代替「成品标识已写」。台账/导出报表要有
  InspectTime 列。
- 检查页三条已定协议（可用性不看 `Active`、超时重试复用同一 Timestamp + 新
  RequestId、mapper 层拒绝不回 ProductTestResult 靠超时兜底）见
  `qml/ViewInspect.qml` 头注释，实现时勿偏离。

## 实测坑（每一个都让程序坏过，改动前先读）

**QML/构建：**

1. `set_source_files_properties`（单例标记、资源别名）必须写在
   `qt_add_qml_module` **之前** —— 写在后面不报错但静默失效。
2. QML 单例的属性初始化不能调用同对象的自定义函数（`qmlcachegen` 编译版里
   属性变 undefined；解释执行的 qml.exe 预览却正常）。
3. QML 文件挪进子目录后同模块类型不再隐式可见，每个文件都要显式 `import ptest`。
4. 图标字形不能直接贴进源码（私有区字符会被编辑器/编码往返吃掉），必须
   `String.fromCharCode(码位)`。
5. `Button` 子类不能声明 `icon` 属性（基类 FINAL），本工程用 `glyph`。
6. QML 的 font 没有 `families` 回退链（赋值直接组件加载失败）——图标字体用
   `Qt.fontFamilies()` 运行时探测：Win11 用 Segoe Fluent Icons，**Win10 退
   Segoe MDL2 Assets**。所有用到的码位都已验证两字体全覆盖。
7. 嵌套 `ColumnLayout` 默认 `fillWidth:true`，固定宽度侧栏必须显式
   `Layout.fillWidth: false`，否则会把兄弟挤成几像素。

**部署：**

8. **不要依赖样式提供按钮背景色** —— FluentWinUI3 在部分机器上主题解析不同，
   曾出现白底白字。所有按钮用 `AppButton`（颜色全显式，primary/normal/danger）。
9. 强调色必须在根窗口 `palette.accent` 钉死（conf 文件里写 `Accent=` 无效），
   否则跟随系统强调色，系统色是红时与 FAIL 语义撞车。
10. `windeployqt` 中途失败仍返回 0 —— `build.sh` 部署到临时目录、自检关键
    DLL 后原子替换，缺件直接 fail。
11. `qml/QtQuick/Controls/Windows` 与 `Fusion` 不能删（FluentWinUI3 的基座）；
    `opengl32sw.dll`（20 MB）故意保留（低配机/远程桌面的软渲染兜底）。
12. **验证必须跑 `dist/` 里的 exe**。qml.exe 预览与编译版走不同的模块解析
    路径，预览正常完全不代表 exe 没坏（坑 1/2/3 都只在编译版发作）。

## 已知待办

- 企业微信跳转用 `wxwork://message?username=工号`，能唤醒已登录的企业微信；
  能否直达指定人会话无公开文档保证，「复制工号」按钮是永久兜底。
- SN 型号段带 `V1.0`（含点号）后，与流水号的边界解析、Excel 导出时点号/前导零
  的处理，等产线给出真实 SN 编码规则后一次定死（`MockData.qml` 有备注）。
- 数据写盘位置、三工位台账是否汇总中心库 —— 决定 SQLite 放哪，需产线拍板。
