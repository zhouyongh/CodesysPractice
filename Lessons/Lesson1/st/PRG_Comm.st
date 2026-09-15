(* =====================================================================
   对象类型 : POU（PRG，语言 ST）  对象名 : PRG_Comm
   项目     : Lesson1
   任务     : CommTask（20 ms，优先级低于 MainTask）
   纪律     : 只收发原始帧，不认识协议内容：收帧写进 GVL.stCmd、
              回执序号变化就立即发一帧 AxisInfo、否则周期发。
              解析和执行永远是 MainTask 的事。
   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 PRG_Comm
              -> 类型选"程序"（Program）-> 实现语言选 ST。
   粘贴方法 : 跳过下面第一行对象头（PROGRAM xxx），声明区（VAR 块）粘到
              编辑器上半部，"实现区"分隔线以下的内容粘到下半部。
   ===================================================================== *)
PROGRAM PRG_Comm
VAR
    fbTcp      : FB_TcpServer;
    stAxisInfo   : AxisInfo;      // 待发的一帧（回执与周期状态共用同一个结构）
    nLastAck   : UDINT := 0;      // 上次发出帧里带的回执序号
    nStatusDiv : UINT := 0;       // 状态帧分频：20ms x 10 = 200ms 一帧
    xSend      : BOOL;
END_VAR
(* ---------------- 实现区（以下粘到 POU 编辑器下半部） ---------------- *)

// --- 1) 发送仲裁：回执优先于周期状态。一周期最多发一帧，
//        TCP 会排队不丢，状态帧晚 20ms 无碍 ---
xSend := FALSE;
IF GVL.nAckSeq <> nLastAck THEN
    nLastAck := GVL.nAckSeq;
    xSend := TRUE;
ELSE
    nStatusDiv := nStatusDiv + 1;
    IF nStatusDiv >= 10 THEN
        nStatusDiv := 0;
        xSend := TRUE;           // 无客户端时 FB_TcpServer 内部会丢弃
    END_IF
END_IF

IF xSend THEN
    stAxisInfo.wResult := GVL.wResult;   // 结果码随每一帧带出去
    stAxisInfo.nAckSeq := GVL.nAckSeq;   // 上位机靠它的变化识别新回执
    stAxisInfo.aAxis   := GVL.aAxis;
END_IF

// --- 2) 跑服务器：收到的字节直接凑进 GVL.stCmd ---
fbTcp(
    xEnable := TRUE,
    nPort   := 12000,
    pRxBuf  := ADR(GVL.stCmd),
    nRxSize := SIZEOF(Cmd),
    pTxBuf  := ADR(stAxisInfo),
    nTxSize := SIZEOF(AxisInfo),
    xSend   := xSend);

// --- 3) 凑满一帧 -> 命令序号 +1（GVL.stCmd 只允许本任务写）---
IF fbTcp.xFrameReady THEN
    GVL.nCmdSeq := GVL.nCmdSeq + 1;
END_IF
