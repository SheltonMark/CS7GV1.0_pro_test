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

**云拉流（XP2P，无网口产品如 CS6GV2.0 的调焦画面）：**

20. **拉流通道按产品分流：带网口（`focusRtsp:true`，CS7GV1.0）走 RTSP 直拉，
    无网口走云。** 云路径 = 腾讯 XP2P SDK（`dist/xp2p/app_interface.dll`）在本机
    起一个 http-flv 转发服务，拿到 `http://127.0.0.1:PORT/ipc.flv?...` 的**本机
    URL**，再交给同一个 `VlcStreamPlayer` 播放 —— 播放层与 XP2P 完全解耦，libvlc
    的坑（15~19）同样适用。建联序列（`startService` → `setDeviceXp2pInfo` →
    等 `DetectReady(1004)` → `delegateHttpFlv`）照搬参考实现 `D:\tendasecuritypc`
    的 `TencentIotMgr` / `p2p_sample`，落在 `src/stream/xp2p_client.cpp`。
21. **xp2p_info 必须走腾达后台取，绕不开云账号登录。** 曾以为
    `setDeviceXp2pInfo(id, NULL)` 能让 SDK 自取、从而免掉登录（据此还删掉过一条
    "等后台授权"的阻塞项），实测是错的 —— 见第 26 条。正路：
    `/td/td-device-api/se-device/p2pToken/get/v1`，实现在
    `src/cloud/tenda_cloud_client.cpp`，三段式 check-v2 取主账号与 encrypt_mode
    → password-login 拿 `access_token` → 带 `Bearer` 取 p2pToken。密码哈希是
    sha1(用户名) 当 20 字节盐 + 密码按 4 字节对齐补零，5 轮 MD5（前 4 轮喂原始
    摘要，末轮取 hex），复刻参考实现 `EncryptUtil.cpp:124`。
    - `cloud_config.json` 的 `tenda.account` / `password` 配好即可，**不用手贴
      xp2p_info**（2026-08-20 实测：只配账号密码就出图）。`xp2pInfo` 字段保留作
      临时手段 —— 票据是会话级的、几分钟就变，填了会优先用它。
    - 业务码 `100012` 报「Header头部信息有误，请检查」其实是**缺 Authorization**，
      别去查 `sig`（A/B/C curl 对比实证，白查过一轮）。`100410`/`100412` 是
      token 过期/解析失败，自动重登一次再试。
    - 账号必须在**安全云**注册过，否则一律 `100421`（`15059242592` 在 cn/sa/eu/us
      四个区全 `100421`，换测试账号即通）。
    - `access_token` 与 `xp2p_info` 都是敏感值，日志**只记长度不记值**。
    - XP2P 的 app_id/app_key 仍是参考实现那对测试凭据，在 `xp2p_client.cpp` 顶部
      常量，产线定案后挪进 `cloud_config.json`。
22. **SDK 动态加载（`LoadLibrary`）而非链接导入库。** 纯 C 接口、C ABI 跨编译器
    兼容，绕开 MSVC `.lib` 与 MinGW 链接不兼容；且 DLL 缺失时 `Xp2pClient.available`
    为假、按钮点了提示"SDK 未就绪"，不拖垮产测其余工位。就绪等待用异步回调 +
    `QTimer` 超时（10s），**不用参考实现那种嵌套 `QEventLoop`**（QML 单线程里会
    重入/假死，方案 §7.1）。
23. **`app_interface.dll` 链的是 MSVC 运行时**（`MSVCP140`/`VCRUNTIME140[_1]`，
    `objdump -p` 实证）。产线机不一定装 VC++ 可再发行组件，缺了 `LoadLibrary` 直接
    失败。`build.sh` 把这三个 DLL 从 `System32` 复制到 `dist/xp2p/`（与
    `app_interface.dll` 同目录，靠 DLL 搜索顺序兜住），不依赖系统装没装。
24. **离开工位/切设备/停止都必须 `Xp2pClient.stop()`。** 同一设备的并发拉流有上限
    （`maxConnectNum`），不收会占着名额，下次拉会 `StreamEnd(1008)` 被拒 —— UI
    提示"可能被其他工位占用"而不是笼统"失败"（方案 §1.2）。
