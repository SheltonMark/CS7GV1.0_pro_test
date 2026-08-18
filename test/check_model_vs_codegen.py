#!/usr/bin/env python3
"""比对「物模型 JSON」与「设备端 codegen」是否一致。

为什么需要：设备端 app/cloud/tencent/model_generated/iv_usrex.c 是按物模型生成的。
若云端导入的模型与固件里的 codegen 不是同一版，表现为「PC 下发云端受理成功、
设备端却没有对应回调」——这种错很难从日志看出来，但在这里一比就现形。

用法：
    python test/check_model_vs_codegen.py <model.json> [battery_ipc 根目录]

退出码 0 = 一致；1 = 有差异。
"""
import json
import re
import sys
from pathlib import Path

DEFAULT_IPC = Path(r"A:\AOV_AX615\battery_ipc")


def load_model(path: Path):
    model = json.loads(path.read_text(encoding="utf-8"))
    actions = {a["id"] for a in model.get("actions", [])}
    props = {p["id"] for p in model.get("properties", [])}
    # action 入参名：codegen 的 DeviceProperty .key 要与之逐字对应
    action_inputs = {
        a["id"]: [p["id"] for p in a.get("input", [])]
        for a in model.get("actions", [])
    }
    return actions, props, action_inputs


def load_codegen(ipc_root: Path):
    src = ipc_root / "app/cloud/tencent/model_generated/iv_usrex.c"
    if not src.exists():
        sys.exit(f"找不到 codegen: {src}")
    text = src.read_text(encoding="utf-8", errors="replace")
    actions = set(re.findall(r'\.pActionId\s*=\s*"([^"]+)"', text))
    # 只取**顶层**属性：sg_RO_/sg_RW_DataTemplate[N]。
    # struct 成员走 sg_<结构名>_DataTemplate[N]（如 sg_ProductTestInfo_DataTemplate），
    # 那些是嵌套字段名，物模型里不作为顶层属性出现——一并抓会造成大量假差异。
    props = set(
        re.findall(
            r'sg_R[OW]_DataTemplate\[\d+\]\.data_property\.key\s*=\s*"([^"]+)"', text
        )
    )
    # 每个 action 的入参数组：g_actionInput_<Action>[] = { {.key="X"}, ... }
    inputs = {}
    for m in re.finditer(
        r"g_actionInput_(\w+)\[\]\s*=\s*\{(.*?)\};", text, re.S
    ):
        inputs[m.group(1)] = re.findall(r'\.key\s*=\s*"([^"]+)"', m.group(2))
    return actions, props, inputs


def report(title, model_set, code_set):
    only_model = sorted(model_set - code_set)
    only_code = sorted(code_set - model_set)
    if not only_model and not only_code:
        print(f"  OK  {title}：{len(model_set)} 项完全一致")
        return True
    print(f"  差异 {title}：")
    for name in only_model:
        print(f"        物模型有、codegen 无: {name}  ← 固件收不到")
    for name in only_code:
        print(f"        codegen 有、物模型无: {name}  ← 云端不会下发")
    return False


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    model_path = Path(sys.argv[1])
    ipc_root = Path(sys.argv[2]) if len(sys.argv) > 2 else DEFAULT_IPC

    m_actions, m_props, m_inputs = load_model(model_path)
    c_actions, c_props, c_inputs = load_codegen(ipc_root)

    print(f"物模型 : {model_path}")
    print(f"codegen: {ipc_root / 'app/cloud/tencent/model_generated/iv_usrex.c'}")
    print()

    ok = True
    print("[1] action 集合")
    ok &= report("action", m_actions, c_actions)
    print("[2] 上报属性集合（codegen 只登记只读上报属性，物模型含可写项，故只查缺失方向）")
    missing = sorted(
        p for p in c_props if p not in m_props
    )
    if missing:
        ok = False
        print("  差异：codegen 要报、物模型无此属性（上报会被云端丢弃）：")
        for name in missing:
            print(f"        {name}")
    else:
        print(f"  OK  codegen 登记的 {len(c_props)} 个上报属性都在物模型里")

    print("[3] 产测 action 入参逐字比对")
    for action in sorted(a for a in m_actions & c_actions if a.startswith("Ptest")):
        want = m_inputs.get(action, [])
        got = c_inputs.get(action, [])
        if want == got:
            print(f"  OK  {action}: {want}")
        else:
            ok = False
            print(f"  差异 {action}:")
            print(f"        物模型 : {want}")
            print(f"        codegen: {got}")

    print()
    if ok:
        print("结论：物模型与固件 codegen 一致。")
    else:
        print("结论：**存在差异**，按上面逐条核对。云端导入的模型必须与固件同版。")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
