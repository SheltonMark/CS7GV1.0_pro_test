# 产测 PC 客户端

CS7G 系列低功耗电池 IPC 产线产测软件。Qt 6.8 + C++ + QML（FluentWinUI3 深色主题）。

**当前状态：UI 完整，业务链路半接。** 已接：腾讯云 API 链路（TC3 签名，指令
闭环/批次联动/等待态，另有 mock 传输层可离线跑）、心跳在线判定与诊断链路
（云调试页含设备「最近异常/日志尾部」展示，物模型 v3 属性，设备端稍后上报）、
调焦工位 UDP 广播搜设备 + RTSP 直拉（对齐 CP3 老协议）、检查/维修工位接云、
测试项勾选持久化（factory_config.json）。未接：XP2P 拉流（SDK 待要）、
Excel 导出、SQLite 台账。产品 profile 等静态数据仍在 `qml/MockData.qml`。
协议契约见固件仓库 `battery_ipc/docs/product_test/产测物模型字段评审表.md`。

## 构建

```bash
sh build.sh
```

产物 = **`dist/` 整个文件夹**（~248 MB / 1551 文件，其中 VLC 运行时约 137 MB），
拷到任何 Win10/Win11 机器双击
`ProductTestTool.exe` 即可，不需要装 Qt。发布 = dist **内容**直压 zip（无顶层
文件夹，压后 ~90 MB），放 `package/`（已 gitignore，zip 不进仓库）：

```bash
cd dist && tar -a -c -f ../package/ProductTestTool_vX.Y.Z_日期.zip *
```

PowerShell 等价写法（不想开 Git Bash 时用，`*` 同样保证无顶层文件夹）：

```powershell
sh build.sh                                    # 构建仍需 Git Bash
Compress-Archive -Path dist\* -DestinationPath package\ProductTestTool_v0.1.8_20260819.zip
```

版本号唯一来源 = CMakeLists `project(VERSION)`（exe 版本资源/标题栏/关于页同源），
zip 名里的版本必须与其一致，日期用打包当天；改过版本号要先重跑 `build.sh` 再压。
⚠️ 压包前先关掉运行中的 exe —— DLL 被占用会让压缩失败。
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

## 页面与会话模型

**启动第一屏 = 产品选择门**：列出已配置产品（CS6GV2.0 这类待建模的可见但置灰），
选定后锁定会话上下文（ProductId/测试项集合，真实实现还锁凭证与工装卡校验基准）进主界面。
顶栏常显当前产品；「切换产品」在**导航栏底部**（分隔线下、暗色）—— 会话级低频动作
不和顶栏的设备状态区（SN/在线）混排，防误触也防视觉抢占；二次确认后回启动门，
主界面整棵销毁，设备连接与指令流水随会话清空。开发联调可用 `--autoselect` 跳过启动门。

**二次确认覆盖**（`ConfirmDialog` 统一实现，取舍标准见其头注释）：写阶段标识
（调焦/检查）、咪头人工判定（听到了/没听到）、跳过当前项、恢复默认、定时重启、
清除分区、切换产品。高频可重来的动作（开始拉流/停止/开始自动化测试/重新读取）
刻意不设卡 —— 确认疲劳会让工人闭眼点 OK，反而失去保护。

主界面导航 = 纯工位流：**调焦 → 准成品 → 成品 → 检查 → 维修 → 关于**。
产品信息在关于页只读展示，无编辑入口。

- **每产品一份静态 profile**（真实实现 = 安装目录 `profiles/<产品>.json`，管理员随
  软件发布维护，普通工人不可编辑）：productId、显示名、固定测试项集合、
  后续可扩展工装卡模板。mock 里对应 `MockData.profiles`。
- 测试项三层收敛：**实际下发 = 工厂勾选 ∩ profile 固定项 ∩ 设备
  SupportedItems**（勾选入口 = 产品门卡片「测试项」按钮，管理员可见，存
  factory_config.json，产线也可直接改文件）；profile 要求而设备未上报 →
  标红「设备未上报能力，检查接线」并计不通过，**不静默跳过**；设备上报而
  profile 不含 → 不下发。
- **咪头不发指令**（`MockData.manualChecks` 的 `noCommand`，不发就不查能力位）：工人对
  设备喊话，PC 端经实时画面回传听到即通过（评审表 §4.5）。⚠️ CS7G 装壳后无网口（网线
  只有调焦工位能接），准成品/成品的画面与声音回传要走 XP2P（SDK 待要），接通前该项
  判定无声音依据。PC 侧音频通路已就绪（`LivePreview` 的 `audioOutput`）。
