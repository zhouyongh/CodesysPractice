(* =====================================================================
   对象类型 : POU（FB，语言 ST，带 2 个方法）   对象名 : FB_SimAxis
   项目     : Lesson1
   角色     : 仿真轴：恒速点位 + 立即停止。轴是对象：
              行为是方法（MoveTo / Stop），本体每周期只做积分更新。
              参数合法性（速度 > 0）由轴自己判 —— 那是轴的业务，
              不是协议的事。换真轴时方法内部改调 MC_MoveAbsolute /
              MC_Stop，调用侧零改动。
   为什么自写而不上 SoftMotion：架子阶段要的是"一定跑得起来"。虚拟轴也要
              装 SoftMotion、配三组轴对象，把通信架子的首跑拖进运动控制
              的泥潭；接口设计好，后面换芯不动架。
   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 FB_SimAxis
              -> 类型选"功能块"（Function Block）-> 实现语言选 ST。
              然后右键 FB_SimAxis -> 添加对象 -> 方法（Method）：
              名 MoveTo、返回类型 WORD、语言 ST；名 Stop、无返回类型、语言 ST。
   粘贴方法 : FB 本体：跳过第一行对象头，VAR 块粘到上半部，"本体实现区"
              分隔线以下粘到下半部。★ 两个 METHOD 分隔线以下的内容
              **不要粘进 FB**（FB 里出现 METHOD 关键字会报"未预期的语句"）——
              方法是挂在 FB 下的独立子对象，逐节粘进对应的方法编辑器：
              跳过该节的 METHOD 对象头（IDE 按创建对话框自动生成），
              VAR 块粘上半部，实现粘下半部。
   ===================================================================== *)
FUNCTION_BLOCK FB_SimAxis
VAR_INPUT
    rCycleTime : REAL := 0.01;   // 调用任务的周期（秒），由调用方按任务配置填
END_VAR
VAR_OUTPUT
    rActPos    : REAL;           // 实际位置
    rTargetPos : REAL;           // 目标位置（最近一次 MoveTo 的设定）
    rVelocity  : REAL;           // 速度（最近一次 MoveTo 的设定）
    xMoving    : BOOL;           // TRUE=运动中
END_VAR
VAR
    rDir  : REAL := 1.0;         // 运动方向（+1/-1），MoveTo 时设定
    rStep : REAL;                // 本周期的步进量
END_VAR
(* ---------------- 本体实现区（粘到 FB 编辑器下半部） ---------------- *)
// 本体每周期只做一件事：恒速积分，到点钳位（防过冲）
IF xMoving THEN
    rStep := rVelocity * rCycleTime * rDir;
    IF ((rDir > 0) AND ((rActPos + rStep) >= rTargetPos)) OR
       ((rDir < 0) AND ((rActPos + rStep) <= rTargetPos)) THEN
        rActPos := rTargetPos;
        xMoving := FALSE;                        // 到位
    ELSE
        rActPos := rActPos + rStep;
    END_IF
END_IF

(* ============ METHOD MoveTo（独立子对象，不要粘进 FB 本体！） ============ *)
METHOD MoveTo : WORD
VAR_INPUT
    rPos : REAL;   // 目标位置
    rVel : REAL;   // 速度，必须 > 0
END_VAR
(* ---- MoveTo 实现 ---- *)
// 返回值是 GVL 结果码；运动中再来 = 改目标
MoveTo := GVL.OK;
IF rVel <= 0 THEN
    MoveTo := GVL.BAD_PARAM;
    RETURN;
END_IF
rTargetPos := rPos;
rVelocity  := rVel;
IF rTargetPos = rActPos THEN
    xMoving := FALSE;                            // 已经在点上
ELSE
    xMoving := TRUE;
    IF rTargetPos > rActPos THEN
        rDir := 1.0;
    ELSE
        rDir := -1.0;
    END_IF
END_IF

(* ============ METHOD Stop（独立子对象，不要粘进 FB 本体！） ============ *)
METHOD Stop
(* ---- Stop 实现 ---- *)
// 立即停止
xMoving := FALSE;
