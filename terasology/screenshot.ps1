param([Parameter(Mandatory = $true)][string]$Path, [string]$Window = '')
# Capture a window, found by the start of its title (the game's is "Terasology
# Alpha"), to a PNG. With no title, or no such window, every display there is:
# on a machine with several, the game opens wherever the OS puts it, and the
# primary display alone can be a monitor nothing is drawn on. Needs an
# interactive, unlocked session: behind the lock screen the capture is one
# flat colour (black on most machines, dark brown on Dionysus), and so is
# PrintWindow's view of the window, so a flat picture is named as such.
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -Namespace Naust -Name Win32 -MemberDefinition @'
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
public struct RECT { public int Left, Top, Right, Bottom; }
'@
$bounds = [System.Windows.Forms.SystemInformation]::VirtualScreen
if ($Window) {
    $proc = Get-Process | Where-Object { $_.MainWindowTitle -like "$Window*" } | Select-Object -First 1
    $rect = New-Object 'Naust.Win32+RECT'
    if ($proc -and [Naust.Win32]::GetWindowRect($proc.MainWindowHandle, [ref]$rect) -and $rect.Right -gt $rect.Left -and $rect.Bottom -gt $rect.Top) {
        $bounds = New-Object System.Drawing.Rectangle($rect.Left, $rect.Top, ($rect.Right - $rect.Left), ($rect.Bottom - $rect.Top))
    } else {
        Write-Warning "no window titled '$Window*'; capturing every display instead"
    }
}
$bitmap = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
$bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
$first = $bitmap.GetPixel(0, 0); $flat = $true
foreach ($fx in 0.1, 0.3, 0.5, 0.7, 0.9) {
    foreach ($fy in 0.1, 0.3, 0.5, 0.7, 0.9) {
        if ($bitmap.GetPixel([int]($bounds.Width * $fx), [int]($bounds.Height * $fy)) -ne $first) { $flat = $false }
    }
}
if ($flat) { Write-Warning "the capture is one flat colour ($first): the desktop is probably locked, and a locked desktop shows nothing" }
$graphics.Dispose(); $bitmap.Dispose()
