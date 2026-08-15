# P5 + P6 · C++ 后端（账户库/哈希/节流）与审计

| | |
|---|---|
| 状态 | 待做（真实实现期，与协议接入同期） |
| 前置 | P3/P4 的 UI 与流程已定型 |
| 落盘 | ✅ 已定：程序同目录（绿色版）。`./data/accounts.db` + `./data/ledger.db` **两个文件** |
| 产出 | `src/auth/*`、`src/audit/*`、SQLite schema |

## P5 · 账户后端

### T5.0 落盘布局（已定）

```
ProductTestTool.exe
data/
  accounts.db     ← 操作者账户(本批)
  ledger.db       ← 产测台账(R088)
  audit.db        ← 审计日志(P6;或并入 ledger.db)
profiles/
  CS7GV1.0.json   ← 产品 profile(管理员维护)
```

**必须分文件**：超级用户忘密的兜底是「删除 `accounts.db`」回到首启建号，
台账与审计不能跟着一起没了。

⚠️ **不要装进 `Program Files`**：那里默认不可写，写失败会被 UAC 静默虚拟化到
`%LOCALAPPDATA%\VirtualStore\...`，工人看到的是"保存成功"但文件在别处，
产线上极难排查。安装说明要写明装到可写目录（或直接用免安装 dist）。
启动时应自检 `data/` 可写，不可写就红警报错而不是静默失败。

### T5.1 SQLite 账户库

```sql
CREATE TABLE operators (
  emp_id       TEXT PRIMARY KEY,        -- 工号,字符串(前导零!)
  name         TEXT NOT NULL,
  role         TEXT NOT NULL,           -- super|engineer|tech
  pwd_hash     BLOB NOT NULL,           -- PBKDF2 输出
  pwd_salt     BLOB NOT NULL,           -- 每用户独立随机盐 ≥16 字节
  pwd_iters    INTEGER NOT NULL,        -- 迭代次数,存库以便将来提升
  must_change  INTEGER NOT NULL DEFAULT 0,
  disabled     INTEGER NOT NULL DEFAULT 0,
  created_at   TEXT NOT NULL,
  updated_at   TEXT NOT NULL
);
```

⚠️ **`emp_id` 必须 TEXT**。工号 `0045009` 有前导零，用 INTEGER 会变 45009。

**约束：`role='super'` 只允许一行**（建表加唯一索引或插入前检查）。
不可删除超级用户 —— 在 DAO 层拒绝，不靠 UI 藏按钮。

### T5.2 密码哈希

`QPasswordDigestor::deriveKeyPbkdf2(QCryptographicHash::Sha256, pwd, salt, iters, 32)`，
迭代 ≥100000。**不用 MD5/SHA1/Base64**（老软件的做法，等于明文）。

比对用**常量时间比较**，别用 `==`（时序侧信道；产线场景风险低，但成本也低）。

### T5.3 失败节流

同一工号连错 5 次 → 锁 30 秒（内存计数，进程重启清零即可，产线不需要跨重启持久化）。
锁定期间登录按钮禁用并显示剩余秒数。

### T5.3b 工号不校验格式（已定）

任意字符串即可，不强制位数/数字。**但存取必须按字符串**（见 T5.1 的 TEXT 约束）。

### T5.4 记住工号

`QSettings` 存**工号**，绝不存密码。

### T5.5 忘密兜底 + 管理员说明

超级用户忘密 = **删除账户库文件** → 回到首启建号流程。
必须写进管理员说明文档，并强调：**产测台账独立存放，删账户库不影响台账**。
这条是废除硬编码万能密码（老软件 `super_password = tenda_mfg` 写死在代码里）
的代价，也是它比万能密码更安全的原因 —— 兜底需要物理访问文件系统。

## P6 · 审计

### T6.1 流水与台账带操作者

指令流水每行、产测台账每条记录加两列：`operator_emp_id` / `operator_role`。
**在下发指令的那一刻取 `Session.user`**，不要在写库时再取 —— 中途换班会记错人。

### T6.2 四类独立审计日志

```sql
CREATE TABLE audit_log (
  id         INTEGER PRIMARY KEY AUTOINCREMENT,
  at         TEXT NOT NULL,            -- 本地时间 17 位
  emp_id     TEXT NOT NULL,
  role       TEXT NOT NULL,
  kind       TEXT NOT NULL,            -- repair_clear|skip_item|profile_edit|account_op
  device_sn  TEXT,                     -- 账号操作可为空
  params     TEXT,                     -- JSON
  reason     TEXT                      -- 跳过测试项必填
);
```

四类：**维修清除 / 跳过测试项 / profile 修改 / 账号操作**。

### T6.3 跳过测试项强制填原因

工程师点「跳过当前项」→ 弹原因输入（**不可为空**，不给"其他"这类免填选项）→
原因进 `audit_log.reason` 与产测台账。

理由：跳过是唯一能让不良品合法通过的口子，必须留下"为什么"。空原因的跳过记录
等于没记。

## 验收标准

- [ ] 工号 `0045009` 存取后前导零不丢
- [ ] 库里插不进第二个 super；删 super 被 DAO 拒绝
- [ ] 密码字段无明文；哈希/盐/迭代三者都落库
- [ ] 连错 5 次锁 30 秒，UI 显示剩余秒数
- [ ] 删账户库后回首启建号，且台账文件仍在、可导出
- [ ] 跳过测试项不填原因无法提交
- [ ] 换班后新指令记的是新操作者
