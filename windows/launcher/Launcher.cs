// Tiny launcher: runs scripts\<name>.ps1 (next to the exe) with Windows PowerShell.
// Build with build.ps1 (uses the csc.exe that ships with .NET Framework 4.x on every Windows 10/11).
//   /define:SETUP     -> CameraController-Setup.exe     -> scripts\install.ps1
//   /define:START     -> CameraController-Start.exe     -> scripts\start.ps1
//   /define:UNINSTALL -> CameraController-Uninstall.exe -> scripts\uninstall.ps1
using System;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;

static class Launcher
{
#if SETUP
    const string ScriptName = "install.ps1";
    const bool KillChildrenOnClose = false;
#elif START
    const string ScriptName = "start.ps1";
    const bool KillChildrenOnClose = true;   // closing the window stops the server and USB forwarding
#elif UNINSTALL
    const string ScriptName = "uninstall.ps1";
    const bool KillChildrenOnClose = false;
#else
#error Define SETUP, START or UNINSTALL
#endif

    static int Main(string[] args)
    {
        if (KillChildrenOnClose)
        {
            try { PutSelfIntoKillOnCloseJob(); } catch { }
        }
        // Ctrl+C is handled by the PowerShell script (it cleans up); keep the launcher alive meanwhile.
        Console.CancelKeyPress += delegate(object s, ConsoleCancelEventArgs e) { e.Cancel = true; };

        string dir = AppDomain.CurrentDomain.BaseDirectory;
        string script = Path.Combine(Path.Combine(dir, "scripts"), ScriptName);
        if (!File.Exists(script))
        {
            Console.WriteLine("Missing file: " + script);
            Console.WriteLine("Keep the exe files together with the 'scripts' and 'linux' folders.");
            Console.WriteLine("Press Enter to exit.");
            Console.ReadLine();
            return 2;
        }

        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System),
                                 @"WindowsPowerShell\v1.0\powershell.exe");
        string arguments = "-NoProfile -NoLogo -ExecutionPolicy Bypass -File \"" + script + "\"";
        foreach (string a in args) arguments += " \"" + a.Replace("\"", "\\\"") + "\"";

        ProcessStartInfo psi = new ProcessStartInfo(ps, arguments);
        psi.UseShellExecute = false;
        psi.WorkingDirectory = dir;
        using (Process p = Process.Start(psi))
        {
            p.WaitForExit();
            return p.ExitCode;
        }
    }

    // ---- Job object: when this launcher dies (e.g. the console window is closed), Windows kills
    //      every process it started (wsl.exe server, usbipd auto-attach, keep-alive).

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_BASIC_LIMIT_INFORMATION
    {
        public long PerProcessUserTimeLimit;
        public long PerJobUserTimeLimit;
        public uint LimitFlags;
        public UIntPtr MinimumWorkingSetSize;
        public UIntPtr MaximumWorkingSetSize;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint PriorityClass;
        public uint SchedulingClass;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct IO_COUNTERS
    {
        public ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
        public ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
    }

    [StructLayout(LayoutKind.Sequential)]
    struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION
    {
        public JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
        public IO_COUNTERS IoInfo;
        public UIntPtr ProcessMemoryLimit;
        public UIntPtr JobMemoryLimit;
        public UIntPtr PeakProcessMemoryUsed;
        public UIntPtr PeakJobMemoryUsed;
    }

    const int JobObjectExtendedLimitInformation = 9;
    const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x2000;

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr lpJobAttributes, string lpName);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr hJob, int infoClass,
        ref JOBOBJECT_EXTENDED_LIMIT_INFORMATION info, uint cbInfo);

    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr hJob, IntPtr hProcess);

    static IntPtr job;  // kept open for the lifetime of the process

    static void PutSelfIntoKillOnCloseJob()
    {
        job = CreateJobObject(IntPtr.Zero, null);
        if (job == IntPtr.Zero) return;
        JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
        info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
        SetInformationJobObject(job, JobObjectExtendedLimitInformation, ref info,
            (uint)Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION)));
        AssignProcessToJobObject(job, Process.GetCurrentProcess().Handle);
    }
}