25. **云拉流 `quality` 取 `super`（主码流）。** 合法值 `standard`/`high`/`super`
    （`iv_av_cli_v2.h:69`），但服役实现 `BL_TencentLivePlayControl.cpp:19`
    `mapLiveQuality()` 只发两个：子码流 `standard`，其余一律 `super`。调焦要看
    清晰度边界，用主码流。URL 只拼 `action=live&quality=xxx`（对齐
    `TencentIotMgr::composeLiveUrl`，它连 crypto 都 `Q_UNUSED` 掉），不带
    `&channel=0&_crypto=off`。
    注：`quality` 曾被当成"卡 0%"的元凶试了三个值，全都无效 —— 真因见下一条，
    请求根本没发出去，改它当然没用。后来"缓冲 100% 不出画面"时又怀疑过一轮
    （想换 `standard` 取子码流避开 H.265），同样是错的方向：`super` 在参考实现里
    就是主码流的合法取值，且子码流默认也是 H.265（`media_config.hpp:24`），
    换 quality 躲不开。真因见第 28 条。
26. **`setDeviceXp2pInfo(id, NULL)` 让 SDK 自取 xp2p_info，在我们这类产品上
    行不通 —— 两个腾讯平台不是一回事。** 这是云拉流卡「缓冲 0%」的真因，
    日志实测：
    ```
    setDeviceXp2pInfo rc=-1001            # XP2P_ERR_GET_XP2PINFO
    [requestXP2PInfo]: request xp2p info for 5KHBENFCX2 1000000003
    [parseXP2PInfo]: no data on response   # 云端返回空
    [_set_remote_xp2pinfo]: request xp2p_info failed, errmsg:parse reply error
    [operator ()]: proxy_server_post error:invalid xp2pinfo parameter
    ```
    SDK 内置的自取走**物联网视频服务（IoT Video）**，而我们的设备在**物联网
    开发平台（IoT Explorer）**上（`iotexplorer.tencentcloudapi.com`，产品
    `5KHBENFCX2`）—— 两个平台产品空间不通，查不到就返回空。参考实现之所以没
    暴露这个坑：它**从不自取**，总是先从腾达后台拿真 xp2p_info 再
    `setDeviceXp2pInfo`（`TencentIotMgr.cpp:170-196`，取空即返回），它虽然也调
    `setQcloudApiCred`，那条自取路径它压根没走过。
    - **`DetectReady(1004)` 会照常上报 `{"mode":"ready"}`，它只代表本机代理起来
      了，不代表到设备的链路可用。** 别拿它当"建联成功"的证据 —— 正因为它来了，
      前面才误判成"隧道没问题，是设备不推流"，白试了三个 `quality`。没有
      xp2p_info 时代理对每个请求回 `invalid xp2pinfo parameter`，请求根本没出
      本机，所以既没有 `StreamEnd(1008)` 也没有 `DetectError(1005)`，只有干等。
    - 结论：xp2p_info 必须由**我们**取到并显式传进去，走 IoT Explorer 的接口
      （设备侧这个值是 P2P 票据、每次会话变化，与小程序要手填的那个 id 同源）。
