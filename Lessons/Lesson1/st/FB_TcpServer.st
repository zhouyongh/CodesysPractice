(* =====================================================================
   对象类型 : POU（FB，语言 ST）   对象名 : FB_TcpServer
   项目     : Lesson1
   运行目标 : CODESYS Control Win V3 x64（64 位！）
   角色     : TCP 服务器封装（SysSocket 库）：监听 -> 接单客户端 ->
              收字节凑成定长帧 / 把一帧发出去。协议内容它一概不懂，
              只认识帧长度 —— 这就是"协议层"和"通道层"的分界。
   纪律     : 全部 socket 调用都是非阻塞的（FIONBIO），
              绝不许把 CommTask 卡死在对端的沉默上。
   注意     : 定长帧没有同步头 —— 对端发来的字节数一旦错位就会永久错位。
              骨架双方都是自己人（配套上位机），不处理；接陌生对端时
              要加帧头 + 长度 + CRC（已记入项目 README 的扩展点）。

   —— 为什么用 SysSocket 而不是 SysSockets23 ——
   旧的 SysSockets23（3.5.13.0）是 32 位专用库，在 x64 设备上编译直接报
   C0338（该库不支持 64 位应用程序）。现役的 **SysSocket**（3.5.19.0）
   是 32/64 位通用版，本文件按它的实际签名编写。

   创建方法 : Application 右键 -> 添加对象 -> POU -> 名称 FB_TcpServer
              -> 类型选"功能块"（Function Block）-> 实现语言选 ST。
   库       : Library Manager -> Add Library -> 搜 syssocket -> 选 **SysSocket**
              （3.5.19.0）。★ 不要选 SysSocket23（32 位专用），
              也不要选 SysSocket2（另一套已废弃的 2.x 接口）。
              加好后把旧的 SysSockets23 从 Library Manager 里删掉。
   粘贴方法 : 跳过下面第一行对象头（FUNCTION_BLOCK xxx），声明区（各 VAR 块）
              粘到编辑器上半部，"实现区"分隔线以下的内容粘到下半部。
   ===================================================================== *)
FUNCTION_BLOCK FB_TcpServer
VAR_INPUT
    xEnable : BOOL := TRUE;      // FALSE 时关闭连接与监听，回到空闲
    nPort   : UINT := 12000;
    pRxBuf  : POINTER TO BYTE;   // 收帧目标：凑满 nRxSize 字节 = 一帧
    nRxSize : UINT;              // 收帧长度（调用方传 SIZEOF(命令结构体)）
    pTxBuf  : POINTER TO BYTE;   // 待发的一帧
    nTxSize : UINT;              // 发帧长度
    xSend   : BOOL;              // 上升沿把 pTxBuf 指向的 nTxSize 字节发出去
END_VAR
VAR_OUTPUT
    xClientConnected : BOOL;
    xFrameReady : BOOL;          // 本周期凑满一帧（pRxBuf 内容已更新），保持一个周期
    bError      : BOOL;          // 保持型：建监听失败才置位，码见 GVL.SOCK_*
    nErrorID    : WORD;
END_VAR
VAR
    eState     : INT := 0;       // 0=空闲 / 1=监听中 / 2=已连接；不出本 FB，故不建枚举
    hListen    : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
    hClient    : RTS_IEC_HANDLE := RTS_INVALID_HANDLE;
    hNew       : RTS_IEC_HANDLE;
    sockAddr    : SOCKADDRESS;   // 本机监听地址
    sockAddrCli : SOCKADDRESS;   // accept 回写的客户端地址（内容不用，签名要指针）
    diAddrLen   : DINT;          // sockAddrCli 的长度（accept 的入/出参）
    resOp      : RTS_IEC_RESULT; // create / bind / listen / accept 的返回码
    resRecv    : RTS_IEC_RESULT; // recv 的返回码：区分"对端关闭"与"暂无数据"
    resSend    : RTS_IEC_RESULT;
    diNonBlock : DINT := 1;      // FIONBIO 参数：1 = 非阻塞
    diReuse    : DINT := 1;      // SO_REUSEADDR 参数：1 = 允许地址复用
    diRet      : __XINT;         // recv 返回值。__XINT = 平台相关整型（x64 下 64 位），
                                 // 必须用 __XINT 接，用 DINT 接在 x64 上报类型错
    diSent     : __XINT;         // send 返回值：<=0 视为发送失败（对端已死）
    diRxCnt    : INT;            // 本帧已收字节数（兼作写入偏移；指针运算用 INT 最稳）
    xBufSize   : __XINT;         // recv / send 的缓冲长度入参：类型必须和形参一致（__XINT），
                                 // 先把长度算进这个变量，实参里就不做类型转换
    xSendPrev  : BOOL;
