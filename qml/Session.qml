pragma Singleton
import QtQuick

// 会话上下文。启动门选定产品后锁定,null = 仍在启动门。
//
// 切换产品 = 置回 null → Main 里挂主界面的 Loader 随之卸载,设备连接、
// 指令流水、各页状态整棵销毁 —— "切产品即换会话"靠对象生命周期保证,
// 不靠逐个清理(会漏)。
//
// 真实实现:选定时一并锁定 云端凭证、工装卡校验基准、测试项集合;
// profile 来自安装目录 profiles/*.json(管理员随软件发布维护)。
QtObject {
    property var profile: null
}