27. **排障日志：程序是 `WIN32_EXECUTABLE`，双击运行时 `stderr` 没有去处。**
    以前写的 `fprintf(stderr, …)` 在正常使用中**全部丢失**，这是"没有日志可分析"
    的根因。现在两条出口（`src/stream/stream_log.*`）：
    - 落盘 `dist/logs/ptest_<时间>.log`（`main.cpp` 的 `InstallFileLog()` 用
      `freopen` 劫走整个 `stderr`，所以 libvlc 的 `LogCb`、XP2P SDK 的
      `setLogEnable`、Qt 的 `qDebug` 全都进同一个文件），只留最近 20 个；
    - 调焦页「拉流日志」（`qml/StreamLogPanel.qml`）：页面上**只有一个按钮**，
      和「开始拉流」「停止」同排；正文与「复制全部」「清空」全在模态框里，
      两个动作都有 toast 回执。关掉整块：`ViewFocus.qml` 的
      `showStreamDebug` 置 false。
      - ⚠️ **不要把它做成页面里独立的一行。** 曾经如此，把预览挤矮约 30px，而
        小窗是 `PreserveAspectCrop`，一矮就从上下裁，正好吃掉画面顶部的 OSD
        时间戳和底部 Tenda logo 下缘（同第 18 条那个坑）。按钮行是工人的主操作
        区，排障用的东西不该跟它抢位置。
      - 复制走 C++ 的 `StreamLog::copyToClipboard()`。早先靠一个隐藏 `TextArea`
        的 `selectAll()+copy()` 代劳，那要求控件常驻存活 —— 正是这个实现细节
        逼出了"必须占一行"的布局。
      - 模态框里的 toast 必须放在**弹出层内部**：页面级 `Toast` 在 overlay
        之下，模态框一开就被压住看不见。
      - 成品/准成品页**不放**日志入口：那两站画面只是确认"图出来了"，真要查
        日志去调焦工位。小窗里塞按钮既挡画面又和「双击全屏」角标撞位。
    `PTEST_STREAM_DEBUG=1` 额外放开 libvlc 全量日志与 XP2P SDK 日志，并启用
    建联后的 `get_device_st` 探测（阻塞 5s，故默认不开）。**注意 libvlc 的日志
    等级要在 `libvlc_new` 时用 `-vv` 打开** —— 只在 `LogCb` 里放行 debug 级是
    收不到的，引擎压根不发。另：解复用器选型与轨道 fourcc 那几行即使是 debug
    级也会提到面板上（前缀 `[vlc·demux]`），判"画面出不来"全靠它们。
28. **随包的 VLC 是 ffmpeg 4.4，解不了 HEVC-in-FLV —— 云拉流"缓冲 100% 不出
    画面"的真因。** 票据灌对、隧道通、心跳正常、缓冲跑满 100%，却一帧不出。
    判据是 `could not identify codec` / `Unidentified codec`，这是 VLC
    `decoder.c` 里 `fmt->i_codec == VLC_CODEC_UNKNOWN` 的专属分支 ——
    **解复用器建出了轨道但给不出 fourcc**，不是缺解码器（`libavcodec_plugin.dll`
    在，RTSP 的 H.265 就是它软解的）。
    - 我们这套 VLC 没有 `libflv_plugin.dll`，FLV 靠编进 `libavcodec_plugin.dll`
      的 avformat 模块解。版本串 `Lavc58.1` / `Lavf58.76.100` = **ffmpeg 4.4**，
      没有扩展视频标签头解析（`ex_header`、`multitrack` 两个串只在新版二进制里
      有）。主码流 2560x1472 H.265 进 FLV 走的正是这条路。
    - 已换成参考实现那份 **ffmpeg 8**（`Lavc62.2` / `Lavf62.12.100`，ffmpeg 静态
      编进插件、无外部 ffmpeg DLL 依赖 —— 那 128 MB 不是 debug 版）。换之前核过
      兼容性，不是硬塞：插件 ABI 入口两边同为 `vlc_entry__3_0_0f`；`objdump -p`
      解 PE 导入表，两份都只从 libvlccore 导入**同样的 66 个符号**，新插件不需要
      任何 3.0.24 才有的符号。ffmpeg-4 原件留在
      `dist/vlc/libavcodec_plugin.ffmpeg4.bak`（必须放在 `plugins/` **之外**，
      否则 VLC 会去探它）。
    - ⚠️ **这是个隐形依赖**：`build.sh` 优先复用已有 `dist/vlc`，`dist/` 一旦被
      清掉就悄悄退回 ffmpeg-4，画面再次消失且毫无线索。所以 `build.sh` 每次构建
      都校验插件里有没有 `ex_header`，缺了就从参考实现取、取不到就告警。
      2026-08-20 dist 被误删重建时这道校验实际生效了一次，没有它就静默回退。
      判据用 `ex_header` 而不是版本串：ffmpeg-8 二进制里同时含 `Lavf57`/`Lavf62`
      等多个串，按老版本号匹配会永远命中、每次构建白拷 125MB。
    - 代价：dist 从 251 MB 涨到 **357 MB**（那份插件没 strip）。
    - 另需两个媒体参数（抄参考实现 `BL_TencentLivePlayControl.cpp:357-359`，
      **只对 http 源加，别动已调好的 RTSP**）：`:clock-jitter=0` 关掉
      `input_clock.c` 的抖动护栏 —— 设备侧音频送的是**绝对**时间戳（实测
      `2444148201000`），护栏一律判超界丢弃并报 `Timestamp conversion failed
      (delay …, bound 3000000)`，而音频是主时钟，于是永久停在 100%；
      `:clock-synchro=1` 让时钟跟着流里的 PCR 走，不自己猜。
    - 排查时走过的弯路：先怀疑"打包漏了 flv 插件"（错，参考实现同样没有
      `libflv_plugin.dll`，插件数同为 47）；又断言"这套 VLC 放不了 H.265"（错，
      没核对参考实现的 ffmpeg 版本就下结论）。真正的差量只有 ffmpeg 版本。