- **复位按键 = 人动作 + 设备判定**（`deviceJudged`，定稿 2026-08-18）：下发布防后工人
  **按住 3 秒**，设备检测到按键事件上报，PC 按 Code 自动判过、不出人工判定页；窗口期
  外一律判失败。设备端 libsys 按加密分区「成品标志位」分流——未置位（产测中）按 3 秒
  只上报不复位，已置位走原复位流程。能力位需含 bit4（Mock=0x6F5/1781）。
- **云台无电机，设备端注册桩执行体恒回成功**（定稿 2026-08-18），所以能力位报"支持"。
  不这么做的话 PC 按「设备缺能力」判废，整条流程卡在一个已知没有的硬件上。
  ⚠️ 云台桩、复位检测（libsys 分流）、XP2P 回传三条都依赖设备端 `battery_ipc` 同步实现。
- **设备准入**：上线先核对设备上报 ProductId 与会话产品，不符 → 顶栏红警
  「设备型号与当前产品不符」+ 全部工位页禁用（关于页保留）。
- **整机产测通过的最终判据 = 四阶段时间戳齐全**（FocusTime/SemiTime/FinishTime/
  InspectTime 全非空，评审表 §4.10），代替「成品标识已写」。台账/导出报表要有
  InspectTime 列。
- **成品写标识链顺序**（定稿 2026-08-18）：逐项测试 → 产测信息校验（写 InputData1
  该行身份 → 读回逐字段比对 + 采 IMEI）→ 采集信息入库（IMEI 写 InputData2）→
  写成品标识 → 配置清除 → 定时关机。**校验不一致不写成品标识**（该行不入库、
  IMEI 留空，设备转维修后批次行仍可用）；写标识失败可断点续走（只补写标识，
  不重写身份不重复入库）。
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
13. **构建前必须关掉正在运行的 `dist/ProductTestTool.exe`**。它锁住自己的 exe
    与已加载的 Qt DLL，最后那步整体替换 `dist/` 会删一半然后被 `set -e` 中断，
    留下被掏空的 `dist`（连 exe 都只剩 `.msys` 待删存根，重跑构建也修不回来，
    要手工删目录；A: 盘的删除还不会立即落地，得等一拍）。`build.sh` 已在编译前
    加占用检查提前 fail —— 判据是"能否以写方式打开 exe"，不按进程名查
    （MSYS 会把 `tasklist //FI` 的参数当路径处理）。
14. **深色不能靠跟随系统主题** —— FluentWinUI3 的 `Dialog` 在 Light 主题下
    背景**写死 white**（样式源码如此，钉 palette 拦不住），Win10 机器普遍被
    解析成 Light，弹窗全白底（实测：测试项配置弹窗 Win10 白 / Win11 深色黑）。
    `main.cpp` 已 `styleHints()->setColorScheme(Qt::ColorScheme::Dark)` 强制
    深色，所有机器走同一分支；新写弹窗不用逐个钉背景，但按钮仍必须走
    `AppButton`（坑 8 不因此失效）。

**拉流（libvlc）：**

15. **libvlc 的 `new`/`play`/`stop` 全是同步阻塞，绝不能在 UI 线程调用。**
    首次 `libvlc_new` 要扫插件目录建缓存（实测 5-8 秒），`player_stop` 还要等
    输入线程收尾 —— 现象是"双击 IP 后整个软件假死"，而且**转圈也停着不转**
    （事件循环被堵，动画不走），比没有转圈更像死机。已改：所有控制调用走
    专用控制线程（`vlc_stream_player.cpp` 的 `controlHub()`），`setSource()`
    立即返回、状态经队列信号回主线程；程序启动即后台预热运行时，把插件扫描
    的代价挪到开机而不是工人双击的那一刻。
