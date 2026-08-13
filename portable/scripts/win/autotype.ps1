# ============================================================
#  autotype.ps1  -  Simple "auto typer" for Windows using SendKeys
#
#  HOW TO USE:
#   1. Edit $TextToType below with what you want typed.
#   2. Run: powershell -ExecutionPolicy Bypass -File autotype.ps1
#   3. Within the countdown, click into the target terminal window
#      so it has keyboard focus.
#   4. It types the text (no Enter key pressed at the end).
# ============================================================

$DELAY_SECONDS = 5      # seconds to wait before typing starts
$CHAR_DELAY_MS = 20     # delay between each character (raise if chars get dropped)

$TextToType = "TEXT TO TYPE HERE"

# Load Windows.Forms assembly for SendKeys
Add-Type -AssemblyName System.Windows.Forms

Write-Host "Starting in $DELAY_SECONDS seconds... Click your target window now!"
Start-Sleep -Seconds $DELAY_SECONDS

foreach ($ch in $TextToType.ToCharArray()) {
    # SendKeys reserves these chars: {}, +, ^, % — wrap them in braces to type literally
    if ($ch -in @('{', '}', '+', '^', '%', '(', ')')) {
        [System.Windows.Forms.SendKeys]::SendKeys("{$ch}")
    } else {
        [System.Windows.Forms.SendKeys]::SendKeys($ch)
    }
    Start-Sleep -Milliseconds $CHAR_DELAY_MS
}
