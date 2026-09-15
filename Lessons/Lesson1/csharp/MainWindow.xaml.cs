using System.Globalization;
using System.IO;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Windows;

namespace Lesson1Host;

/// <summary>
/// Lesson1 最简上位机：TCP 客户端，给 CODESYS（Control Win 仿真）发
/// 二进制命令帧（Cmd，30 字节，可携带多路轴参数），收汇报帧（AxisInfo，45 字节）。
/// 帧格式与 PLC 侧结构体逐字节一致（pack_mode=1，双端都是小端，
/// 内存拷贝即协议，没有序列化代码）；协议结构体在 Data.cs。
/// 无 MVVM、无依赖注入 —— 架子的目的是把链路跑通，不是演示框架。
/// </summary>
public partial class MainWindow : Window
{
    private static readonly int AxisInfoSize = Marshal.SizeOf<AxisInfo>();  // 45 字节，一帧的长度
    private const byte CmdMove = 1;
    private const byte CmdStop = 2;

    private TcpClient? _client;
    private NetworkStream? _stream;
    private CancellationTokenSource? _cts;

    public MainWindow()
    {
        InitializeComponent();
    }

    private bool Connected => _stream is not null;

    // ---------- 连接 / 断开 ----------

    private async void BtnConnect_Click(object sender, RoutedEventArgs e)
    {
        if (Connected)
        {
            Disconnect("主动断开");
            return;
        }

        try
        {
            _client = new TcpClient();
            await _client.ConnectAsync(TxtIp.Text.Trim(), int.Parse(TxtPort.Text.Trim()));
            _stream = _client.GetStream();
            _cts = new CancellationTokenSource();
            BtnConnect.Content = "断开";
            TxtConnState.Text = "已连接";
            Log($"已连接 {TxtIp.Text.Trim()}:{TxtPort.Text.Trim()}");
            _ = ReceiveLoop(_cts.Token);
        }
        catch (Exception ex)
        {
            Log($"连接失败：{ex.Message}");
            Cleanup();
        }
    }

    private void Disconnect(string reason)
    {
        _cts?.Cancel();
        Cleanup();
        BtnConnect.Content = "连接";
        TxtConnState.Text = "未连接";
        Log(reason);
    }

    private void Cleanup()
    {
        try { _stream?.Dispose(); } catch { /* 关闭路径不抛 */ }
        try { _client?.Close(); } catch { /* 关闭路径不抛 */ }
        _stream = null;
        _client = null;
    }

    // ---------- 接收循环：定长帧，凑满一个 AxisInfo = 一帧 ----------

    private async Task ReceiveLoop(CancellationToken ct)
    {
        var buf = new byte[AxisInfoSize];
        uint lastSeq = 0;   // 已见过的回执序号：变了才记日志（周期帧不刷屏）
        try
        {
            while (!ct.IsCancellationRequested)
            {
                // ReadExactlyAsync：读不满就继续等，和 PLC 侧"凑满即帧"正好对应
                await _stream!.ReadExactlyAsync(buf, ct);
                var info = FrameCodec.FromBytes<AxisInfo>(buf);
                Dispatcher.Invoke(() =>
                {
                    var tbs = new[] { TxtAxisX, TxtAxisY, TxtAxisZ };
                    var names = new[] { "X", "Y", "Z" };
                    for (int i = 0; i < 3; i++)
                    {
                        var a = info.aAxis[i];
                        UpdateAxis(tbs[i], names[i], a.rActPos, a.rTargetPos, a.xMoving != 0);
                    }

                    if (info.nAckSeq != lastSeq)
                    {
                        lastSeq = info.nAckSeq;
                        Log($"<< 回执 seq={info.nAckSeq} code={info.wResult} {ErrName(info.wResult)}");
                    }
                });
            }
        }
        catch (OperationCanceledException) { /* 主动断开 */ }
        catch (EndOfStreamException)
        {
            Dispatcher.Invoke(() => Disconnect("PLC 侧关闭了连接"));
        }
        catch (Exception ex)
        {
            Dispatcher.Invoke(() => Disconnect($"接收异常：{ex.Message}"));
        }
    }

    private static void UpdateAxis(System.Windows.Controls.TextBlock tb, string name, float pos, float target, bool moving)
        => tb.Text = $"{name} : {pos:0.###} → {target:0.###}  {(moving ? "Moving" : "Idle")}";

    private static string ErrName(ushort code) => code switch
    {
        0 => "OK",
        1001 => "UNKNOWN_CMD",
        1002 => "BAD_AXIS",
        1003 => "BAD_PARAM",
        _ => ""
    };

    // ---------- 发命令 ----------

    private void BtnMove_Click(object sender, RoutedEventArgs e)
    {
        // PLC 侧也会校验，这里拦一手是为了把低级输入错误挡在本地
        if (!TryReadPosVel(out float pos, out float vel))
            return;
        SendCmd(CmdMove, new[] { (byte)AxisNo() }, pos, vel);
    }

    // 三轴联动：一帧携带 3 路轴参数，演示 Cmd 的数组结构
    private void BtnMoveAll_Click(object sender, RoutedEventArgs e)
    {
        if (!TryReadPosVel(out float pos, out float vel))
            return;
        SendCmd(CmdMove, new byte[] { 1, 2, 3 }, pos, vel);
    }

    private void BtnStop_Click(object sender, RoutedEventArgs e)
    {
        SendCmd(CmdStop, new[] { (byte)AxisNo() }, 0, 0);
    }

    private bool TryReadPosVel(out float pos, out float vel)
    {
        pos = 0;
        vel = 0;
        if (!float.TryParse(TxtPos.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out pos) ||
            !float.TryParse(TxtVel.Text, NumberStyles.Float, CultureInfo.InvariantCulture, out vel) || vel <= 0)
        {
            Log("输入非法：位置/速度须为数字，速度须 > 0（小数点用 .）");
            return false;
        }
        return true;
    }

    // 轴号 = 下拉框序号 + 1（1=X / 2=Y / 3=Z，即 PLC 侧 aAxis 的下标）
    private int AxisNo() => CmbAxis.SelectedIndex + 1;

    // 按 Cmd 结构体填字段，Marshal 进字节数组即一帧（布局同 PLC 侧 DUT.st）
    private void SendCmd(byte type, byte[] axes, float pos, float vel)
    {
        if (!Connected)
        {
            Log("未连接，命令未发送");
            return;
        }
        try
        {
            var cmd = new Cmd
            {
                bType = type,
                bSub = 0,                       // 预留
                nLen = (byte)axes.Length,
                aParam = new AxisParam[3],
            };
            for (int k = 0; k < axes.Length; k++)
                cmd.aParam[k] = new AxisParam { bAxis = axes[k], rPos = pos, rVel = vel };
            _stream!.Write(FrameCodec.ToBytes(cmd));
            Log($">> cmd={type} axes=[{string.Join(',', axes)}] pos={pos} vel={vel}");
        }
        catch (Exception ex)
        {
            Disconnect($"发送失败：{ex.Message}");
        }
    }

    // ---------- 杂项 ----------

    private void Log(string msg)
    {
        TxtLog.AppendText(msg + Environment.NewLine);
        TxtLog.ScrollToEnd();
    }

    protected override void OnClosed(EventArgs e)
    {
        _cts?.Cancel();
        Cleanup();
        base.OnClosed(e);
    }
}
