using System;
using System.Text;
using System.Runtime.InteropServices;
using System.Collections.Generic;

public static class Gs2Cli {
    const int AF_UNIX = 1, SOCK_STREAM = 1;
    [DllImport("ws2_32.dll")] static extern int WSAStartup(ushort ver, IntPtr data);
    [DllImport("ws2_32.dll")] static extern IntPtr socket(int af, int type, int proto);
    [DllImport("ws2_32.dll")] static extern int connect(IntPtr s, byte[] name, int len);
    [DllImport("ws2_32.dll")] static extern int send(IntPtr s, byte[] buf, int len, int flags);
    [DllImport("ws2_32.dll")] static extern int recv(IntPtr s, byte[] buf, int len, int flags);
    [DllImport("ws2_32.dll")] static extern int closesocket(IntPtr s);
    [DllImport("ws2_32.dll")] static extern int WSAGetLastError();
    static IntPtr h = IntPtr.Zero;
    static uint seq = 1;

    public static void Connect(string path) {
        IntPtr mem = Marshal.AllocCoTaskMem(400);
        WSAStartup(0x0202, mem);
        Marshal.FreeCoTaskMem(mem);
        h = socket(AF_UNIX, SOCK_STREAM, 0);
        if (h.ToInt64() == -1) throw new Exception("socket() failed err=" + WSAGetLastError());
        byte[] sa = new byte[110];
        sa[0] = (byte)(AF_UNIX & 0xff);
        sa[1] = (byte)((AF_UNIX >> 8) & 0xff);
        byte[] p = Encoding.UTF8.GetBytes(path);
        Array.Copy(p, 0, sa, 2, p.Length);
        int rc = connect(h, sa, 110);
        if (rc != 0) throw new Exception("connect rc=" + rc + " err=" + WSAGetLastError());
    }

    static void SendAll(byte[] buf) {
        int sent = 0;
        while (sent < buf.Length) {
            byte[] chunk;
            int want = buf.Length - sent;
            chunk = buf; // send whole remaining piece via offset copy
            byte[] tmp = new byte[want];
            Array.Copy(buf, sent, tmp, 0, want);
            int rc = send(h, tmp, want, 0);
            if (rc <= 0) throw new Exception("send err=" + WSAGetLastError());
            sent += rc;
        }
    }

    static byte[] RecvN(int n) {
        byte[] outb = new byte[n];
        int got = 0;
        while (got < n) {
            byte[] tmp = new byte[n - got];
            int rc = recv(h, tmp, n - got, 0);
            if (rc <= 0) throw new Exception("recv closed rc=" + rc + " err=" + WSAGetLastError());
            Array.Copy(tmp, 0, outb, got, rc);
            got += rc;
        }
        return outb;
    }

    public static byte[] RequestPub(uint type, byte[] payload) { return Request(type, payload); }

    static byte[] Request(uint type, byte[] payload) {        if (payload == null) payload = new byte[0];
        byte[] f = new byte[12 + payload.Length];
        byte[] t = BitConverter.GetBytes(type);
        Array.Copy(t, 0, f, 0, 4);
        t = BitConverter.GetBytes(seq++);
        Array.Copy(t, 0, f, 4, 4);
        t = BitConverter.GetBytes(payload.Length);
        Array.Copy(t, 0, f, 8, 4);
        if (payload.Length > 0) Array.Copy(payload, 0, f, 12, payload.Length);
        SendAll(f);
        while (true) {
            byte[] hdr = RecvN(12);
            uint rt = BitConverter.ToUInt32(hdr, 0);
            uint rs = BitConverter.ToUInt32(hdr, 4);
            uint rl = BitConverter.ToUInt32(hdr, 8);
            byte[] rp = rl > 0 ? RecvN((int)rl) : new byte[0];
            if (rt == 4) continue; // unsolicited EVENT
            if (rt == 3) {
                uint code = BitConverter.ToUInt32(rp, 0);
                string msg = rp.Length > 4 ? Encoding.ASCII.GetString(rp, 4, rp.Length - 4) : "";
                throw new Exception("protocol error " + code + ": " + msg);
            }
            if (rs != seq - 1) throw new Exception("unexpected seq " + rs);
            return rp;
        }
    }

