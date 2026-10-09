(* =====================================================================
   对象类型 : POU（PRG，语言 ST）  对象名 : PRG_Main
   项目     : Lesson2
   任务     : MainTask（10 ms，优先级最高）
   纪律     : PRG 只做调度 —— 新命令交给 FB_CmdHandler 装弹给沿、
              每周期驱动 MC 功能块、把状态发布到 GVL。
   换芯对照 : Lesson1 的 fbAxis(FB_SimAxis ×3) 退役，换成
              fbPower/fbMove/fbHalt(MC 功能块，每轴一套) + 三根虚拟轴；
              TCP、GVL 协议变量、上位机零改动。

   轴引用方式：直接写 Drive_X/Y/Z，不做 REFERENCE/POINTER 中转 ——
     虚拟轴的轴变量实类型是 AXIS_REF_VIRTUAL_SM3（AXIS_REF_SM3 的子类型）；
     子类型变量直接传给 MC 块的 VAR_IN_OUT 是允许的，编译器认；
     但一旦经 REFERENCE/POINTER 中转就两重碰壁：
       IN_OUT 只认"同名同类型的真变量"，指针本身顶不上，报 C0201
       （类型 'POINTER TO AXIS_REF_VIRTUAL_SM3' 不等于 'AXIS_REF_SM3'）；
       指针变量又不是结构化变量，取 .fActPosition 报 C0062/C0032。
     三根轴写死展开：比多一层会坑人的间接更清楚。

   前置步骤（工程里做一次，IDE 操作）:
      1) 库管理器添加 SM3_Basic（MC_Power / MC_MoveAbsolute / MC_Halt
         都在这个库）；
      2) 设备树 Application 下添加三根 SoftMotion 虚拟轴 SM_Drive_Virtual，
         设备名分别取 Drive_X / Drive_Y / Drive_Z，对应 1=X / 2=Y / 3=Z；
         添加时 IDE 自动生成轴变量 Drive_X/Y/Z
         （类型 AXIS_REF_VIRTUAL_SM3，全局按设备名直接访问）；
      3) 虚拟轴不走总线，MC 块放在本任务（10ms 周期）即可。
   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 PRG_Main
              -> 类型选"程序"（Program）-> 实现语言选 ST。
   粘贴方法 : 跳过下面第一行对象头（PROGRAM xxx），声明区（VAR 块）粘到
              编辑器上半部，"实现区"分隔线以下的内容粘到下半部。
   ===================================================================== *)
PROGRAM PRG_Main
VAR
    fbCmdHandler : FB_CmdHandler;
    aCmd         : ARRAY[1..3] OF ST_AxisCmd;       // 命令槽：handler 装弹，本程序取用

    // ---- MC 功能块：每根轴一套（块内部有状态，不能共用）----
    fbPower      : ARRAY[1..3] OF MC_Power;         // 使能，常驻
    fbMove       : ARRAY[1..3] OF MC_MoveAbsolute;  // 绝对定位
    fbHalt       : ARRAY[1..3] OF MC_Halt;          // 停止

    i            : INT;
END_VAR
(* ---------------- 实现区（以下粘到 POU 编辑器下半部） ---------------- *)

// --- 1) 来了新命令：解析 + 装弹给沿 + 回执（接受与拒绝都回执、都回显序号）---
IF GVL.nCmdSeq <> GVL.nAckSeq THEN
    fbCmdHandler(stCmd := GVL.stCmd, aCmd := aCmd);
    GVL.wResult := fbCmdHandler.wResult;
    GVL.nAckSeq := GVL.nCmdSeq;
END_IF

// --- 2) 使能常驻：上位机的命令集里没有"使能"，
//     上位机零改动的前提是下位机自己把能上了 ---
fbPower[1](Axis := Drive_X, Enable := TRUE,
           bRegulatorOn := TRUE, bDriveStart := TRUE);
fbPower[2](Axis := Drive_Y, Enable := TRUE,
           bRegulatorOn := TRUE, bDriveStart := TRUE);
fbPower[3](Axis := Drive_Z, Enable := TRUE,
           bRegulatorOn := TRUE, bDriveStart := TRUE);

// --- 3) 运动块：Execute 接命令槽的沿（只高一拍）。
//     加/减速度是用户单位/s²，先拍 500，工程里按轴调 ---
fbMove[1](Axis := Drive_X, Execute := aCmd[1].xMoveTrig,
          Position := aCmd[1].rPos, Velocity := aCmd[1].rVel,
          Acceleration := 500, Deceleration := 500);
fbMove[2](Axis := Drive_Y, Execute := aCmd[2].xMoveTrig,
          Position := aCmd[2].rPos, Velocity := aCmd[2].rVel,
          Acceleration := 500, Deceleration := 500);
fbMove[3](Axis := Drive_Z, Execute := aCmd[3].xMoveTrig,
          Position := aCmd[3].rPos, Velocity := aCmd[3].rVel,
          Acceleration := 500, Deceleration := 500);
fbHalt[1](Axis := Drive_X, Execute := aCmd[1].xHaltTrig, Deceleration := 500);
fbHalt[2](Axis := Drive_Y, Execute := aCmd[2].xHaltTrig, Deceleration := 500);
fbHalt[3](Axis := Drive_Z, Execute := aCmd[3].xHaltTrig, Deceleration := 500);

// --- 4) 状态发布：轴属性是 LREAL，线上格式是 REAL，显式收窄别靠隐式转换；
//     字段来源与手搓轴不同，字节布局不变（本任务唯一写者）---
GVL.aAxis[1].rActPos    := LREAL_TO_REAL(Drive_X.fActPosition);
GVL.aAxis[1].rVelocity  := LREAL_TO_REAL(Drive_X.fActVelocity);
GVL.aAxis[1].rTargetPos := aCmd[1].rPos;            // 命令回显（最近一次 MOVE）
GVL.aAxis[1].xMoving    := fbMove[1].Busy OR fbHalt[1].Busy;  // 运动中
GVL.aAxis[2].rActPos    := LREAL_TO_REAL(Drive_Y.fActPosition);
GVL.aAxis[2].rVelocity  := LREAL_TO_REAL(Drive_Y.fActVelocity);
GVL.aAxis[2].rTargetPos := aCmd[2].rPos;
GVL.aAxis[2].xMoving    := fbMove[2].Busy OR fbHalt[2].Busy;
GVL.aAxis[3].rActPos    := LREAL_TO_REAL(Drive_Z.fActPosition);
GVL.aAxis[3].rVelocity  := LREAL_TO_REAL(Drive_Z.fActVelocity);
GVL.aAxis[3].rTargetPos := aCmd[3].rPos;
GVL.aAxis[3].xMoving    := fbMove[3].Busy OR fbHalt[3].Busy;

// --- 5) 拉沿：调用完当拍拉低，下一帧再给沿 ---
FOR i := 1 TO 3 DO
    aCmd[i].xMoveTrig := FALSE;
    aCmd[i].xHaltTrig := FALSE;
END_FOR
