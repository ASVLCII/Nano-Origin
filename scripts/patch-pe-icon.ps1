param(
  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $ExePath,

  [Parameter(Mandatory = $true)]
  [ValidateNotNullOrEmpty()]
  [string] $IconPath,

  [Parameter(Mandatory = $false)]
  [ValidateNotNullOrEmpty()]
  [string] $BackupPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class NativeResource {
    public delegate bool EnumResNameProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, IntPtr lParam);
    public delegate bool EnumResLangProc(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, ushort wIDLanguage, IntPtr lParam);

    public sealed class ResourceRef {
        public IntPtr Name;
        public ushort Language;
        public string DisplayName;
    }

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr LoadLibraryEx(string lpFileName, IntPtr hFile, uint dwFlags);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool FreeLibrary(IntPtr hModule);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool EnumResourceNames(IntPtr hModule, IntPtr lpszType, EnumResNameProc lpEnumFunc, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool EnumResourceLanguages(IntPtr hModule, IntPtr lpszType, IntPtr lpszName, EnumResLangProc lpEnumFunc, IntPtr lParam);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern IntPtr BeginUpdateResource(string pFileName, bool bDeleteExistingResources);

    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    public static extern bool UpdateResource(IntPtr hUpdate, IntPtr lpType, IntPtr lpName, ushort wLanguage, byte[] lpData, uint cbData);

    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool EndUpdateResource(IntPtr hUpdate, bool fDiscard);

    public const uint LOAD_LIBRARY_AS_DATAFILE = 0x00000002;

    public static IntPtr IntResource(ushort id) {
        return new IntPtr(id);
    }

    public static bool IsIntResource(IntPtr value) {
        return ((long)value >> 16) == 0;
    }

    public static string ResourceNameToString(IntPtr value) {
        if (IsIntResource(value)) {
            return "#" + ((ushort)value.ToInt64()).ToString();
        }
        return Marshal.PtrToStringUni(value);
    }

    private static IntPtr CopyResourceName(IntPtr value) {
        if (IsIntResource(value)) {
            return IntResource((ushort)value.ToInt64());
        }
        return Marshal.StringToHGlobalUni(Marshal.PtrToStringUni(value));
    }

    public static List<ResourceRef> EnumRefs(string fileName, ushort typeId) {
        var refs = new List<ResourceRef>();
        IntPtr module = LoadLibraryEx(fileName, IntPtr.Zero, LOAD_LIBRARY_AS_DATAFILE);
        if (module == IntPtr.Zero) {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "LoadLibraryEx failed while reading resources");
        }

        EnumResLangProc langCallback = (hModule, lpszType, lpszName, wIDLanguage, lParam) => {
            IntPtr copiedName = CopyResourceName(lpszName);
            refs.Add(new ResourceRef {
                Name = copiedName,
                Language = wIDLanguage,
                DisplayName = ResourceNameToString(copiedName)
            });
            return true;
        };

        EnumResNameProc callback = (hModule, lpszType, lpszName, lParam) => {
            bool okLang = EnumResourceLanguages(hModule, lpszType, lpszName, langCallback, IntPtr.Zero);
            if (!okLang) {
                int error = Marshal.GetLastWin32Error();
                if (error != 1815) {
                    throw new Win32Exception(error, "EnumResourceLanguages failed");
                }
            }
            return true;
        };

        try {
            bool ok = EnumResourceNames(module, IntResource(typeId), callback, IntPtr.Zero);
            if (!ok) {
                int error = Marshal.GetLastWin32Error();
                if (error != 1813) {
                    throw new Win32Exception(error, "EnumResourceNames failed");
                }
            }
            GC.KeepAlive(langCallback);
            GC.KeepAlive(callback);
            return refs;
        } finally {
            FreeLibrary(module);
        }
    }

    public static void FreeResourceRefs(List<ResourceRef> refs) {
        foreach (ResourceRef resourceRef in refs) {
            if (!IsIntResource(resourceRef.Name)) {
                Marshal.FreeHGlobal(resourceRef.Name);
            }
        }
    }

    public static string LastErrorMessage(string operation) {
        return new Win32Exception(Marshal.GetLastWin32Error(), operation + " failed").Message;
    }
}
'@

function Resolve-ExistingFile {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Path,

    [Parameter(Mandatory = $true)]
    [string] $Label
  )

  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "$Label does not exist or is not a file: $Path"
  }
  return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Read-UInt16LE {
  param(
    [byte[]] $Bytes,
    [int] $Offset
  )

  return [BitConverter]::ToUInt16($Bytes, $Offset)
}

function Read-UInt32LE {
  param(
    [byte[]] $Bytes,
    [int] $Offset
  )

  return [BitConverter]::ToUInt32($Bytes, $Offset)
}