END_VAR
VAR CONSTANT
    // SysSocket 函数的成功返回码 = 0。
    // 不直接写库常量 ERR_OK：它由库的依赖链带出，库版本一变就可能"没有定义标识符"。
    // 用本地常量最稳，语义一样。
    SOCK_OK : RTS_IEC_RESULT := 0;
    // x64 下 SysSocket 出错时返回的非法句柄是 16#FFFFFFFFFFFFFFFF
    // （Windows 的 INVALID_SOCKET），与 RTS_INVALID_HANDLE
    // （16#00000000FFFFFFFF）不相等！create / accept 拿到返回值后先归一成
    // RTS_INVALID_HANDLE，否则空 accept 会被当成接到了客户端
    // （假连接死循环：发送失败 -> 回监听 -> 又假 accept，真客户端进不来）。
    HANDLE_INVALID : RTS_IEC_HANDLE := 16#FFFFFFFFFFFFFFFF;
END_VAR
(* ---------------- 实现区（以下粘到 POU 编辑器下半部） ---------------- *)
xFrameReady := FALSE;

// --- 使能撤掉：关干净回空闲 ---
IF NOT xEnable THEN
    IF (hClient <> RTS_INVALID_HANDLE) AND (hClient <> 0) THEN
        SysSockClose(hClient);
        hClient := RTS_INVALID_HANDLE;
    END_IF
    IF (hListen <> RTS_INVALID_HANDLE) AND (hListen <> 0) THEN
        SysSockClose(hListen);
        hListen := RTS_INVALID_HANDLE;
    END_IF
    eState := 0;
    xClientConnected := FALSE;
    diRxCnt := 0;
END_IF

