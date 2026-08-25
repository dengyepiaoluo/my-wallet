Add-Type -AssemblyName System.Drawing

$sizes = @{
  "mipmap-mdpi" = 48
  "mipmap-hdpi" = 72
  "mipmap-xhdpi" = 96
  "mipmap-xxhdpi" = 144
  "mipmap-xxxhdpi" = 192
}

foreach ($k in $sizes.Keys) {
  $s = $sizes[$k]
  $bmp = New-Object System.Drawing.Bitmap($s, $s)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
  $g.Clear([System.Drawing.Color]::Transparent)
  $r = [int]($s * 0.18)
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $path.AddArc(0, 0, $r, $r, 180, 90)
  $path.AddArc($s - $r, 0, $r, $r, 270, 90)
  $path.AddArc($s - $r, $s - $r, $r, $r, 0, 90)
  $path.AddArc(0, $s - $r, $r, $r, 90, 90)
  $path.CloseFigure()
  $brush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 27, 138, 90))
  $g.FillPath($brush, $path)
  $font = New-Object System.Drawing.Font("Microsoft YaHei", [float]($s * 0.52), [System.Drawing.FontStyle]::Bold)
  $sf = New-Object System.Drawing.StringFormat
  $sf.Alignment = [System.Drawing.StringAlignment]::Center
  $sf.LineAlignment = [System.Drawing.StringAlignment]::Center
  $rect = New-Object System.Drawing.RectangleF(0, [float]($s * 0.02), $s, $s)
  $g.DrawString([char]0xA5, $font, [System.Drawing.Brushes]::White, $rect, $sf)
  $dir = "e:\six\my_wallet\android\app\src\main\res\$k"
  New-Item -ItemType Directory -Force -Path $dir | Out-Null
  $bmp.Save("$dir\ic_launcher.png", [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose()
  $bmp.Dispose()
  Write-Host "$k : $s px done"
}
