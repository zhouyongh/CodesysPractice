(* =====================================================================
   对象类型 : DUT            对象名 : DUT
   项目     : Lesson1
   角色     : 全工程唯一的自定义类型表，分两个层次：
              【领域类型】Axis（一根轴）、Cmd（一条命令）—— 业务的语言；
              【报文格式】AxisInfo（PLC 发给上位机的帧）—— 线上的字节合同。
              Cmd 同时就是上行帧（命令即报文）；AxisInfo 只是输出报文，
              不是与 Axis / Cmd 并列的领域概念。

   报文布局（pack_mode=1，双端 x86/x64 小端，内存拷贝即协议）:
      Cmd    30 字节 : bType(1) bSub(1) nLen(1) aParam[3]×AxisParam(27)
      AxisParam 9 字节 : bAxis(1) rPos(4) rVel(4)
      Axis   13 字节 : rActPos(4) rTargetPos(4) rVelocity(4) xMoving(1)
      AxisInfo 45 字节 : wResult(2) nAckSeq(4) aAxis[3]×Axis(39)

   创建方法 : Application 右键 -> 添加对象 -> DUT -> 名称 DUT
              -> 类型选"结构体"（多个结构体可放在同一个 DUT 对象里）。
   粘贴方法 : 本文件整段照粘（编辑器自带的外壳整段替换）。
   ===================================================================== *)

// ==================== 领域类型 ====================

// ---- 一根轴：设定 + 实际的全部家当 ----
{attribute 'pack_mode' := '1'}
TYPE Axis :
STRUCT
    rActPos    : REAL;   // 实际位置
    rTargetPos : REAL;   // 目标位置（最近一次 MoveTo 的设定）
    rVelocity  : REAL;   // 速度（最近一次 MoveTo 的设定）
    xMoving    : BOOL;   // TRUE=运动中，FALSE=Idle
END_STRUCT
END_TYPE

// ---- 一路轴参数（CMD_CONTENT 的元素）：轴号 + 位置 + 速度 ----
{attribute 'pack_mode' := '1'}
TYPE AxisParam :
STRUCT
    bAxis : BYTE;    // 轴号：1=X 2=Y 3=Z（即 GVL.aAxis 的下标）
    rPos  : REAL;    // MOVE 目标位置（STOP 时不用）
    rVel  : REAL;    // MOVE 速度，必须 > 0（STOP 时不用）
END_STRUCT
END_TYPE

// ---- 一条命令：上位机 -> PLC，同时就是上行帧，30 字节 ----
// 分层：命令头(bType) + 子命令(bSub) + 参数数组(aParam + 有效个数 nLen)。
// 一帧可携带多路轴参数，一次命令多根轴；每路自带轴号，顺序无关。
{attribute 'pack_mode' := '1'}
TYPE Cmd :
STRUCT
    bType  : BYTE;                      // 命令头：取值见 GVL 常量 CMD_MOVE / CMD_STOP
    bSub   : BYTE;                      // 子命令：预留，现填 0（将来如 MOVE 的绝对/相对）
    nLen   : BYTE;                      // aParam 里的有效路数：1..3
    aParam : ARRAY[1..3] OF AxisParam;  // 参数数组，只有前 nLen 路有效
END_STRUCT
END_TYPE

// ==================== 报文格式 ====================

// ---- 汇报帧：PLC -> 上位机，45 字节 ----
// 只是"PLC 发出的电报"：最近一条命令的结果 + 三轴现状。
// 回执序号变化立即发一帧，否则每 200ms 发一帧 —— 两种场合发同一个结构。
{attribute 'pack_mode' := '1'}
TYPE AxisInfo :
STRUCT
    wResult : WORD;                  // 最近一条命令的结果码（0=OK，其余见 GVL 结果码）
    nAckSeq : UDINT;                 // 回执序号：上位机靠它的变化识别"新回执"
    aAxis   : ARRAY[1..3] OF Axis;   // 三轴现状
END_STRUCT
END_TYPE
