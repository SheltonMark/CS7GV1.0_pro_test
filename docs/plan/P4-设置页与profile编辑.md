# P4 · 设置页（云凭证 + profile 编辑）

| | |
|---|---|
| 状态 | 待做（纯 UI；凭证真实存储在 P5） |
| 前置 | P1/P2；profile schema v2 见 P11 |
| 产出 | `qml/ViewSettings.qml` |

入口：导航栏底部「设置」，`visible: Session.canEditCredentials`（仅超级用户）。

## T4.1 后台 API 凭证配置

**这是软件级云凭证，不是操作者账号** —— 即腾达后台账号（PC 版 App 那个登录），
软件用它连云。超级用户配一次，全机所有操作者共用。

字段：后台地址 / 账号 / 密码 / （可能的）AppKey。UI 要点：

- 密码框 `echoMode: Password`，**不提供"显示密码"眼睛按钮**（产线电脑常有人围观）；
- 保存后只显示「已配置 · 最后更新 时间」，**不回显明文**；
- 提供「测试连接」按钮（P5 才真连，本批占位）。

存储（P5 落地）：Windows DPAPI 加密后落本地，**不与操作者账户库同表**。
明文绝不进 QSettings/ini/日志。

## T4.2 产品 profile 编辑

关于页现在是**只读**展示（P2 时的降级结果）。本批给超级用户加编辑入口。
可编辑字段（对齐 P11 的 schema v2）：

| 字段 | 说明 |
|---|---|
| `items` | 固定测试项集合（勾选 11 项中的哪些） |
| `expectedSwVersion` / `expectedHwVersion` | 期望版本，不符判不良（P10-①） |
| `thresholds.cellBarsMin` | 4G 信号格数下限（默认 2） |
| `thresholds.sdWriteMinMBps` / `sdReadMinMBps` | SD 读写速率下限（默认 2 / 5） |
| `enabled` | false = 启动门置灰（待建模产品） |

UI 要点：

- 编辑的是**当前会话产品**，改完提示「下次进入该产品生效」——
  不热改运行中的会话（会话上下文在选定时锁定，中途变更会让已下发指令与
  新集合不一致）；
- `productId` **不可编辑**（改它等于换产品，应该走新增 profile）；
- 保存 = 写 `profiles/<name>.json`；本批 mock 只改内存。

## 验收标准

- [ ] 工程师/技术员登录后**看不到**设置入口
- [ ] 凭证保存后不回显明文，无"显示密码"按钮
- [ ] profile 编辑不含 `productId`；保存提示"下次进入生效"
- [ ] 阈值字段有默认值与范围校验（bars 0-5，速率 >0）
- [ ] 编译版零告警

## 开放问题

- 后台 API 的实际字段（地址/账号/密码之外是否要 AppKey、region）
  等参考代码 `D:\tendasecuritypc` 的登录模块确认后回填。
