(* =====================================================================
   对象类型 : POU（FB，语言 ST）   对象名 : FB_CmdHandler
   项目     : Lesson2
   角色     : 命令处理：解析当前命令（GVL.stCmd），分发到命令槽。
              它只懂协议 —— 命令字合法吗、路数合法吗、轴号合法吗；不懂运动。
              与 Lesson1 的唯一结构差别：分发不再是"调轴的方法"（执行完事），
              而是"装弹 + 给沿"——把参数记进命令槽、给一拍 TRUE。
              原因：MC 功能块必须每周期被调用（块内部靠持续调用维护状态机），
              不能只在来帧的那一拍调；所以执行移到 PRG_Main 的周期驱动里。
              多路命令仍是两遍法：先整体校验，再逐路装弹 ——
              要么全收，要么全不收，不存在"动了一半"。
   协议     : bType = GVL.CMD_MOVE / GVL.CMD_STOP；bSub 预留填 0
              nLen  = 1..3（aParam 的有效路数）
              每路：bAxis = 1..3；MOVE 要求 rVel > 0（第一遍校验拦截）
   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 FB_CmdHandler
              -> 类型选"功能块"（Function Block）-> 实现语言选 ST。
   粘贴方法 : 跳过下面第一行对象头（FUNCTION_BLOCK xxx），声明区（各 VAR 块）
              粘到编辑器上半部，"实现区"分隔线以下的内容粘到下半部。
   ===================================================================== *)
FUNCTION_BLOCK FB_CmdHandler
VAR_INPUT
    stCmd   : Cmd;                          // 待处理的当前命令
END_VAR
VAR_IN_OUT
    aCmd    : ARRAY[1..3] OF ST_AxisCmd;    // 分发目标：三根轴的命令槽
END_VAR
VAR_OUTPUT
    wResult : WORD;                         // 处理结果码：GVL.OK 或结果码
END_VAR
VAR
    i       : INT;
    nAx     : INT;
END_VAR
(* ---------------- 实现区（以下粘到 POU 编辑器下半部） ---------------- *)
// 默认成功，走到哪步出错在哪步盖结果码
wResult := GVL.OK;

// --- 命令字（协议级校验）---
IF (stCmd.bType <> GVL.CMD_MOVE) AND (stCmd.bType <> GVL.CMD_STOP) THEN
    wResult := GVL.UNKNOWN_CMD;
    RETURN;
END_IF

// --- 有效路数 ---
IF (stCmd.nLen < 1) OR (stCmd.nLen > 3) THEN
    wResult := GVL.BAD_PARAM;
    RETURN;
END_IF

// --- 第一遍：整体校验全部路数（轴号；MOVE 还要速度 > 0）---
// 任何一路非法 -> 整体拒绝，一路都不装弹
FOR i := 1 TO TO_INT(stCmd.nLen) DO
    IF (stCmd.aParam[i].bAxis < 1) OR (stCmd.aParam[i].bAxis > 3) THEN
        wResult := GVL.BAD_AXIS;
        RETURN;
    END_IF
    IF (stCmd.bType = GVL.CMD_MOVE) AND (stCmd.aParam[i].rVel <= 0) THEN
        wResult := GVL.BAD_PARAM;
        RETURN;
    END_IF
END_FOR

// --- 第二遍：逐路装弹 + 给沿（校验已过，此处必成功）---
// 沿只高一拍：PRG_Main 调用运动块后当拍拉低；
// 运动中再来一帧 MOVE = 重新给沿，旧指令 CommandAborted，轴按新目标走
FOR i := 1 TO TO_INT(stCmd.nLen) DO
    nAx := TO_INT(stCmd.aParam[i].bAxis);
    CASE stCmd.bType OF
        GVL.CMD_MOVE:
            aCmd[nAx].rPos      := stCmd.aParam[i].rPos;   // 记参数（即状态帧的回显）
            aCmd[nAx].rVel      := stCmd.aParam[i].rVel;
            aCmd[nAx].xMoveTrig := TRUE;                   // 给沿
        GVL.CMD_STOP:
            aCmd[nAx].xHaltTrig := TRUE;                   // 给沿
    END_CASE
END_FOR