CASE eState OF

    // ---------------------------------------------------------------
    0:  // 空闲：建立监听
        bError := FALSE;
        nErrorID := GVL.OK;
        IF xEnable THEN
            // SysSockCreate(iAddressFamily : INT, diType : DINT, diProtocol : DINT,
            //               pResult : POINTER TO RTS_IEC_RESULT) : RTS_IEC_HANDLE
            hListen := SysSockCreate(SOCKET_AF_INET, SOCKET_STREAM, SOCKET_IPPROTO_TCP,
                                     ADR(resOp));
            IF hListen = HANDLE_INVALID THEN
                hListen := RTS_INVALID_HANDLE;   // 归一非法句柄，见 HANDLE_INVALID 注释
            END_IF
            IF (hListen = RTS_INVALID_HANDLE) OR (hListen = 0) THEN
                bError := TRUE;
                nErrorID := GVL.SOCK_CREATE;
                hListen := RTS_INVALID_HANDLE;
            ELSE
                // 非阻塞：accept / recv 没有事件时立即返回，不卡任务
                // SysSockIoctl(hSocket, diCommand : DINT, pdiParameter : POINTER TO DINT)
                SysSockIoctl(hListen, SOCKET_FIONBIO, ADR(diNonBlock));
                // 允许地址复用：调试时反复"下载/运行"不会报端口被占用（9002）
                // SysSockSetOption(hSocket, diLevel : DINT, diOption : DINT,
                //                  pdiOptionValue : POINTER TO DINT, diOptionLen : DINT)
                SysSockSetOption(hListen, SOCKET_SOL, SOCKET_SO_REUSEADDR,
                                 ADR(diReuse), SIZEOF(diReuse));

                sockAddr.sin_family      := SOCKET_AF_INET;      // INT，直接赋值，不要 TO_INT
                // 端口必须转成网络字节序；显式 WORD 转型避免 UINT->WORD 的隐式转换告警
                sockAddr.sin_port        := SysSockHtons(TO_WORD(nPort));
                sockAddr.sin_addr.ulAddr := SOCKET_INADDR_ANY;   // 0.0.0.0，本机所有网卡都接

                // SysSockBind(hSocket, pSockAddr : POINTER TO SOCKADDRESS,
                //             diSockAddrSize : DINT) : RTS_IEC_RESULT
                IF SysSockBind(hListen, ADR(sockAddr), SIZEOF(sockAddr)) <> SOCK_OK THEN
                    bError := TRUE;
                    nErrorID := GVL.SOCK_BIND;
                // SysSockListen(hSocket, diMaxConnections : DINT) : RTS_IEC_RESULT
                ELSIF SysSockListen(hListen, 1) <> SOCK_OK THEN
                    bError := TRUE;
                    nErrorID := GVL.SOCK_LISTEN;
                ELSE
                    eState := 1;
                END_IF
                IF bError THEN
                    SysSockClose(hListen);
                    hListen := RTS_INVALID_HANDLE;
                END_IF
            END_IF
        END_IF

    // ---------------------------------------------------------------
    1:  // 监听中：非阻塞 accept，接到就进已连接
        // SysSockAccept(hSocket, pSockAddr : POINTER TO SOCKADDRESS,
        //               pdiSockAddrSize : POINTER TO DINT,
        //               pResult) : RTS_IEC_HANDLE
        // 注意：x64 版不接受空指针（0），必须传真实的地址变量和长度变量
        diAddrLen := SIZEOF(sockAddrCli);
        hNew := SysSockAccept(hListen, ADR(sockAddrCli), ADR(diAddrLen), ADR(resOp));
        IF hNew = HANDLE_INVALID THEN
            hNew := RTS_INVALID_HANDLE;          // 归一非法句柄，见 HANDLE_INVALID 注释
        END_IF
        IF (hNew <> RTS_INVALID_HANDLE) AND (hNew <> 0) THEN
            hClient := hNew;
            SysSockIoctl(hClient, SOCKET_FIONBIO, ADR(diNonBlock));
            diRxCnt := 0;
            xClientConnected := TRUE;
            eState := 2;
        END_IF

    // ---------------------------------------------------------------
    2:  // 已连接：收字节凑帧 / 发一帧
        // -- 收：往调用方的帧缓冲里续字节，凑满 nRxSize 即一帧 --
        IF (pRxBuf <> 0) AND (nRxSize > 0) THEN
            // SysSockRecv(hSocket, pbyBuffer : POINTER TO BYTE, diBufferSize : __XINT,
            //             diFlags : DINT, pResult) : __XINT
            // flags 传 NONE：非阻塞由 socket 级的 FIONBIO 保证。
            // 不要传 MSG_DONTWAIT（16#8）——那是 Linux 语义，Windows 运行时下
            // 16#8 是 MSG_WAITALL，会让 recv 行为异常、读不到数据
            xBufSize := TO_INT(nRxSize) - diRxCnt;       // 本帧还缺的字节数
            diRet := SysSockRecv(hClient, pRxBuf + diRxCnt,
                                 xBufSize, SOCKET_MSG_NONE, ADR(resRecv));
            IF diRet > 0 THEN
                diRxCnt := diRxCnt + TO_INT(diRet);
                IF diRxCnt >= TO_INT(nRxSize) THEN
                    diRxCnt := 0;                        // 下一帧从头开始凑
                    xFrameReady := TRUE;
                END_IF
            ELSIF (diRet = 0) AND (resRecv = SOCK_OK) THEN
                // 收到 0 字节且无错误 = 对端正常关闭 -> 回监听态等下一个客户端；
                // 没收完的半帧随 diRxCnt 清零一起丢弃
                SysSockClose(hClient);
                hClient := RTS_INVALID_HANDLE;
                xClientConnected := FALSE;
                diRxCnt := 0;
                eState := 1;
            END_IF
            // diRet = 0 且 resRecv <> SOCK_OK：非阻塞下"暂无数据"，不是错误
        END_IF

        // -- 发：xSend 上升沿 --
        // 骨架不做短写重发：本机回环 + 一帧 21 字节，一次写不完的概率为零；
        // 将来走真实网络时必须处理短写（已记入项目 README 的扩展点）
        IF xSend AND NOT xSendPrev AND (pTxBuf <> 0) THEN
            // SysSockSend(hSocket, pbyBuffer, diBufferSize : __XINT,
            //             diFlags : DINT, pResult) : __XINT
            xBufSize := nTxSize;
            diSent := SysSockSend(hClient, pTxBuf, xBufSize, SOCKET_MSG_NONE, ADR(resSend));
            // 死连接检测（不依赖 recv 的返回码语义）：对端关闭后，
            // 头一两次 send 可能还"成功"，对端 OS 回 RST 之后 send 必失败。
            // 状态帧每 200ms 一发，所以断开最多 ~400ms 内被发现并自愈：
            // 关掉死句柄回监听态，backlog 里排队的新连接下一周期被 accept。
            // 注意：本机回环下发送缓冲永远不会满，"0=失败"不会误伤活连接。
            IF diSent <= 0 THEN
                SysSockClose(hClient);
                hClient := RTS_INVALID_HANDLE;
                xClientConnected := FALSE;
                diRxCnt := 0;
                eState := 1;
            END_IF
        END_IF

END_CASE

xSendPrev := xSend;
