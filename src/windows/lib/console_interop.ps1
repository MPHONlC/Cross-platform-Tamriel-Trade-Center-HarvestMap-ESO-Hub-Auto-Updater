try {
    $csharp = @"
    using System;
    using System.Runtime.InteropServices;
    public class ConsoleConfig {
        const int SW_HIDE = 0;
        const int SW_RESTORE = 9;
        const int SW_SHOW = 5;
        const uint ENABLE_QUICK_EDIT = 0x0040;
        const int STD_INPUT_HANDLE = -10;
        const int STD_OUTPUT_HANDLE = -11;
        const uint ENABLE_VIRTUAL_TERMINAL_PROCESSING = 0x0004;
        
        [DllImport("kernel32.dll", ExactSpelling = true)]
        public static extern IntPtr GetConsoleWindow();
        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);
        [DllImport("user32.dll")]
        public static extern bool IsIconic(IntPtr hWnd);
        [DllImport("kernel32.dll", SetLastError = true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll")]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out uint lpMode);
        [DllImport("kernel32.dll")]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, uint dwMode);

        public static void DisableQuickEdit() {
            IntPtr consoleHandle = GetStdHandle(STD_INPUT_HANDLE);
            uint consoleMode;
            if (GetConsoleMode(consoleHandle, out consoleMode)) {
                consoleMode &= ~ENABLE_QUICK_EDIT;
                SetConsoleMode(consoleHandle, consoleMode);
            }
        }

        public static void EnableANSI() {
            IntPtr handle = GetStdHandle(STD_OUTPUT_HANDLE);
            uint mode;
            if (GetConsoleMode(handle, out mode)) {
                mode |= ENABLE_VIRTUAL_TERMINAL_PROCESSING;
                SetConsoleMode(handle, mode);
            }
        }
        
        public static void HideWindow() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero) ShowWindow(hWnd, SW_HIDE);
        }
        public static void RestoreWindow() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero) {
                ShowWindow(hWnd, SW_RESTORE);
                ShowWindow(hWnd, SW_SHOW);
                SetForegroundWindow(hWnd);
            }
        }
        public static bool CheckMinimizedAndHide() {
            IntPtr hWnd = GetConsoleWindow();
            if (hWnd != IntPtr.Zero && IsIconic(hWnd)) {
                ShowWindow(hWnd, SW_HIDE);
                return true;
            }
            return false;
        }
    }
"@
    Add-Type -TypeDefinition $csharp -Language CSharp -IgnoreWarnings
    [ConsoleConfig]::DisableQuickEdit()
    [ConsoleConfig]::EnableANSI()
} catch {}

