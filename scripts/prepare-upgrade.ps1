param(
    [Parameter(Mandatory=$true)]
    [string]$InstallRoot,
    [string]$LogPath = (Join-Path $env:TEMP 'PocketTTS-Setup-LockFix.log')
)

$ErrorActionPreference = 'Stop'
$transcriptStarted = $false
try {
    Start-Transcript -Path $LogPath -Append | Out-Null
    $transcriptStarted = $true
} catch {}
trap {
    $failure = "Pocket TTS lock preparation failed: $($_.Exception.Message)"
    if ($transcriptStarted) {
        try { Write-Output $failure; Stop-Transcript | Out-Null } catch {}
    }
    [Console]::Error.WriteLine($failure)
    exit 1
}
$install = [IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
$workerPath = [IO.Path]::GetFullPath((Join-Path $install 'pocket-tts.exe'))
$dllPath = [IO.Path]::GetFullPath((Join-Path $install 'pocket_sapi.dll'))
$currentPowerShell = $PID
$parentProcessId = (Get-CimInstance Win32_Process -Filter "ProcessId=$PID").ParentProcessId

# Stop only the Pocket TTS worker started from this installation.
Get-CimInstance Win32_Process -Filter "Name='pocket-tts.exe'" -ErrorAction SilentlyContinue |
    Where-Object {
        $_.ExecutablePath -and
        [string]::Equals([IO.Path]::GetFullPath($_.ExecutablePath), $workerPath, [StringComparison]::OrdinalIgnoreCase) -and
        $_.CommandLine -match '\bserve\b'
    } |
    ForEach-Object {
        Write-Output "Stopping Pocket TTS worker PID $($_.ProcessId)."
        Stop-Process -Id $_.ProcessId -Force -ErrorAction Stop
        $null = Wait-Process -Id $_.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
    }

$interop = @'
using System;
using System.Runtime.InteropServices;

public static class PocketTtsRestartManager
{
    [StructLayout(LayoutKind.Sequential)]
    public struct FileTimeParts
    {
        public uint Low;
        public uint High;
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct UniqueProcess
    {
        public int ProcessId;
        public FileTimeParts StartTime;
    }

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    public struct ProcessInfo
    {
        public UniqueProcess Process;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 256)]
        public string ApplicationName;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 64)]
        public string ServiceName;
        public uint ApplicationType;
        public uint ApplicationStatus;
        public uint SessionId;
        [MarshalAs(UnmanagedType.Bool)]
        public bool Restartable;
    }

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmStartSession(out uint handle, int flags, string sessionKey);

    [DllImport("rstrtmgr.dll", CharSet = CharSet.Unicode)]
    public static extern int RmRegisterResources(
        uint handle, uint fileCount, string[] files,
        uint appCount, UniqueProcess[] apps,
        uint serviceCount, string[] services);

    [DllImport("rstrtmgr.dll")]
    public static extern int RmGetList(
        uint handle, out uint needed, ref uint count,
        IntPtr processInfo, ref uint rebootReasons);

    [DllImport("rstrtmgr.dll")]
    public static extern int RmEndSession(uint handle);
}
'@
Add-Type -TypeDefinition $interop -Language CSharp

