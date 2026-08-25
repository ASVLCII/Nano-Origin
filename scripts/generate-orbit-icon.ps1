param(
  [string]$Output = (Join-Path $PSScriptRoot 'launcher\nano-origin.ico'),
  [string]$Source = (Join-Path $PSScriptRoot 'launcher\orbit-official.png')
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
if (-not (Test-Path -LiteralPath $Source -PathType Leaf)) { throw "Missing official Orbit source: $Source" }
$official = [Drawing.Image]::FromFile((Resolve-Path -LiteralPath $Source).Path)

$sizes = 16,24,32,48,64,128,256
$images = [Collections.Generic.List[byte[]]]::new()

foreach ($size in $sizes) {
  $bitmap = [Drawing.Bitmap]::new($size, $size, [Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  try {
    $graphics.Clear([Drawing.Color]::Black)
    $graphics.SmoothingMode = [Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.PixelOffsetMode = [Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.InterpolationMode = [Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $graphics.DrawImage($official, [Drawing.Rectangle]::new(0,0,$size,$size))

    $stream = [IO.MemoryStream]::new()
    try {
      $bitmap.Save($stream, [Drawing.Imaging.ImageFormat]::Png)
      $images.Add($stream.ToArray())
    } finally {
      $stream.Dispose()
    }
  } finally {
    $graphics.Dispose()
    $bitmap.Dispose()
  }
}
$official.Dispose()

$parent = Split-Path -Parent ([IO.Path]::GetFullPath($Output))
New-Item -ItemType Directory -Force -Path $parent | Out-Null
$file = [IO.File]::Open($Output, [IO.FileMode]::Create, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
  $writer = [IO.BinaryWriter]::new($file, [Text.Encoding]::ASCII, $true)
  $writer.Write([uint16]0)
  $writer.Write([uint16]1)
  $writer.Write([uint16]$sizes.Count)
  $offset = 6 + 16 * $sizes.Count
  for ($i = 0; $i -lt $sizes.Count; $i++) {
    $size = $sizes[$i]
    $dimension = if ($size -eq 256) { 0 } else { $size }
    $writer.Write([byte]$dimension)
    $writer.Write([byte]$dimension)
    $writer.Write([byte]0)
    $writer.Write([byte]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]32)
    $writer.Write([uint32]$images[$i].Length)
    $writer.Write([uint32]$offset)
    $offset += $images[$i].Length
  }
  foreach ($image in $images) { $writer.Write($image) }
  $writer.Flush()
  $file.Flush($true)
} finally {
  $file.Dispose()
}

[pscustomobject]@{
  Icon = $Output
  Sizes = ($sizes -join ',')
  Bytes = (Get-Item -LiteralPath $Output).Length
  SHA256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $Output).Hash
} | Format-List
