[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ExePath,
  [Parameter(Mandatory=$true)][string]$DonorExePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

foreach ($path in $ExePath,$DonorExePath) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Missing PE file: $path" }
}

Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class NanoVersionResource {
  public delegate bool EnumResNameProc(IntPtr module, IntPtr type, IntPtr name, IntPtr param);
  public delegate bool EnumResLangProc(IntPtr module, IntPtr type, IntPtr name, ushort lang, IntPtr param);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr LoadLibraryEx(string file, IntPtr h, uint flags);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool FreeLibrary(IntPtr module);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool EnumResourceNames(IntPtr module, IntPtr type, EnumResNameProc callback, IntPtr param);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern bool EnumResourceLanguages(IntPtr module, IntPtr type, IntPtr name, EnumResLangProc callback, IntPtr param);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr FindResourceEx(IntPtr module, IntPtr type, IntPtr name, ushort lang);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr LoadResource(IntPtr module, IntPtr resource);
  [DllImport("kernel32.dll", SetLastError=true)] static extern IntPtr LockResource(IntPtr resource);
  [DllImport("kernel32.dll", SetLastError=true)] static extern uint SizeofResource(IntPtr module, IntPtr resource);
  [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)] static extern IntPtr BeginUpdateResource(string file, bool deleteExisting);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool UpdateResource(IntPtr update, IntPtr type, IntPtr name, ushort lang, byte[] data, uint size);
  [DllImport("kernel32.dll", SetLastError=true)] static extern bool EndUpdateResource(IntPtr update, bool discard);

  const uint LOAD_LIBRARY_AS_DATAFILE = 2;
  static IntPtr Id(int value) { return new IntPtr(value); }

  public static void CopyFirstVersion(string donor, string target) {
    IntPtr module = LoadLibraryEx(donor, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
    if (module == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Load donor PE failed");
    IntPtr foundName = IntPtr.Zero; ushort foundLang = 0;
    try {
      EnumResNameProc names = (m,t,n,p) => {
        foundName = n;
        EnumResLangProc langs = (lm,lt,ln,lang,lp) => { foundLang = lang; return false; };
        EnumResourceLanguages(m, Id(16), n, langs, IntPtr.Zero);
        return false;
      };
      EnumResourceNames(module, Id(16), names, IntPtr.Zero);
      if (foundName == IntPtr.Zero) throw new InvalidOperationException("Donor has no RT_VERSION resource");
      IntPtr info = FindResourceEx(module, Id(16), foundName, foundLang);
      if (info == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Find RT_VERSION failed");
      uint size = SizeofResource(module, info);
      IntPtr loaded = LoadResource(module, info); IntPtr ptr = LockResource(loaded);
      if (ptr == IntPtr.Zero || size == 0) throw new InvalidOperationException("Donor RT_VERSION is empty");
      byte[] bytes = new byte[size]; Marshal.Copy(ptr, bytes, 0, (int)size);
      IntPtr update = BeginUpdateResource(target, false);
      if (update == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "BeginUpdateResource failed");
      bool commit = false;
      try {
        if (!UpdateResource(update, Id(16), Id(1), 0x0409, bytes, size))
          throw new Win32Exception(Marshal.GetLastWin32Error(), "UpdateResource failed");
        commit = true;
      } finally {
        if (!EndUpdateResource(update, !commit)) throw new Win32Exception(Marshal.GetLastWin32Error(), "EndUpdateResource failed");
      }
    } finally { FreeLibrary(module); }
  }
}
'@

[NanoVersionResource]::CopyFirstVersion(
  (Resolve-Path -LiteralPath $DonorExePath).Path,
  (Resolve-Path -LiteralPath $ExePath).Path
)

$info = (Get-Item -LiteralPath $ExePath).VersionInfo
foreach ($field in 'CompanyName','ProductName','FileDescription') {
  if ($info.$field -notlike 'Nano Origin*') { throw "RT_VERSION verification failed: $field=$($info.$field)" }
}
[pscustomobject]@{Exe=$ExePath;CompanyName=$info.CompanyName;ProductName=$info.ProductName;FileDescription=$info.FileDescription}
