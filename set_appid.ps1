param([string]$AppId = 'PixelBrightness.App', [string[]]$Paths)
# Tags the shortcuts with our AppUserModelID so the running window groups with the pinned icon
Add-Type -TypeDefinition @'
using System; using System.Runtime.InteropServices;
public static class AppIdTag {
  [StructLayout(LayoutKind.Sequential, Pack=4)] public struct PKEY { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Sequential)] public struct PROPVARIANT { public ushort vt; ushort r1, r2, r3; public IntPtr p; IntPtr p2; }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore { int GetCount(out uint c); int GetAt(uint i, out PKEY k); int GetValue(ref PKEY k, out PROPVARIANT v); int SetValue(ref PKEY k, ref PROPVARIANT v); int Commit(); }
  [DllImport("shell32.dll", CharSet=CharSet.Unicode)] static extern int SHGetPropertyStoreFromParsingName(string path, IntPtr bc, int flags, ref Guid iid, out IPropertyStore ps);
  public static int Set(string lnk, string id) {
    Guid iid = typeof(IPropertyStore).GUID; IPropertyStore ps;
    int hr = SHGetPropertyStoreFromParsingName(lnk, IntPtr.Zero, 2 /* GPS_READWRITE */, ref iid, out ps); if (hr != 0) return hr;
    var key = new PKEY { fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"), pid = 5 };
    var v = new PROPVARIANT { vt = 31 /* VT_LPWSTR */, p = Marshal.StringToCoTaskMemUni(id) };
    hr = ps.SetValue(ref key, ref v); if (hr == 0) hr = ps.Commit();
    Marshal.FreeCoTaskMem(v.p); Marshal.ReleaseComObject(ps); return hr;
  } }
'@
if (-not $Paths) { $Paths = @((Join-Path ([Environment]::GetFolderPath('Desktop')) '밝기 전환.lnk'), (Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar\밝기 전환.lnk')) }
foreach ($l in $Paths) {
  if (Test-Path $l) { "$l -> hr=$([AppIdTag]::Set($l, $AppId))" }
}