function Get-IcoImages {
  param([Parameter(Mandatory = $true)][string] $Path)

  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -lt 6) {
    throw "ICO is too small to contain a header: $Path"
  }

  $reserved = Read-UInt16LE $bytes 0
  $type = Read-UInt16LE $bytes 2
  $count = Read-UInt16LE $bytes 4

  if ($reserved -ne 0) {
    throw "ICO reserved field must be 0."
  }
  if ($type -ne 1) {
    throw "ICO type must be 1 for icons; found $type."
  }
  if ($count -lt 1) {
    throw "ICO contains no images."
  }
  if ($count -gt 256) {
    throw "ICO contains an unreasonable number of images: $count."
  }

  $directoryBytes = 6 + (16 * [int]$count)
  if ($bytes.Length -lt $directoryBytes) {
    throw "ICO directory is truncated."
  }

  $ranges = New-Object 'System.Collections.Generic.List[object]'
  $images = New-Object 'System.Collections.Generic.List[object]'

  for ($i = 0; $i -lt $count; $i++) {
    $entryOffset = 6 + (16 * $i)
    $size = [uint64](Read-UInt32LE $bytes ($entryOffset + 8))
    $offset = [uint64](Read-UInt32LE $bytes ($entryOffset + 12))

    if ($size -eq 0) {
      throw "ICO image $i has zero length."
    }
    if ($offset -lt [uint64]$directoryBytes) {
      throw "ICO image $i starts inside the header or directory."
    }
    if ($offset -gt [uint64]$bytes.Length -or $size -gt ([uint64]$bytes.Length - $offset)) {
      throw "ICO image $i points outside the file."
    }

    $end = $offset + $size
    foreach ($range in $ranges) {
      if ($offset -lt $range.End -and $end -gt $range.Start) {
        throw "ICO image $i overlaps another image payload."
      }
    }
    $ranges.Add([pscustomobject]@{ Start = $offset; End = $end }) | Out-Null

    $imageData = New-Object byte[] ([int]$size)
    [Array]::Copy($bytes, [int64]$offset, $imageData, 0, [int]$size)

    $images.Add([pscustomobject]@{
      Index = $i
      Width = $bytes[$entryOffset]
      Height = $bytes[$entryOffset + 1]
      ColorCount = $bytes[$entryOffset + 2]
      Reserved = $bytes[$entryOffset + 3]
      Planes = Read-UInt16LE $bytes ($entryOffset + 4)
      BitCount = Read-UInt16LE $bytes ($entryOffset + 6)
      Size = [uint32]$size
      Data = $imageData
      ResourceId = [uint16]($i + 1)
    }) | Out-Null
  }

  foreach ($image in $images) {
    if ($image.Reserved -ne 0) {
      throw "ICO image $($image.Index) reserved byte must be 0."
    }
  }

  return ,$images.ToArray()
}

function Write-UInt16LE {
  param(
    [IO.BinaryWriter] $Writer,
    [uint16] $Value
  )

  $Writer.Write($Value)
}

function Write-UInt32LE {
  param(
    [IO.BinaryWriter] $Writer,
    [uint32] $Value
  )

  $Writer.Write($Value)
}

