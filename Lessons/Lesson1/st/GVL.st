(* =====================================================================
   对象类型 : GVL            对象名 : GVL
   项目     : Lesson1
   角色     : 全工程唯一的全局变量表，分两层：
              【领域数据】三根轴、当前命令 —— 业务的语言；
              【配套机制】命令的处理结果、跨任务序号握手 —— 实现细节。
              纪律：一个变量只有一个写者。
   创建方法 : Application 右键 -> 添加对象 -> 全局变量列表（GVL）-> 名称 GVL。
   粘贴方法 : 本文件整段照粘（编辑器自带的 VAR_GLOBAL...END_VAR 外壳整段替换，
              注意本文件有两个 VAR_GLOBAL 块，都要粘进去）。
   ===================================================================== *)
{attribute 'qualified_only'}
VAR_GLOBAL CONSTANT
    // ==== 命令字：Cmd.bType 的合法取值 ====
    CMD_MOVE    : BYTE := 1;
    CMD_STOP    : BYTE := 2;

    // ==== 结果码：全工程唯一出处。AxisInfo.wResult 就是这里的值，
    //      上位机按码判错 ====
    OK          : WORD := 0;      // 成功
    UNKNOWN_CMD : WORD := 1001;   // 命令字不认识（只认 CMD_MOVE / CMD_STOP）
    BAD_AXIS    : WORD := 1002;   // 轴号不是 1..3
    BAD_PARAM   : WORD := 1003;   // 参数非法（如速度 <= 0）
    SOCK_CREATE : WORD := 9001;   // 监听套接字创建失败
    SOCK_BIND   : WORD := 9002;   // 端口绑定失败（最常见：端口被占用）
    SOCK_LISTEN : WORD := 9003;   // listen 失败
END_VAR

VAR_GLOBAL
    // ==== 领域数据 ====
    aAxis   : ARRAY[1..3] OF Axis;  // 三根轴：下标即轴号 1=X / 2=Y / 3=Z
                                    // （MainTask 写，CommTask 读去组 AxisInfo）
    stCmd   : Cmd;                  // 当前命令（CommTask 收帧写入，MainTask 处理）

    // ==== stCmd 的配套机制（跨任务握手，实现细节，不是领域概念）====
    // 规则：CommTask 凑满一帧 -> stCmd 已被 FB_TcpServer 写好 -> nCmdSeq +1；
    //      MainTask 看到 nCmdSeq <> nAckSeq 就处理，处理完写 wResult、
    //      把 nAckSeq 对齐 nCmdSeq。
    // 单命令槽：上一帧没被取走时会被新帧覆盖。命令是人手速发的，骨架阶段够用；
    //          将来接自动上位机时换命令队列。
    wResult : WORD;             // stCmd 的处理结果（MainTask 写）
    nCmdSeq : UDINT := 0;       // 命令序号，CommTask 每收满一帧 +1；回绕到 0 也安全
    nAckSeq : UDINT := 0;       // 回执序号，MainTask 处理完对齐 nCmdSeq
END_VAR