    public static void Hello() {
        byte[] p = new byte[8];
        Array.Copy(BitConverter.GetBytes((uint)1), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes((uint)0), 0, p, 4, 4);
        Request(0x00000001, p);
    }

    public static uint[] Status() {
        byte[] r = Request(0x00000101, new byte[0]);
        return new uint[] { BitConverter.ToUInt32(r, 0), BitConverter.ToUInt32(r, 4) };
    }

    public static byte[] ReadMem(uint domain, uint addr, uint len) {
        byte[] p = new byte[12];
        Array.Copy(BitConverter.GetBytes(domain), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(addr), 0, p, 4, 4);
        Array.Copy(BitConverter.GetBytes(len), 0, p, 8, 4);
        return Request(0x00000301, p);
    }

    public static void WriteMem(uint domain, uint addr, byte[] data) {
        byte[] p = new byte[12 + data.Length];
        Array.Copy(BitConverter.GetBytes(domain), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(addr), 0, p, 4, 4);
        Array.Copy(BitConverter.GetBytes((uint)data.Length), 0, p, 8, 4);
        Array.Copy(data, 0, p, 12, data.Length);
        Request(0x00000302, p);
    }

    public static uint[] FindMem(uint domain, uint addr, uint len, uint maxhits, byte[] pattern) {
        byte[] p = new byte[24 + pattern.Length];
        Array.Copy(BitConverter.GetBytes(domain), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(addr), 0, p, 4, 4);
        Array.Copy(BitConverter.GetBytes(len), 0, p, 8, 4);
        Array.Copy(BitConverter.GetBytes(maxhits), 0, p, 12, 4);
        Array.Copy(BitConverter.GetBytes((uint)pattern.Length), 0, p, 16, 4);
        Array.Copy(BitConverter.GetBytes((uint)0), 0, p, 20, 4);
        Array.Copy(pattern, 0, p, 24, pattern.Length);
        byte[] r = Request(0x00000303, p);
        uint n = BitConverter.ToUInt32(r, 0);
        uint[] hits = new uint[n];
        for (int i = 0; i < n; i++) hits[i] = BitConverter.ToUInt32(r, 4 + 4 * i);
        return hits;
    }

    public static byte[] VideoText(uint page, uint mode) {
        byte[] p = new byte[8];
        Array.Copy(BitConverter.GetBytes(page), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(mode), 0, p, 4, 4);
        return Request(0x00000701, p);
    }

    public static byte[] Regs() { return Request(0x00000202, new byte[0]); }

    public static byte[] Trace(uint ago, uint count) {
        byte[] p = new byte[8];
        Array.Copy(BitConverter.GetBytes(ago), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(count), 0, p, 4, 4);
        return Request(0x00000201, p);
    }

    public static uint BpExec(uint addr) {
        byte[] p = new byte[32];
        p[0] = 1;                     // BP_KIND_EXEC
        p[1] = 1;                     // BP_FLAG_ENABLED
        p[2] = 0; p[3] = 0;
        Array.Copy(BitConverter.GetBytes(0u), 0, p, 4, 4);
        Array.Copy(BitConverter.GetBytes(addr), 0, p, 8, 4);
        Array.Copy(BitConverter.GetBytes(1u), 0, p, 12, 4);
        Array.Copy(BitConverter.GetBytes(0xFFFFFFFFu), 0, p, 16, 4);
        byte[] r = Request(0x00000401, p);
        return BitConverter.ToUInt32(r, 0);
    }

    public static void BpClearAll() { Request(0x00000403, new byte[0]); }
    public static void Continue() { Request(0x00000104, new byte[0]); }
    public static void Pause() { Request(0x00000103, new byte[0]); }
    public static void StepInto(uint count) {
        byte[] p = new byte[4];
        Array.Copy(BitConverter.GetBytes(count), 0, p, 0, 4);
        Request(0x00000105, p);
    }
    public static void Reset(bool cold) {
        byte[] p = new byte[4];
        Array.Copy(BitConverter.GetBytes(cold ? 1u : 0u), 0, p, 0, 4);
        Request(0x00000102, p);
    }