function New-GroupIconResource {
  param([Parameter(Mandatory = $true)] $Images)

  $stream = [IO.MemoryStream]::new()
  $writer = [IO.BinaryWriter]::new($stream)
  try {
    Write-UInt16LE $writer 0
    Write-UInt16LE $writer 1
    Write-UInt16LE $writer ([uint16]$Images.Count)

    foreach ($image in $Images) {
      $writer.Write([byte]$image.Width)
      $writer.Write([byte]$image.Height)
      $writer.Write([byte]$image.ColorCount)
      $writer.Write([byte]0)
      Write-UInt16LE $writer ([uint16]$image.Planes)
      Write-UInt16LE $writer ([uint16]$image.BitCount)
      Write-UInt32LE $writer ([uint32]$image.Size)
      Write-UInt16LE $writer ([uint16]$image.ResourceId)
    }

    return $stream.ToArray()
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Assert-UpdateResource {
  param(
    [IntPtr] $Handle,
    [uint16] $TypeId,
    [IntPtr] $Name,
    [uint16] $Language,
    [byte[]] $Data,
    [string] $Description
  )

  $size = if ($null -eq $Data) { 0 } else { $Data.Length }
  $ok = [NativeResource]::UpdateResource(
    $Handle,
    [NativeResource]::IntResource($TypeId),
    $Name,
    $Language,
    $Data,
    [uint32]$size
  )

  if (-not $ok) {
    throw ([NativeResource]::LastErrorMessage($Description))
  }
}

function Assert-ResourceRefsMatch {
  param(
    [Parameter(Mandatory = $true)]
    $Refs,

    [Parameter(Mandatory = $true)]
    [uint16[]] $ExpectedIds,

    [Parameter(Mandatory = $true)]
    [string] $Label
  )

  if ($Refs.Count -ne $ExpectedIds.Count) {
    $actual = ($Refs | ForEach-Object { "$($_.DisplayName):$($_.Language)" }) -join ', '
    throw "$Label validation failed: expected $($ExpectedIds.Count) resource(s), found $($Refs.Count): $actual"
  }

  $expectedKeys = @{}
  foreach ($id in $ExpectedIds) {
    $expectedKeys["#$id`:0"] = $true
  }

  foreach ($ref in $Refs) {
    $key = "$($ref.DisplayName):$($ref.Language)"
    if (-not $expectedKeys.ContainsKey($key)) {
      throw "$Label validation failed: unexpected resource tuple $key."
    }
  }
}

$resolvedExe = Resolve-ExistingFile -Path $ExePath -Label 'EXE'
$resolvedIcon = Resolve-ExistingFile -Path $IconPath -Label 'ICO'

if ($PSBoundParameters.ContainsKey('BackupPath')) {
  $backupParent = Split-Path -Parent $BackupPath
  if ($backupParent) {
    New-Item -ItemType Directory -Force -Path $backupParent | Out-Null
  }
  Copy-Item -LiteralPath $resolvedExe -Destination $BackupPath -Force
}

$images = Get-IcoImages -Path $resolvedIcon
$groupData = New-GroupIconResource -Images $images

$rtIcon = [uint16]3
$rtGroupIcon = [uint16]14
$groupId = [uint16]1
$oldIconRefs = $null
$oldGroupRefs = $null
$validationIconRefs = $null
$validationGroupRefs = $null
$updateHandle = [IntPtr]::Zero
$committed = $false

try {
  $oldIconRefs = [NativeResource]::EnumRefs($resolvedExe, $rtIcon)
  $oldGroupRefs = [NativeResource]::EnumRefs($resolvedExe, $rtGroupIcon)

  $updateHandle = [NativeResource]::BeginUpdateResource($resolvedExe, $false)
  if ($updateHandle -eq [IntPtr]::Zero) {
    throw ([NativeResource]::LastErrorMessage('BeginUpdateResource'))
  }

  foreach ($resourceRef in $oldGroupRefs) {
    Assert-UpdateResource -Handle $updateHandle -TypeId $rtGroupIcon -Name $resourceRef.Name -Language $resourceRef.Language -Data $null -Description "Delete RT_GROUP_ICON resource $($resourceRef.DisplayName), language $($resourceRef.Language)"
  }
  foreach ($resourceRef in $oldIconRefs) {
    Assert-UpdateResource -Handle $updateHandle -TypeId $rtIcon -Name $resourceRef.Name -Language $resourceRef.Language -Data $null -Description "Delete RT_ICON resource $($resourceRef.DisplayName), language $($resourceRef.Language)"
  }

  foreach ($image in $images) {
    Assert-UpdateResource -Handle $updateHandle -TypeId $rtIcon -Name ([NativeResource]::IntResource($image.ResourceId)) -Language 0 -Data $image.Data -Description "Update RT_ICON resource $($image.ResourceId)"
  }

  Assert-UpdateResource -Handle $updateHandle -TypeId $rtGroupIcon -Name ([NativeResource]::IntResource($groupId)) -Language 0 -Data $groupData -Description "Update RT_GROUP_ICON resource $groupId"

  $commitOk = [NativeResource]::EndUpdateResource($updateHandle, $false)
  $updateHandle = [IntPtr]::Zero
  if (-not $commitOk) {
    throw ([NativeResource]::LastErrorMessage('EndUpdateResource commit'))
  }
  $committed = $true

  $validationIconRefs = [NativeResource]::EnumRefs($resolvedExe, $rtIcon)
  $validationGroupRefs = [NativeResource]::EnumRefs($resolvedExe, $rtGroupIcon)
  $expectedIconIds = [uint16[]]($images | ForEach-Object { [uint16]$_.ResourceId })
  Assert-ResourceRefsMatch -Refs $validationIconRefs -ExpectedIds $expectedIconIds -Label 'RT_ICON'
  Assert-ResourceRefsMatch -Refs $validationGroupRefs -ExpectedIds ([uint16[]]@($groupId)) -Label 'RT_GROUP_ICON'

  Write-Host "Patched icon resources in $resolvedExe from $resolvedIcon."
  Write-Host "Installed $($images.Count) RT_ICON image(s) with IDs 1..$($images.Count) and RT_GROUP_ICON ID 1, language neutral."
} finally {
  if ($updateHandle -ne [IntPtr]::Zero -and -not $committed) {
    [void][NativeResource]::EndUpdateResource($updateHandle, $true)
  }
  if ($null -ne $oldIconRefs) {
    [NativeResource]::FreeResourceRefs($oldIconRefs)
  }
  if ($null -ne $oldGroupRefs) {
    [NativeResource]::FreeResourceRefs($oldGroupRefs)
  }
  if ($null -ne $validationIconRefs) {
    [NativeResource]::FreeResourceRefs($validationIconRefs)
  }
  if ($null -ne $validationGroupRefs) {
    [NativeResource]::FreeResourceRefs($validationGroupRefs)
  }
}