function Get-PocketTtsFileOwner {
    param([string[]]$Files)

    [uint32]$session = 0
    $sessionKey = [guid]::NewGuid().ToString('N')
    $result = [PocketTtsRestartManager]::RmStartSession([ref]$session, 0, $sessionKey)
    if ($result -ne 0) { throw "Windows Restart Manager could not start (error $result)." }

    try {
        $result = [PocketTtsRestartManager]::RmRegisterResources(
            $session, [uint32]$Files.Length, $Files, [uint32]0, $null, [uint32]0, $null)
        if ($result -ne 0) { throw "Windows Restart Manager could not inspect Pocket TTS files (error $result)." }

        [uint32]$needed = 0
        [uint32]$count = 0
        [uint32]$rebootReasons = 0
        $result = [PocketTtsRestartManager]::RmGetList(
            $session, [ref]$needed, [ref]$count, [IntPtr]::Zero, [ref]$rebootReasons)
        if ($result -eq 0 -and $needed -eq 0) { return @() }
        if ($result -ne 234) { throw "Windows Restart Manager could not list file owners (error $result)." }

        $itemSize = [Runtime.InteropServices.Marshal]::SizeOf([type][PocketTtsRestartManager+ProcessInfo])
        $buffer = [Runtime.InteropServices.Marshal]::AllocHGlobal($itemSize * $needed)
        try {
            $count = $needed
            $result = [PocketTtsRestartManager]::RmGetList(
                $session, [ref]$needed, [ref]$count, $buffer, [ref]$rebootReasons)
            if ($result -ne 0) { throw "Windows Restart Manager could not read file owners (error $result)." }

            $owners = @()
            for ($i = 0; $i -lt $count; $i++) {
                $item = [Runtime.InteropServices.Marshal]::PtrToStructure(
                    [IntPtr]::Add($buffer, $i * $itemSize),
                    [type][PocketTtsRestartManager+ProcessInfo])
                $owners += [pscustomobject]@{
                    ProcessId = $item.Process.ProcessId
                    Name = $item.ApplicationName
                    Type = $item.ApplicationType
                    Restartable = $item.Restartable
                }
            }
            return $owners
        } finally {
            [Runtime.InteropServices.Marshal]::FreeHGlobal($buffer)
        }
    } finally {
        [void][PocketTtsRestartManager]::RmEndSession($session)
    }
}

$targets = @($workerPath, $dllPath) | Where-Object { Test-Path -LiteralPath $_ }
if (-not $targets.Count) {
    Write-Output 'No existing Pocket TTS files need to be unlocked.'
    exit 0
}
$excludedIds = @($currentPowerShell, [int]$parentProcessId, 0, 4)
Write-Output "Checking installer file locks for: $($targets -join ', ')"

for ($attempt = 0; $attempt -lt 3; $attempt++) {
    $owners = @(Get-PocketTtsFileOwner -Files $targets)
    foreach ($owner in $owners) {
        Write-Output "Restart Manager owner: $($owner.Name) (PID $($owner.ProcessId), type $($owner.Type), restartable=$($owner.Restartable))."
    }
    $closable = @($owners | Where-Object {
        $_.ProcessId -notin $excludedIds -and
        $_.Type -notin @(3, 4, 1000)
    })
    if (-not $closable.Count) { break }

    foreach ($owner in $closable) {
        try {
            $process = Get-Process -Id $owner.ProcessId -ErrorAction SilentlyContinue
            if (-not $process) { continue }
            Write-Output "Closing $($owner.Name) (PID $($owner.ProcessId)) because it is using a Pocket TTS install file."
            if ($process.MainWindowHandle -ne 0) {
                [void]$process.CloseMainWindow()
                $null = Wait-Process -Id $owner.ProcessId -Timeout 6 -ErrorAction SilentlyContinue
            }
            if (Get-Process -Id $owner.ProcessId -ErrorAction SilentlyContinue) {
                Stop-Process -Id $owner.ProcessId -Force -ErrorAction SilentlyContinue
                $null = Wait-Process -Id $owner.ProcessId -Timeout 10 -ErrorAction SilentlyContinue
            }
            # Process exit can lag after the close/kill call. The next Restart
            # Manager pass decides whether the install files remain locked.
        } catch {
            throw "Could not close process $($owner.Name) (PID $($owner.ProcessId)) holding a Pocket TTS file. $($_.Exception.Message)"
        }
    }
    Start-Sleep -Milliseconds 500
}

$remaining = @(Get-PocketTtsFileOwner -Files $targets | Where-Object { $_.ProcessId -notin $excludedIds })
if ($remaining.Count) {
    $details = ($remaining | ForEach-Object { "$($_.Name) (PID $($_.ProcessId), type $($_.Type))" }) -join ', '
    throw "Pocket TTS files are still in use by: $details"
}

Write-Output 'Pocket TTS update files are unlocked.'
if ($transcriptStarted) { Stop-Transcript | Out-Null }