29. **成品/准成品的实时画面一律走云，且必须手动起播。** 不看
    `profile.focusRtsp` —— 那个开关只描述"调焦工位的裸机有网口"这一个场景；到了
    这两站壳已套上、网口被挡，CS7GV1.0 与 CS6GV2.0 都只能走 XP2P（2026-08-20
    与产线确认）。
    - 起播是画面中心的播放按钮（`LivePreview.showPlayButton`），不自动拉：拉流
      占着设备的并发名额（第 24 条），而这两站大部分时间在跑逐项测试、没人看
      画面。失败走 toast，然后回到播放按钮。
    - `LivePreview.connecting` 必须由页面喂 `Xp2pClient.connecting`。云拉流是
      先建联、拿到 URL 才赋 `sourceUrl`，这段时间 `streaming` 仍是假 —— 不喂
      这个值，点了按钮到出画面之间转圈不转、按钮还在，像是没反应。
    - ⚠️ **每个用 `Xp2pClient` 的页面，`Connections` 都必须加
      `enabled: root.visible`。** 工位页常驻不销毁（`Main.qml` 只切 `visible`），
      而 `Xp2pClient` 是单例：漏了这条，后台页面照样收到别的工位触发的
      `onLiveUrlReady`，于是**同一个 URL 被两个播放器同时打开**、两个 HTTP GET
      打本机代理。设备只维持一路直播会话，第二个请求进来就把第一个踢掉 ——
      现象是"刚出图就断"，日志里同一 URL 相隔 8ms 打开两次、缓冲/cipher
      init/nettype 全部成对出现。
    - 事件 1008 `StreamEnd` 的原因**照抄设备的 msg，别猜**。曾自作聪明写成
      "设备停止推流，或已达最大连接数（可能被其他工位占用）"，而设备实际说的是
      `{"mode":"device end stream"}` —— 那句猜测文案把上面那个"两个播放器"的
      bug 误导成了名额问题，白查一轮。猜测性文案比没有文案更坏。
    - 卡片高度按各部分显式相加（内距*2 + 标题 + Card 自带间距 + 额外间距 +
      画面），不要用 `180 + s6 + s4` 那种凑出来的数：那样算出的内容区比槽位写死
      的 180px 还小 11px，槽位往上溢就把标题顶住了（现象："实时画面"和画面贴在
      一起）。槽位要 `anchors.fill` 内容区，别写死高度跟卡片算出来的值打架。

## 已知待办

- 企业微信跳转用 `wxwork://message?username=工号`，能唤醒已登录的企业微信；
  能否直达指定人会话无公开文档保证，「复制工号」按钮是永久兜底。
- SN 型号段带 `V1.0`（含点号）后，与流水号的边界解析、Excel 导出时点号/前导零
  的处理，等产线给出真实 SN 编码规则后一次定死（`MockData.qml` 有备注）。
- 数据写盘位置、三工位台账是否汇总中心库 —— 决定 SQLite 放哪，需产线拍板。
