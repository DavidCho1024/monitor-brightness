using System; using System.Runtime.InteropServices; using System.Text;

// Builds the taskbar right-click "tasks" list (Jump List) for our AppUserModelID.
public static class JumpList {
  [ComImport, Guid("6332DEBF-87B5-4670-90C0-5E57B408A49E"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface ICustomDestinationList {
    void SetAppID([MarshalAs(UnmanagedType.LPWStr)] string id);
    void BeginList(out uint minSlots, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object removed);
    void AppendCategory([MarshalAs(UnmanagedType.LPWStr)] string cat, IObjectArray items);
    void AppendKnownCategory(int cat);
    void AddUserTasks(IObjectArray items);
    void CommitList();
    void GetRemovedDestinations(ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object o);
    void DeleteList([MarshalAs(UnmanagedType.LPWStr)] string id);
    void AbortList();
  }
  [ComImport, Guid("92CA9DCD-5622-4BBA-A805-5E9F541BD8C9"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IObjectArray { void GetCount(out uint n); void GetAt(uint i, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object o); }
  [ComImport, Guid("5632B1A4-E38A-400A-928A-D4CD63230295"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IObjectCollection {
    void GetCount(out uint n); void GetAt(uint i, ref Guid riid, [MarshalAs(UnmanagedType.Interface)] out object o);
    void AddObject([MarshalAs(UnmanagedType.Interface)] object o); void AddFromArray(IObjectArray a); void RemoveObjectAt(uint i); void Clear();
  }
  [ComImport, Guid("000214F9-0000-0000-C000-000000000046"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IShellLinkW {
    void GetPath(StringBuilder f, int c, IntPtr fd, uint fl); void GetIDList(out IntPtr p); void SetIDList(IntPtr p);
    void GetDescription(StringBuilder s, int c); void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetWorkingDirectory(StringBuilder s, int c); void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetArguments(StringBuilder s, int c); void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string s);
    void GetHotkey(out short h); void SetHotkey(short h); void GetShowCmd(out int c); void SetShowCmd(int c);
    void GetIconLocation(StringBuilder s, int c, out int i); void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string s, int i);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string s, uint r); void Resolve(IntPtr h, uint f);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string s);
  }
  [ComImport, Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
  interface IPropertyStore { void GetCount(out uint c); void GetAt(uint i, out PKEY k); void GetValue(ref PKEY k, out PROPVARIANT v); void SetValue(ref PKEY k, ref PROPVARIANT v); void Commit(); }
  [StructLayout(LayoutKind.Sequential, Pack=4)] struct PKEY { public Guid fmtid; public uint pid; }
  [StructLayout(LayoutKind.Sequential)] struct PROPVARIANT { public ushort vt; ushort r1, r2, r3; public IntPtr p; IntPtr p2; }

  static object NewLink(string target, string args, string title, string icon) {
    var link = (IShellLinkW)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("00021401-0000-0000-C000-000000000046")));
    link.SetPath(target); link.SetArguments(args); link.SetIconLocation(icon, 0); link.SetDescription(title);
    var ps = (IPropertyStore)link;
    var key = new PKEY { fmtid = new Guid("F29F85E0-4FF9-1068-AB91-08002B27B3D9"), pid = 2 }; // PKEY_Title
    var v = new PROPVARIANT { vt = 31, p = Marshal.StringToCoTaskMemUni(title) };
    ps.SetValue(ref key, ref v); ps.Commit(); Marshal.FreeCoTaskMem(v.p);
    return link;
  }

  // items: parallel arrays of title / arguments / icon path
  public static void Set(string appId, string target, string[] titles, string[] args, string[] icons) {
    var list = (ICustomDestinationList)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("77F10CF0-3DB5-4966-B520-B7C54FD35ED6")));
    list.SetAppID(appId);
    uint slots; object removed; var iid = typeof(IObjectArray).GUID;
    list.BeginList(out slots, ref iid, out removed);
    var col = (IObjectCollection)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("2D3468C1-36A7-43B6-AC24-D3F02FD9607A")));
    for (int i = 0; i < titles.Length; i++) col.AddObject(NewLink(target, args[i], titles[i], icons[i]));
    if (titles.Length > 0) list.AddUserTasks((IObjectArray)col);
    list.CommitList();
  }
}
