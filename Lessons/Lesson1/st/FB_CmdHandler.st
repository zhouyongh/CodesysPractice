(* =====================================================================
   对象类型 : POU（FB，语言 ST）   对象名 : FB_CmdHandler
   项目     : Lesson1
   角色     : 命令处理：解析当前命令（GVL.stCmd），分发到具体的处理者。
              它只懂协议 —— 命令字合法吗、路数合法吗、轴号合法吗；不懂业务。
              MOVE / STOP 是轴命令，业务在轴的方法（MoveTo / Stop）里；
              将来命令集合扩张（新 bType、bSub 取值、非轴命令）时，
              新增对应的处理类、加分支即可，本类结构不变。
              多路命令采用两遍法：先整体校验，再逐路执行 ——
              要么全执行，要么全不执行，不存在"动了一半"。
   协议     : bType = GVL.CMD_MOVE / GVL.CMD_STOP；bSub 预留填 0
              nLen  = 1..3（aParam 的有效路数）
              每路：bAxis = 1..3；MOVE 要求 rVel > 0（轴自己也会再判一道）
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
    aAxis   : ARRAY[1..3] OF FB_SimAxis;    // 分发目标：命令最终作用在轴上
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
// 任何一路非法 -> 整体拒绝，一路都不执行
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

// --- 第二遍：逐路分发执行（校验已过，此处必成功）---
FOR i := 1 TO TO_INT(stCmd.nLen) DO
    nAx := TO_INT(stCmd.aParam[i].bAxis);
    CASE stCmd.bType OF
        GVL.CMD_MOVE:
            wResult := aAxis[nAx].MoveTo(stCmd.aParam[i].rPos,
                                         stCmd.aParam[i].rVel);
        GVL.CMD_STOP:
            aAxis[nAx].Stop();
    END_CASE
END_FOR
