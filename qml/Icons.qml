pragma Singleton
import QtQuick

// Segoe Fluent Icons 码位表(Windows 自带字体，约 1000 字形)。
//
// ⚠️ 必须用 String.fromCharCode(码位)，不能直接把字形贴进源码 ——
//    私有区字符在不同编辑器/编码往返中会被静默吃掉，变成空串，
//    表现为"图标全都不显示"且毫无报错。这个坑我踩过一次。
//
// 所有码位都用探针网格实际渲染确认过，不是照记忆写的。
//
// 不用自定义 ch() 辅助函数包装 —— 单例属性初始化时调用同对象方法，
// 在 qmlcachegen 编译版里会解析失败（属性变 undefined），
// 而解释执行的 qml.exe 里正常，属于典型的"预览没问题、exe 坏了"。
QtObject {
    // 图标字体运行时选择:Win11 用 Fluent,Win10 退 MDL2。
    // QML 的 font 类型没有 families 回退链(那是 C++ QFont 的 API,
    // QML 里赋值会直接报 non-existent property 且组件加载失败),
    // 所以用 Qt.fontFamilies() 查一次系统字体列表来选。
    readonly property string fontFamily:
        Qt.fontFamilies().indexOf("Segoe Fluent Icons") >= 0
            ? "Segoe Fluent Icons" : "Segoe MDL2 Assets"

    // ---- 导航 ----
    readonly property string navFocus:    String.fromCharCode(0xE722)  // 相机
    readonly property string navSemi:     String.fromCharCode(0xE9D9)  // 波形
    readonly property string navFinished: String.fromCharCode(0xE73A)  // 勾选框
    readonly property string navRepair:   String.fromCharCode(0xE90F)  // 扳手
    readonly property string navProduct:  String.fromCharCode(0xE7B8)  // 箱子
    readonly property string navAbout:    String.fromCharCode(0xE946)  // 信息

    // ---- 状态 ----
    readonly property string pass:     String.fromCharCode(0xE10B)  // 勾
    readonly property string fail:     String.fromCharCode(0xE10A)  // 叉
    readonly property string warning:  String.fromCharCode(0xE7BA)  // 警告三角
    readonly property string blocked:  String.fromCharCode(0xE711)  // 禁止
    readonly property string pending:  String.fromCharCode(0xE121)  // 时钟
    readonly property string running:  String.fromCharCode(0xE895)  // 同步
    readonly property string passRing: String.fromCharCode(0xE930)  // 圆圈勾

    // ---- 操作 ----
    readonly property string play:    String.fromCharCode(0xE768)
    readonly property string stop:    String.fromCharCode(0xE71A)
    readonly property string skip:    String.fromCharCode(0xE893)
    readonly property string save:    String.fromCharCode(0xE74E)
    readonly property string erase:   String.fromCharCode(0xE74D)  // 垃圾桶
    readonly property string reboot:  String.fromCharCode(0xE777)
    readonly property string reset:   String.fromCharCode(0xE72C)  // 刷新
    readonly property string copy:    String.fromCharCode(0xE8C8)
    readonly property string link:    String.fromCharCode(0xE71B)
    readonly property string add:     String.fromCharCode(0xE710)
    readonly property string chat:    String.fromCharCode(0xE8BD)  // 会话
    readonly property string history: String.fromCharCode(0xE81C)

    // ---- 设备/外设 ----
    readonly property string cloud:    String.fromCharCode(0xE753)
    readonly property string online:   String.fromCharCode(0xE701)  // wifi
    readonly property string device:   String.fromCharCode(0xE772)
    readonly property string speaker:  String.fromCharCode(0xE767)
    readonly property string mic:      String.fromCharCode(0xE720)
    readonly property string battery:  String.fromCharCode(0xE83E)
    readonly property string sd:       String.fromCharCode(0xE7F1)
    readonly property string signal4g: String.fromCharCode(0xE701)
    readonly property string light:    String.fromCharCode(0xE781)  // 报警灯(指示灯)
    readonly property string whiteLight: String.fromCharCode(0xE754)  // 手电筒(白光灯)
    readonly property string bulb:     String.fromCharCode(0xEA80)  // 灯泡(通用)
    readonly property string ir:       String.fromCharCode(0xE7B3)  // 眼
    readonly property string gimbal:   String.fromCharCode(0xE9F5)  // 齿轮组
    readonly property string button:   String.fromCharCode(0xE81D)  // 圆点
    readonly property string daynight: String.fromCharCode(0xE793)  // 亮度
    readonly property string person:   String.fromCharCode(0xE77B)

    // 测试项 bit → 图标
    function forItem(bit) {
        switch (bit) {
        case 0:  return light;      // 指示灯
        case 1:  return ir;         // 红外灯
        case 2:  return whiteLight; // 白光灯
        case 3:  return daynight;   // 日夜切换
        case 4:  return button;     // 复位按键
        case 5:  return battery;    // 电池
        case 6:  return gimbal;     // 云台
        case 7:  return speaker;    // 喇叭
        case 8:  return mic;        // 咪头
        case 9:  return signal4g;   // 4G 信号
        case 10: return sd;         // SD 卡
        default: return device;
        }
    }
}
