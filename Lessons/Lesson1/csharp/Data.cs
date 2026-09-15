using System.Runtime.InteropServices;

namespace Lesson1Host;

// ---- 协议结构体：与 PLC 侧 DUT.st 逐字节对应（Pack=1，双端小端，内存拷贝即协议）----
// 字段顺序、类型宽度必须和 DUT.st 保持一致；改协议时两边一起改。

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct AxisParam          // 9 字节
{
    public byte bAxis;           // 轴号：1=X 2=Y 3=Z
    public float rPos;           // MOVE 目标位置
    public float rVel;           // MOVE 速度，必须 > 0
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct Axis               // 13 字节
{
    public float rActPos;
    public float rTargetPos;
    public float rVelocity;
    public byte xMoving;         // PLC 的 BOOL = 1 字节
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct Cmd                // 上行帧，30 字节
{
    public byte bType;           // 命令头：1=MOVE 2=STOP
    public byte bSub;            // 子命令：预留，填 0
    public byte nLen;            // aParam 有效路数：1..3
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
    public AxisParam[] aParam;
}

[StructLayout(LayoutKind.Sequential, Pack = 1)]
public struct AxisInfo           // 下行帧，45 字节
{
    public ushort wResult;       // 最近一条命令的结果码：0=OK
    public uint nAckSeq;         // 回执序号，每条命令必 +1
    [MarshalAs(UnmanagedType.ByValArray, SizeConst = 3)]
    public Axis[] aAxis;
}

// 结构体 <-> 字节： pinning 内存拷贝，没有逐字段序列化代码
internal static class FrameCodec
{
    public static T FromBytes<T>(byte[] buf) where T : struct
    {
        var h = GCHandle.Alloc(buf, GCHandleType.Pinned);
        try { return Marshal.PtrToStructure<T>(h.AddrOfPinnedObject()); }
        finally { h.Free(); }
    }

    public static byte[] ToBytes<T>(T frame) where T : struct
    {
        var buf = new byte[Marshal.SizeOf<T>()];
        var h = GCHandle.Alloc(buf, GCHandleType.Pinned);
        try { Marshal.StructureToPtr(frame, h.AddrOfPinnedObject(), false); }
        finally { h.Free(); }
        return buf;
    }
}
