# Monitors Discord voice chat and updates the on-air indicator.
#
# Detection: Queries the Windows Audio Session API (WASAPI) for active audio
# sessions belonging to Discord. An active session means Discord is producing
# or capturing audio, which indicates an active voice/video call.
#
# Usage:
#   $env:SERVER_URL = "http://192.168.1.1:5000"
#   $env:DISCORD_NAME = "discord"
#   .\monitor-discord.ps1
#
# To allow running unsigned scripts:
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

param(
    [string]$ServerUrl   = ($env:SERVER_URL   ?? "http://192.168.1.1:5000"),
    [string]$Name        = ($env:DISCORD_NAME ?? "discord"),
    [int]   $PollSeconds = 5,
    [int]   $RenewSeconds = 60
)

# WASAPI audio session enumeration via COM
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumerator {
    int NotImplemented1();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice ppDevice);
    int GetDevice(string pwstrId, out IMMDevice ppDevice);
    int RegisterEndpointNotificationCallback(IntPtr pClient);
    int UnregisterEndpointNotificationCallback(IntPtr pClient);
    int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IMMDeviceCollection ppDevices);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
    int OpenPropertyStore(int stgmAccess, out IntPtr ppProperties);
    int GetId([MarshalAs(UnmanagedType.LPWStr)] out string ppstrId);
    int GetState(out int pdwState);
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

[Guid("BFA971F1-4D5E-40BB-935E-967039BFBEE4")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionManager2 {
    int GetAudioSessionControl(ref Guid AudioSessionGuid, int StreamFlags, out IAudioSessionControl SessionControl);
    int GetSimpleAudioVolume(ref Guid AudioSessionGuid, int StreamFlags, out IntPtr AudioVolume);
    int GetSessionEnumerator(out IAudioSessionEnumerator SessionEnum);
    int RegisterSessionNotification(IntPtr SessionNotification);
    int UnregisterSessionNotification(IntPtr SessionNotification);
    int RegisterDuckNotification([MarshalAs(UnmanagedType.LPWStr)] string sessionID, IntPtr duckNotification);
    int UnregisterDuckNotification(IntPtr duckNotification);
}

public class AudioUtil {
    public static uint[] GetAudioSessionPids() {
        var deviceEnumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(deviceEnumeratorType);

        IMMDevice device;
        enumerator.GetDefaultAudioEndpoint(0 /* eRender */, 1 /* eCommunications */, out device);

        object sessionManagerObj;
        var iidSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        device.Activate(ref iidSessionManager2, 23 /* CLSCTX_ALL */, IntPtr.Zero, out sessionManagerObj);
        var sessionManager = (IAudioSessionManager2)sessionManagerObj;

        IAudioSessionEnumerator sessionEnum;
        sessionManager.GetSessionEnumerator(out sessionEnum);

        int count;
        sessionEnum.GetCount(out count);

        var pids = new System.Collections.Generic.List<uint>();
        for (int i = 0; i < count; i++) {
            IAudioSessionControl session;
            sessionEnum.GetSession(i, out session);
            var session2 = session as IAudioSessionControl2;
            if (session2 != null) {
                uint pid;
                session2.GetProcessId(out pid);
                pids.Add(pid);
            }
        }
        return pids.ToArray();
    }
}
'@ -ErrorAction Stop

function Get-DiscordAudioPid {
    # Collect all Discord.exe PIDs
    $discordProcs = Get-Process -Name "Discord" -ErrorAction SilentlyContinue
    if (-not $discordProcs) { return $false }
    $discordPids = $discordProcs.Id

    try {
        $audioPids = [AudioUtil]::GetAudioSessionPids()
        foreach ($pid in $discordPids) {
            if ($audioPids -contains [uint]$pid) { return $true }
        }
    } catch {
        # WASAPI unavailable; fall back to process check
        Write-Warning "WASAPI unavailable, falling back to process check: $_"
        return ($discordProcs.Count -gt 0)
    }
    return $false
}

function Send-Notification([string]$State) {
    try {
        $null = Invoke-WebRequest -Uri "${ServerUrl}/${State}?name=${Name}" `
            -Method Get -UseBasicParsing -TimeoutSec 5
    } catch {
        Write-Warning "Request failed: $_"
    }
}

$active    = $false
$lastSent  = [datetime]::MinValue

Write-Host "Watching Discord voice (server: $ServerUrl, name: $Name)"

while ($true) {
    $now = [datetime]::UtcNow
    $inVoice = Get-DiscordAudioPid

    if ($inVoice) {
        if (-not $active -or ($now - $lastSent).TotalSeconds -ge $RenewSeconds) {
            Send-Notification "on"
            Write-Host "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') ON"
            $active   = $true
            $lastSent = $now
        }
    } else {
        if ($active) {
            Send-Notification "off"
            Write-Host "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') OFF"
            $active = $false
        }
    }

    Start-Sleep -Seconds $PollSeconds
}
