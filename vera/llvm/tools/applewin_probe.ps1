param([switch]$ToggleDebugger, [string[]]$Commands, [int[]]$Keys, [switch]$Screenshot, [string]$Capture)
$ErrorActionPreference='Stop'
Add-Type @'
using System;using System.Text;using System.Runtime.InteropServices;
public class FreegemasWindow {
 public delegate bool Callback(IntPtr h,IntPtr p);
 [DllImport("user32.dll")]static extern bool EnumWindows(Callback c,IntPtr p);
 [DllImport("user32.dll")]static extern uint GetWindowThreadProcessId(IntPtr h,out uint p);
 [DllImport("user32.dll",CharSet=CharSet.Unicode)]static extern int GetWindowText(IntPtr h,StringBuilder s,int n);
 [DllImport("user32.dll")]public static extern bool PostMessage(IntPtr h,uint m,IntPtr w,IntPtr l);
 public static IntPtr Find(uint pid){IntPtr found=IntPtr.Zero;EnumWindows((h,p)=>{uint id;GetWindowThreadProcessId(h,out id);if(id==pid){var s=new StringBuilder(256);GetWindowText(h,s,256);if(s.ToString().Contains("Emulator"))found=h;}return true;},IntPtr.Zero);return found;}
}
'@
$emulator=Get-Process AppleWin | Select-Object -First 1
$targetWindow=[FreegemasWindow]::Find($emulator.Id)
if($targetWindow -eq [IntPtr]::Zero){throw 'AppleWin main window not found'}
function Send-VirtualKey([int]$key){
    [void][FreegemasWindow]::PostMessage($targetWindow,0x100,[IntPtr]$key,[IntPtr]1)
    [void][FreegemasWindow]::PostMessage($targetWindow,0x101,[IntPtr]$key,[IntPtr]0xC0000001)
}
if($ToggleDebugger){Send-VirtualKey 0x76;Start-Sleep -Milliseconds 300}
foreach($command in $Commands){
    foreach($ch in $command.ToCharArray()){[void][FreegemasWindow]::PostMessage($targetWindow,0x102,[IntPtr][int]$ch,[IntPtr]0)}
    Send-VirtualKey 13;Start-Sleep -Milliseconds 150
}
foreach($key in $Keys){[void][FreegemasWindow]::PostMessage($targetWindow,0x102,[IntPtr]$key,[IntPtr]0);Start-Sleep -Milliseconds 150}
if($Screenshot){[void][FreegemasWindow]::PostMessage($targetWindow,0x312,[IntPtr]1028,[IntPtr]0);Start-Sleep -Milliseconds 300}
Write-Output "AppleWin PID=$($emulator.Id), HWND=$targetWindow"
if($Capture){
Add-Type -ReferencedAssemblies System.Drawing @'
using System;using System.Drawing;using System.Runtime.InteropServices;
public class FreegemasCapture {
 [StructLayout(LayoutKind.Sequential)]public struct Rect{public int L,T,R,B;}
 [DllImport("user32.dll")]static extern bool GetWindowRect(IntPtr h,out Rect r);
 [DllImport("user32.dll")]static extern bool PrintWindow(IntPtr h,IntPtr dc,uint flags);
 public static void Save(IntPtr h,string file){Rect r;GetWindowRect(h,out r);using(var b=new Bitmap(r.R-r.L,r.B-r.T)){using(var g=Graphics.FromImage(b)){var dc=g.GetHdc();PrintWindow(h,dc,0);g.ReleaseHdc(dc);}b.Save(file);}}
}
'@
[FreegemasCapture]::Save($targetWindow,$Capture)
}
