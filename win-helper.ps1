# Windows helper for Focus Guard.
# Prints the active window as one JSON line per second, and takes JSON commands on stdin:
#   {"cmd":"warn"|"info","caption":"...","text":"..."}
#   {"cmd":"ask","id":"abc","caption":"...","text":"..."}  -> prints {"type":"answer","id":"abc","yes":true}
#   {"cmd":"close","hwnd":123,"mode":"tab"|"window"}
#   {"cmd":"kill","pid":456}
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

Add-Type -TypeDefinition @'
using System;
using System.Text;
using System.Threading;
using System.Runtime.InteropServices;
public static class FG {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] static extern int GetWindowTextLength(IntPtr h);
  [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] static extern int MessageBoxW(IntPtr h, string text, string cap, uint type);

  public static string Title(IntPtr h) {
    int n = GetWindowTextLength(h);
    var sb = new StringBuilder(n + 1);
    GetWindowText(h, sb, sb.Capacity);
    return sb.ToString();
  }
  public static uint Pid(IntPtr h) { uint p; GetWindowThreadProcessId(h, out p); return p; }
  public static void CloseWindow(IntPtr h) { PostMessage(h, 0x0010, IntPtr.Zero, IntPtr.Zero); }
  // Closes the active browser tab with Ctrl+W.
  public static void CloseTab(IntPtr h) {
    SetForegroundWindow(h);
    Thread.Sleep(200);
    keybd_event(0x11, 0, 0, UIntPtr.Zero);
    keybd_event(0x57, 0, 0, UIntPtr.Zero);
    keybd_event(0x57, 0, 2, UIntPtr.Zero);
    keybd_event(0x11, 0, 2, UIntPtr.Zero);
  }
  // Topmost message boxes run on their own thread so the watch loop keeps running.
  // 0x1000 = system modal, 0x40000 = topmost.
  public static void Warn(string cap, string text) { Box(cap, text, 0x30u, null); }   // warning icon
  public static void Info(string cap, string text) { Box(cap, text, 0x40u, null); }   // info icon
  // Yes/No question; prints {"type":"answer","id":...,"yes":true|false} when answered.
  public static void Ask(string id, string cap, string text) { Box(cap, text, 0x24u, id); }
  static void Box(string cap, string text, uint style, string askId) {
    var t = new Thread(() => {
      int r = MessageBoxW(IntPtr.Zero, text, cap, style | 0x1000u | 0x40000u);
      if (askId != null) {
        Console.Out.WriteLine("{\"type\":\"answer\",\"id\":\"" + askId + "\",\"yes\":" + (r == 6 ? "true" : "false") + "}");
        Console.Out.Flush();
      }
    });
    t.IsBackground = true;
    t.Start();
  }
}
'@

function Emit($obj) {
  [Console]::Out.WriteLine(($obj | ConvertTo-Json -Compress))
  [Console]::Out.Flush()
}

$reader = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), [System.Text.Encoding]::UTF8)
$pending = $reader.ReadLineAsync()
$names = @{}

while ($true) {
  while ($pending.IsCompleted) {
    $line = $pending.Result
    if ($null -eq $line) { exit 0 }  # parent went away
    try {
      $c = $line | ConvertFrom-Json
      switch ($c.cmd) {
        'warn'  { [FG]::Warn([string]$c.caption, [string]$c.text) }
        'info'  { [FG]::Info([string]$c.caption, [string]$c.text) }
        'ask'   { [FG]::Ask(([string]$c.id -replace '[^A-Za-z0-9]', ''), [string]$c.caption, [string]$c.text) }
        'close' {
          $h = [IntPtr][int64]$c.hwnd
          if ($c.mode -eq 'tab') { [FG]::CloseTab($h) } else { [FG]::CloseWindow($h) }
        }
        'kill'  { Stop-Process -Id ([int]$c.pid) -Force -ErrorAction SilentlyContinue }
      }
      Emit @{ type = 'ack'; cmd = $c.cmd }
    } catch {
      Emit @{ type = 'error'; message = $_.Exception.Message }
    }
    $pending = $reader.ReadLineAsync()
  }

  $h = [FG]::GetForegroundWindow()
  $wpid = [FG]::Pid($h)
  if (-not $names.ContainsKey($wpid)) {
    $p = Get-Process -Id $wpid -ErrorAction SilentlyContinue
    $names[$wpid] = if ($p) { $p.ProcessName } else { '' }
  }
  Emit @{ type = 'fg'; hwnd = [int64]$h; pid = [int]$wpid; process = $names[$wpid]; title = [FG]::Title($h) }
  Start-Sleep -Milliseconds 1000
}