16. **起播头几帧是灰底带彩斑的烂图，必须丢掉再显示。** RTSP over UDP 起会话
    时首个 IDR 的分片常丢，解码器拿 P 帧硬凑参考帧就是这个样子，要等下一个
    关键帧才刷干净。产线工人看到会以为镜头脏或机器坏。已改：预热窗口内一帧不送
    `QVideoSink`，界面停在转圈上；LIVE 徽标与收转圈都以"第一帧干净图已送出"
    为准，不是"连上了"。
    **纯按时长/帧数开窗是在猜关键帧到没到 —— 设备 GOP 比窗口长时，窗口到点
    放出去的仍是灰图，现象是起播后还要灰 1~2 秒（实测）。** 现在窗口 = 下限
    （800 ms 且 ≥12 帧）+ 逐帧内容判据 + 上限（4000 ms 强制放行）。内容判据
    `IsStillFlat()` 按 8px 网格数"与右邻居逐位相等"的比例，≥60% 判为仍是解码器
    灰底填充：真实画面有传感器噪声，不会大面积逐位相等 —— 比判"像不像 128"稳，
    不依赖解码器拿哪个值填。上限是为盖镜头/对白墙/平场标定这类真·平坦画面兜底，
    否则转圈永不收。改看内容后下限从 1500 ms 降到 800 ms，起播反而更跟手。
    **预热是起播一次性闸门，不是常驻滤镜 —— 整段只在"还没出过图"（`shown_`）
    时生效。** 忘了这个前提的表现很有迷惑性：第一帧清晰，然后画面卡住不动
    8~10 秒，中途还灰闪一次（实测）。原因是判据出图后仍在拦帧，画面就停在第一
    张；到 4000 ms 上限那一刻又恰好把一张灰图放行。同理 `SetupCb` 里的重新起算
    也必须限定在出图前：已经在放的流中途重协商时重新预热，会让画面重新卡数秒，
    比一两帧花屏难看得多。起播日志会打 `first clean frame WxH after Nms warmup`，
    带 `(ceiling)` 说明是被上限强放的（判据太严或该设备 GOP 特别长），调
    `kFlatPercent` / `kWarmupCeilMs` 就看这个数。
    **2026-08-20 产线口径定案：宁可多转几秒圈，也不许把灰图/卡住的图放上去。**
    据此判据改为只认正面证据 —— 过下限后要**连续 8 帧**同时满足"不平坦"且
    "与上一帧不同"（`ProbeLuma()` 一次采样同时出平坦度和采样点 hash，两帧 hash
    相同即画面没动）才放行，任一帧不合格就重新数；上限放宽到 10 s，平坦度阈值
    从 60% 收到 25%。为什么单帧判据不够：起播灰图上彩斑攒够了平坦度也会掉下来，
    单帧会被它骗过去，出图仍是灰的（实测）。另外 `network-caching` 300→600 ms
    治"画面一顿一顿"（主码流 2560x1472 H265，集显软解吃紧，缓冲太浅解码赶不上）
    —— **代价是调焦操作延迟同步变大约 0.3 秒，嫌不跟手就调回 300。**
    最后一轮（偶现"出图带一点灰、随即刷干净"）：平坦度阈值 25%→10%。这个量是
    *整帧里仍严格平坦的占比*，阈值 25 就等于允许出图时还有约四分之一画面是灰底
    —— 漏的就是这部分。真实画面逐位相等占比只有个位数，收到 10 仍有余量。
    同时把"等不到就放行"拆成三级：**连击 → 宽限（10 s，放弃连击与"在动"要求，
    但仍拦住 ≥85% 平坦的明显灰底）→ 死线（15 s，无条件放行）**。85% 这条线只有
    解码器灰底够得着（严格逐位平坦，实测 95%+），真实平坦场景（白墙、过曝天空）
    有噪声，落在 30~60%。留死线级是因为转圈无限转会被工人当成软件卡死 —— 宁可
    给一张烂图。起播日志 `first frame WxH after Nms warmup (原因, flat=N%)`
    会直接说明走的哪一级，调阈值就看这两个数。
17. **全屏不能新开一个播放器实例** —— 那等于第二路拉流，而 `sourceUrl` 没接
    就是永久黑屏（曾如此）。已改：`LiveFullscreen` 把页面里正在播的
    `LivePreview` 整体重挂（reparent）到顶层，退出时挂回原位，同一路会话、
    同一个解码器。页面侧预览必须包一层槽位 `Item`：直接挂在 `ColumnLayout`
    下时，挂回来会被排到布局末尾。
18. **全屏用 `PreserveAspectFit`，小窗才用 `PreserveAspectCrop`。** 全屏窗口比
    视频更宽（1080p 满屏约 1.93 : 视频 1.74），Crop 会从上下裁，正好吃掉顶部
    OSD 时间戳和底部 Tenda logo 下缘（实测）—— 全屏本就是为看清四角和 OSD，
    裁边违背目的。另：LIVE 徽标靠**右**上角，左上角是设备烧进画面的时间戳。
19. 视频圆角要用 `MultiEffect` 遮罩，`clip: true` 只做矩形裁剪 —— Crop 占满后
    视频的方角会压在 `Rectangle` 的圆角之外。新增 `QtQuick.Effects` 依赖，
    `windeployqt --qmldir` 会自动收进包（已验证 `dist/qml/QtQuick/Effects`）。

## 已知待办

- 企业微信跳转用 `wxwork://message?username=工号`，能唤醒已登录的企业微信；
  能否直达指定人会话无公开文档保证，「复制工号」按钮是永久兜底。
- SN 型号段带 `V1.0`（含点号）后，与流水号的边界解析、Excel 导出时点号/前导零
  的处理，等产线给出真实 SN 编码规则后一次定死（`MockData.qml` 有备注）。
- 数据写盘位置、三工位台账是否汇总中心库 —— 决定 SQLite 放哪，需产线拍板。
