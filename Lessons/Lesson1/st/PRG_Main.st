(* =====================================================================
   对象类型 : POU（PRG，语言 ST）  对象名 : PRG_Main
   项目     : Lesson1
   任务     : MainTask（10 ms，优先级最高）
   纪律     : PRG 只做调度 —— 新命令交给 FB_CmdHandler 解析分发、
              周期驱动三轴、把状态发布到 GVL。
   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 PRG_Main
              -> 类型选"程序"（Program）-> 实现语言选 ST。
   粘贴方法 : 跳过下面第一行对象头（PROGRAM xxx），声明区（VAR 块）粘到
              编辑器上半部，"实现区"分隔线以下的内容粘到下半部。
   ===================================================================== *)
PROGRAM PRG_Main
VAR
    fbCmdHandler : FB_CmdHandler;
    fbAxis       : ARRAY[1..3] OF FB_SimAxis;   // 下标 = 轴号（1=X / 2=Y / 3=Z）
    i            : INT;
END_VAR
(* ---------------- 实现区（以下粘到 POU 编辑器下半部） ---------------- *)

// --- 1) 来了新命令：解析 + 分发 + 回执（接受与拒绝都回执、都回显序号）---
IF GVL.nCmdSeq <> GVL.nAckSeq THEN
    fbCmdHandler(stCmd := GVL.stCmd, aAxis := fbAxis);
    GVL.wResult := fbCmdHandler.wResult;
    GVL.nAckSeq := GVL.nCmdSeq;
END_IF

// --- 2) 周期驱动三轴，并把状态发布到 GVL（本任务唯一写者）---
FOR i := 1 TO 3 DO
    fbAxis[i](rCycleTime := 0.01);              // 与 MainTask 周期一致
    GVL.aAxis[i].rActPos    := fbAxis[i].rActPos;
    GVL.aAxis[i].rTargetPos := fbAxis[i].rTargetPos;
    GVL.aAxis[i].rVelocity  := fbAxis[i].rVelocity;
    GVL.aAxis[i].xMoving    := fbAxis[i].xMoving;
END_FOR
