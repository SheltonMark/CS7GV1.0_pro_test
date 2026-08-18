#!/usr/bin/env python3
"""由 v2 物模型生成 v3：加两个只读属性，把产测日志送到 PC。

`PtestLastError`：最近一次**非指令类**失败的结构化摘要。
    PC 已能通过 ProductTestResult 拿到自己下发的每条指令的结果，真正缺的是
    「PC 没下发指令时发生的失败」——起机读卡失败、自检 4G/SIM/网络/云异常、
    写加密分区失败。这类失败当前只打 stderr（main.cpp:83-86、
    product_test_self_check.cpp:99），云端和 PC 都拿不到，而它恰恰最需要记录：
    那会儿 PC 还没建连，屏上什么都没有，只有语音。

`PtestLogTail`：产测流水日志的尾部原文，直接把设备端 ptest.log 的内容送到 PC。
    量级实测：一行约 52 字节（格式见 product_test_log.hpp:12-14），一整轮产测
    16~30 条 = 840~1575 字节，**2048 的 string 装得下一整轮**，不需要分片。
    模型里已有 max=2048 的先例（TimeZoneSetting.TimeZone）。
    注：腾讯 SDK 自带的日志上传（qcloud_iot_export_log.h 的 IOT_Log_Init_Uploader /
    IOT_Log_Upload）在本工程**用不了**——预编译库的 config.h 是
    `/* #undef LOG_UPLOAD */`，功能没编进 libiot_sdk.a，要用得重编 SDK。
    产测日志量小，走属性即可，不值得为它重编。

为什么现在就加：model_generated/README.md:17-18 的硬规则——
**必须先在控制台定义，设备再上报**，否则平台拒收 `406 property schema not found`。
而导入是手工操作，导两遍不如一遍导对。加了但固件还没上报 = 无害（云端收不到而已）。

用法：
    python test/make_model_v3.py <v2.json> <输出 v3.json>
"""
import json
import io
import sys
from collections import OrderedDict

# 与 ProductTestResult.Code 同一套取值，避免两处枚举各说一套
RESULT_CODE_MAPPING = OrderedDict([
    ("0", "成功"),
    ("1", "参数非法"),
    ("2", "状态不允许"),
    ("3", "Flash错误"),
    ("4", "不支持"),
])

PTEST_LAST_ERROR = OrderedDict([
    ("id", "PtestLastError"),
    ("name", "产测最近异常"),
    ("desc", "产测过程中非指令类失败的最近一条摘要（起机读卡/自检/上云/写分区）。"
             "指令类失败走ProductTestResult；本属性专供PC未下发指令时段的排障。"
             "纪律：Detail绝不含DeviceSecret等密钥"),
    ("mode", "r"),
    ("define", OrderedDict([
        ("type", "struct"),
        ("specs", [
            OrderedDict([
                ("id", "Stage"),
                ("name", "阶段"),
                ("dataType", OrderedDict([
                    ("type", "enum"),
                    ("mapping", OrderedDict([
                        ("0", "读工装卡"),
                        ("1", "启动自检"),
                        ("2", "上云"),
                        ("3", "写加密分区"),
                        ("4", "产测信息校验"),
                        ("5", "电量门"),
                    ])),
                ])),
            ]),
            OrderedDict([
                ("id", "Code"),
                ("name", "结果码"),
                ("dataType", OrderedDict([
                    ("type", "enum"),
                    ("mapping", RESULT_CODE_MAPPING),
                ])),
            ]),
            OrderedDict([
                ("id", "Detail"),
                ("name", "详情"),
                ("dataType", OrderedDict([
                    ("type", "string"),
                    ("min", "0"),
                    ("max", "127"),
                ])),
            ]),
            OrderedDict([
                ("id", "Ts"),
                ("name", "时间戳"),
                ("dataType", OrderedDict([
                    ("type", "int"),
                    ("min", "0"),
                    ("max", "2147483647"),
                    ("start", "0"),
                    ("step", "1"),
                    ("unit", "s"),
                ])),
            ]),
        ]),
    ])),
    ("required", False),
    ("from", "custom"),
])

PTEST_LOG_TAIL = OrderedDict([
    ("id", "PtestLogTail"),
    ("name", "产测日志尾部"),
    ("desc", "产测流水日志尾部原文（设备端ptest.log的最后若干行，管道分隔："
             "时间戳|请求号|指令|测试项|结果码|详情）。Seq每次更新自增，PC据此判断是否有新内容；"
             "设备只在失败或阶段完成时更新，不逐行上报。纪律：绝不含DeviceSecret等密钥"),
    ("mode", "r"),
    ("define", OrderedDict([
        ("type", "struct"),
        ("specs", [
            OrderedDict([
                ("id", "Seq"),
                ("name", "序号"),
                ("dataType", OrderedDict([
                    ("type", "int"),
                    ("min", "0"),
                    ("max", "2147483647"),
                    ("start", "0"),
                    ("step", "1"),
                    ("unit", ""),
                ])),
            ]),
            OrderedDict([
                ("id", "Text"),
                ("name", "日志原文"),
                ("dataType", OrderedDict([
                    ("type", "string"),
                    ("min", "0"),
                    ("max", "2048"),
                ])),
            ]),
        ]),
    ])),
    ("required", False),
    ("from", "custom"),
])


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    src, dst = sys.argv[1], sys.argv[2]

    with io.open(src, encoding="utf-8") as handle:
        model = json.load(handle, object_pairs_hook=OrderedDict)

    ids = [p["id"] for p in model["properties"]]
    added = [PTEST_LAST_ERROR, PTEST_LOG_TAIL]
    for prop in added:
        if prop["id"] in ids:
            sys.exit(f"v2 里已有 {prop['id']}，无需再加（是否传错了文件？）")

    # 紧跟 ProductTestResult 之后插入，保持产测属性聚在一起便于控制台核对
    anchor = ids.index("ProductTestResult") if "ProductTestResult" in ids else len(ids) - 1
    for offset, prop in enumerate(added):
        model["properties"].insert(anchor + 1 + offset, prop)

    with io.open(dst, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(model, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    names = " + ".join(p["id"] for p in added)
    print(f"已写出: {dst}")
    print(f"  属性 {len(ids)} → {len(model['properties'])}"
          f"（+{names}，插在 ProductTestResult 之后）")
    print(f"  事件 {len(model.get('events', []))}（不变）")
    print(f"  行为 {len(model.get('actions', []))}（不变）")
    print(f"  profile: {json.dumps(model.get('profile'), ensure_ascii=False)}")


if __name__ == "__main__":
    main()
