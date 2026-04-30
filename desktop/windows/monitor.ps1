# Monitors Discord voice and Zoom audio, updating the on-air indicator for each.
# Each app is tracked independently so they don't interfere with each other.
#
# Detection uses the Windows Audio Session API (WASAPI) to find which process
# PIDs have active audio sessions, matched against Discord/Zoom process IDs.
#
# Usage:
#   $env:SERVER_URL = "http://192.168.1.1:5000"
#   .\monitor.ps1
#
# To allow running unsigned scripts:
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

param(
    [string]$ServerUrl    = ($env:SERVER_URL ?? "http://192.168.1.1:5000"),
    [int]   $PollSeconds  = 5,
    [int]   $RenewSeconds = 60
)

# ── WASAPI via COM ───────────────────────────────────────────────────────────

Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int NotImplemented1();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams,
                 [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionEnumerator {
    int GetCount(out int SessionCount);
    int GetSession(int SessionCount, out IAudioSessionControl Session);
}

[Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl {
    int GetState(out int pRetVal);
    int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string Value, ref Guid EventContext);
    int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string Value, ref Guid EventContext);
    int GetGroupingParam(out Guid pRetVal);
    int SetGroupingParam(ref Guid Override, ref Guid EventContext);
    int RegisterAudioSessionNotification(IntPtr NewNotifications);
    int UnregisterAudioSessionNotification(IntPtr NewNotifications);
}

[Guid("bfb7ff88-7239-4fc9-8fa2-07c950be9c6d")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControl2 {
    int GetState(out int pRetVal);
    int GetDisplayName([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetDisplayName([MarshalAs(UnmanagedType.LPWStr)] string Value, ref Guid EventContext);
    int GetIconPath([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int SetIconPath([MarshalAs(UnmanagedType.LPWStr)] string Value, ref Guid EventContext);
    int GetGroupingParam(out Guid pRetVal);
    int SetGroupingParam(ref Guid Override, ref Guid EventContext);
    int RegisterAudioSessionNotification(IntPtr NewNotifications);
    int UnregisterAudioSessionNotification(IntPtr NewNotifications);
    int GetSessionIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int GetSessionInstanceIdentifier([MarshalAs(UnmanagedType.LPWStr)] out string pRetVal);
    int GetProcessId(out uint pRetVal);
    int IsSystemSoundsSession();
    int SetDuckingPreference(bool optOut);
}

[Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionManager2 {
    int GetAudioSessionControl(ref Guid AudioSessionGuid, int StreamFlags,
                               out IAudioSessionControl SessionControl);
    int GetSimpleAudioVolume(ref Guid AudioSessionGuid, int StreamFlags,
                             out IntPtr AudioVolume);
    int GetSessionEnumerator(out IAudioSessionEnumerator SessionEnum);
}

public static class Wasapi {
    public static uint[] AudioSessionPids() {
        var clsid = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(
            Type.GetTypeFromCLSID(clsid));

        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0 /* eRender */, 1 /* eCommunications */,
                                           out device);

        object mgr;
        var iid = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        device.Activate(ref iid, 23 /* CLSCTX_ALL */, IntPtr.Zero, out mgr);

        IAudioSessionEnumerator sessions;
        ((IAudioSessionManager2)mgr).GetSessionEnumerator(out sessions);

        int count;
        sessions.GetCount(out count);

        var pids = new System.Collections.Generic.List<uint>();
        for (int i = 0; i < count; i++) {
            IAudioSessionControl ctrl;
            sessions.GetSession(i, out ctrl);
            var ctrl2 = ctrl as IAudioSessionControl2;
            if (ctrl2 != null) {
                uint pid;
                ctrl2.GetProcessId(out pid);
                pids.Add(pid);
            }
        }
        return pids.ToArray();
    }
}
'@ -ErrorAction Stop

# ── Shared helpers ───────────────────────────────────────────────────────────

function Get-AudioSessionPids {
    try   { [Wasapi]::AudioSessionPids() }
    catch { @() }
}

function Test-ProcessHasAudio([string[]]$Names) {
    $procs = Get-Process -Name $Names -ErrorAction SilentlyContinue
    if (-not $procs) { return $false }

    $audioPids = Get-AudioSessionPids
    if ($audioPids.Count -eq 0) {
        # WASAPI unavailable — fall back to process-presence only
        return $true
    }

    foreach ($p in $procs) {
        if ($audioPids -contains [uint]$p.Id) { return $true }
    }
    return $false
}

function Send-Notification([string]$State, [string]$Name) {
    try {
        $null = Invoke-WebRequest -Uri "${ServerUrl}/${State}?name=${Name}" `
            -Method Get -UseBasicParsing -TimeoutSec 5
    } catch {
        Write-Warning "${Name}: request failed — $_"
    }
}

# ── App detection ────────────────────────────────────────────────────────────

function Test-DiscordActive {
    # Discord voice/video uses WebRTC; an active audio session means a live call
    Test-ProcessHasAudio "Discord"
}

function Test-ZoomActive {
    # CptHost.exe is Zoom's media host; Zoom.exe checked as fallback for older versions
    Test-ProcessHasAudio "CptHost", "Zoom"
}

# ── Core ─────────────────────────────────────────────────────────────────────

# Invoke-AppCheck tracks per-app state in $AppStates and handles on/off/renew.
function Invoke-AppCheck([string]$Name, [scriptblock]$Test, [hashtable]$AppStates) {
    $s   = $AppStates[$Name]
    $now = [datetime]::UtcNow

    if (& $Test) {
        if (-not $s.Active -or ($now - $s.LastSent).TotalSeconds -ge $RenewSeconds) {
            Send-Notification "on" $Name
            Write-Host "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') $Name ON"
            $s.Active   = $true
            $s.LastSent = $now
        }
    } else {
        if ($s.Active) {
            Send-Notification "off" $Name
            Write-Host "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') $Name OFF"
            $s.Active = $false
        }
    }
}

# ── Main loop ────────────────────────────────────────────────────────────────

$state = @{
    discord = @{ Active = $false; LastSent = [datetime]::MinValue }
    zoom    = @{ Active = $false; LastSent = [datetime]::MinValue }
}

Write-Host "Monitoring Discord and Zoom (server: $ServerUrl)"

while ($true) {
    Invoke-AppCheck "discord" { Test-DiscordActive } $state
    Invoke-AppCheck "zoom"    { Test-ZoomActive    } $state
    Start-Sleep -Seconds $PollSeconds
}
