# Always-on-top "collabterm live" indicator for the HOST.
# A small, click-through, topmost pill in the top-right corner of the primary
# screen, so the host always knows a session is live - even with every window
# minimized. _collabterm.ps1 launches this hidden and ties it to the same
# kill-on-close job, so it shows for exactly as long as the session is live.
#
# -HostPid lets the overlay self-close if the launcher process disappears, as a
# fallback in case the job-object teardown didn't reach it.
param([int]$HostPid = 0)

$ErrorActionPreference = 'Stop'
try {
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -AssemblyName System.Drawing

  Add-Type @'
using System;
using System.Runtime.InteropServices;
public static class NativeOverlay {
  const int GWL_EXSTYLE = -20;
  const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80,
            WS_EX_TOPMOST = 0x8, WS_EX_NOACTIVATE = 0x8000000;
  [DllImport("user32.dll", SetLastError=true)] static extern int GetWindowLong(IntPtr h, int i);
  [DllImport("user32.dll", SetLastError=true)] static extern int SetWindowLong(IntPtr h, int i, int v);
  [DllImport("user32.dll")] static extern bool SetWindowPos(IntPtr h, IntPtr after, int x, int y, int cx, int cy, uint f);
  static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
  const uint SWP_NOSIZE=0x1, SWP_NOMOVE=0x2, SWP_NOACTIVATE=0x10, SWP_SHOWWINDOW=0x40;
  // Float above everything and let clicks pass straight through it.
  public static void MakeClickThrough(IntPtr h) {
    int ex = GetWindowLong(h, GWL_EXSTYLE);
    SetWindowLong(h, GWL_EXSTYLE, ex | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_NOACTIVATE);
  }
  public static void Repin(IntPtr h) {
    SetWindowPos(h, HWND_TOPMOST, 0,0,0,0, SWP_NOSIZE|SWP_NOMOVE|SWP_NOACTIVATE|SWP_SHOWWINDOW);
  }
}
'@

  $form = New-Object System.Windows.Forms.Form
  $form.FormBorderStyle = 'None'
  $form.StartPosition   = 'Manual'
  $form.TopMost         = $true
  $form.ShowInTaskbar   = $false
  $form.BackColor       = [System.Drawing.Color]::FromArgb(13,13,13)
  $form.Opacity         = 0.86
  $form.Width           = 162
  $form.Height          = 30

  # rounded-pill shape
  $d  = 14
  $rr = New-Object System.Drawing.Drawing2D.GraphicsPath
  $rr.AddArc(0,0,$d,$d,180,90)
  $rr.AddArc($form.Width-$d,0,$d,$d,270,90)
  $rr.AddArc($form.Width-$d,$form.Height-$d,$d,$d,0,90)
  $rr.AddArc(0,$form.Height-$d,$d,$d,90,90)
  $rr.CloseFigure()
  $form.Region = New-Object System.Drawing.Region($rr)

  # pin to the top-right of the primary screen's working area
  $wa = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea
  $form.Left = $wa.Right - $form.Width - 12
  $form.Top  = $wa.Top + 12

  # red dot
  $dot = New-Object System.Windows.Forms.Label
  $dot.Width = 12; $dot.Height = 12; $dot.Left = 13; $dot.Top = 9
  $dot.BackColor = [System.Drawing.Color]::FromArgb(231,80,80)
  $gp = New-Object System.Drawing.Drawing2D.GraphicsPath
  $gp.AddEllipse(0,0,12,12)
  $dot.Region = New-Object System.Drawing.Region($gp)
  $form.Controls.Add($dot)

  # label
  $lbl = New-Object System.Windows.Forms.Label
  $lbl.Text      = 'collabterm live'
  $lbl.ForeColor = [System.Drawing.Color]::FromArgb(230,230,230)
  $lbl.Font      = New-Object System.Drawing.Font('Segoe UI',9,[System.Drawing.FontStyle]::Bold)
  $lbl.AutoSize  = $true
  $lbl.Left = 32; $lbl.Top = 7
  $lbl.BackColor = [System.Drawing.Color]::Transparent
  $form.Controls.Add($lbl)

  $form.Add_Shown({
    [NativeOverlay]::MakeClickThrough($form.Handle)
    [NativeOverlay]::Repin($form.Handle)
  })

  # keep it on top, and bail out if the launcher process is gone
  $timer = New-Object System.Windows.Forms.Timer
  $timer.Interval = 1500
  $timer.Add_Tick({
    try { [NativeOverlay]::Repin($form.Handle) } catch {}
    if ($HostPid -gt 0 -and -not (Get-Process -Id $HostPid -ErrorAction SilentlyContinue)) { $form.Close() }
  })
  $timer.Start()

  [System.Windows.Forms.Application]::Run($form)
} catch {
  # No GUI available (e.g. headless) - the indicator is optional, so just exit quietly.
  exit 0
}