    public static void Key(bool down, uint scancode, uint mod) {
        byte[] p = new byte[12];
        Array.Copy(BitConverter.GetBytes(down ? (uint)1 : (uint)0), 0, p, 0, 4);
        Array.Copy(BitConverter.GetBytes(scancode), 0, p, 4, 4);
        Array.Copy(BitConverter.GetBytes(mod), 0, p, 8, 4);
        Request(0x00000501, p);
    }

    public static void Quit() { Request(0x00000005, new byte[0]); }

    // Generic device STATE_GET (main 6 sub 1). device_id 22 = DEVICE_ID_ENSONIQ.
    public static byte[] DevState(uint id) {
        byte[] p = new byte[4];
        Array.Copy(BitConverter.GetBytes(id), 0, p, 0, 4);
        return Request(0x00000601, p);
    }

    public static byte[] DevStateSet(uint id, byte[] blob) {
        byte[] p = new byte[4 + blob.Length];
        Array.Copy(BitConverter.GetBytes(id), 0, p, 0, 4);
        Array.Copy(blob, 0, p, 4, blob.Length);
        return Request(0x00000602, p);
    }

    public static void MouseMove(int dx, int dy) {
        byte[] b = new byte[8];
        b[0] = 1; b[4] = 1;
        unchecked { b[5] = (byte)(sbyte)dx; b[6] = (byte)(sbyte)dy; }
        DevStateSet(17, b);
    }

    public static void MouseButton(int buttons) {
        byte[] b = new byte[8];
        b[0] = 1; b[4] = 2; b[7] = (byte)buttons;
        DevStateSet(17, b);
    }

    [DllImport("ws2_32.dll", SetLastError=true)] static extern int WSAIoctl(IntPtr s, int code, byte[] inBuf, int inLen, byte[] outBuf, int outLen, out int transferred, IntPtr overlapped, IntPtr completion);

    static IntPtr MakeSock(bool setParent, string parentPath, string sunPath) {
        IntPtr mem0 = Marshal.AllocCoTaskMem(400);
        WSAStartup(0x0202, mem0);
        Marshal.FreeCoTaskMem(mem0);
        IntPtr s = socket(AF_UNIX, SOCK_STREAM, 0);
        if (s.ToInt64() == -1) throw new Exception("socket() failed err=" + WSAGetLastError());
        if (setParent) {
            byte[] pstr = Encoding.ASCII.GetBytes(parentPath);
            byte[] pb = new byte[pstr.Length + 1];
            Array.Copy(pstr, pb, pstr.Length);
            pb[pb.Length - 1] = 0;
            int tr;
            int rc = WSAIoctl(s, unchecked((int)0x98000102), pb, pb.Length, null, 0, out tr, IntPtr.Zero, IntPtr.Zero);
            if (rc != 0) Console.WriteLine("WSAIoctl parent rc=" + rc + " err=" + WSAGetLastError() + " parent=" + parentPath);
        }
        byte[] sa = new byte[110];
        sa[0] = (byte)(AF_UNIX & 0xff);
        sa[1] = (byte)((AF_UNIX >> 8) & 0xff);
        byte[] pp = Encoding.UTF8.GetBytes(sunPath);
        Array.Copy(pp, 0, sa, 2, pp.Length);
        IntPtr mem = Marshal.AllocCoTaskMem(400);
        WSAStartup(0x0202, mem);
        Marshal.FreeCoTaskMem(mem);
        return s;
    }

    public static int ConnectAttempt(bool setParent, string parentPath, string sunPath) {
        IntPtr s = MakeSock(setParent, parentPath, sunPath);
        byte[] sa = new byte[110];
        sa[0] = (byte)(AF_UNIX & 0xff);
        sa[1] = (byte)((AF_UNIX >> 8) & 0xff);
        byte[] pp = Encoding.UTF8.GetBytes(sunPath);
        Array.Copy(pp, 0, sa, 2, pp.Length);
        int rc = connect(s, sa, 110);
        int err = WSAGetLastError();
        if (rc != 0) closesocket(s);
        else { h = s; }
        Console.WriteLine("attempt parent=" + parentPath + " sun=" + sunPath + " rc=" + rc + " err=" + err);
        return rc;
    }
}

