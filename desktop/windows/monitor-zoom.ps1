# Monitors Zoom audio and updates the on-air indicator.
#
# Detection: Queries the Windows Audio Session API (WASAPI) for active audio
# sessions belonging to Zoom. An active audio session for CptHost.exe (Zoom's
# media host process) or Zoom.exe reliably indicates an active meeting with
# audio. Falls back to a CptHost.exe process check if WASAPI is unavailable.
#
# Usage:
#   $env:SERVER_URL = "http://192.168.1.1:5000"
#   $env:ZOOM_NAME  = "zoom"
#   .\monitor-zoom.ps1
#
# To allow running unsigned scripts:
#   Set-ExecutionPolicy -Scope CurrentUser RemoteSigned

param(
    [string]$ServerUrl    = ($env:SERVER_URL  ?? "http://192.168.1.1:5000"),
    [string]$Name         = ($env:ZOOM_NAME   ?? "zoom"),
    [int]   $PollSeconds  = 5,
    [int]   $RenewSeconds = 60
)

# WASAPI audio session enumeration via COM
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceEnumeratorZ {
    int NotImplemented1();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDeviceZ ppDevice);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IMMDeviceZ {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[Guid("E2F5BB11-0570-40CA-ACDD-3AA01277DEE8")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionEnumeratorZ {
    int GetCount(out int SessionCount);
    int GetSession(int SessionCount, out IAudioSessionControlZ Session);
}

[Guid("F4B1A599-7266-4319-A8CA-E70ACB11E8CD")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IAudioSessionControlZ {
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
public interface IAudioSessionControl2Z {
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
public interface IAudioSessionManager2Z {
    int GetAudioSessionControl(ref Guid AudioSessionGuid, int StreamFlags, out IAudioSessionControlZ SessionControl);
    int GetSimpleAudioVolume(ref Guid AudioSessionGuid, int StreamFlags, out IntPtr AudioVolume);
    int GetSessionEnumerator(out IAudioSessionEnumeratorZ SessionEnum);
}

public class AudioUtilZ {
    public static uint[] GetAudioSessionPids() {
        var deviceEnumeratorType = Type.GetTypeFromCLSID(new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E"));
        var enumerator = (IMMDeviceEnumeratorZ)Activator.CreateInstance(deviceEnumeratorType);

        IMMDeviceZ device;
        enumerator.GetDefaultAudioEndpoint(0, 1, out device);

        object sessionManagerObj;
        var iidSessionManager2 = new Guid("77AA99A0-1BD6-484F-8BC7-2C654C9A9B6F");
        device.Activate(ref iidSessionManager2, 23, IntPtr.Zero, out sessionManagerObj);
        var sessionManager = (IAudioSessionManager2Z)sessionManagerObj;

        IAudioSessionEnumeratorZ sessionEnum;
        sessionManager.GetSessionEnumerator(out sessionEnum);

        int count;
        sessionEnum.GetCount(out count);

        var pids = new System.Collections.Generic.List<uint>();
        for (int i = 0; i < count; i++) {
            IAudioSessionControlZ session;
            sessionEnum.GetSession(i, out session);
            var session2 = session as IAudioSessionControl2Z;
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

function Test-ZoomAudio {
    # CptHost.exe is Zoom's media host; it only runs during meetings with audio
    # Also check Zoom.exe itself in case CptHost is absent on some versions
    $zoomProcs = @(
        Get-Process -Name "CptHost" -ErrorAction SilentlyContinue
        Get-Process -Name "Zoom"    -ErrorAction SilentlyContinue
    )
    if (-not $zoomProcs) { return $false }

    $zoomPids = $zoomProcs.Id

    try {
        $audioPids = [AudioUtilZ]::GetAudioSessionPids()
        foreach ($pid in $zoomPids) {
            if ($audioPids -contains [uint]$pid) { return $true }
        }
    } catch {
        # WASAPI unavailable; CptHost.exe presence alone is a strong signal
        Write-Warning "WASAPI unavailable, using CptHost process as fallback: $_"
        if (Get-Process -Name "CptHost" -ErrorAction SilentlyContinue) {
            return $true
        }
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

$active   = $false
$lastSent = [datetime]::MinValue

Write-Host "Watching Zoom audio (server: $ServerUrl, name: $Name)"

while ($true) {
    $now     = [datetime]::UtcNow
    $inMeeting = Test-ZoomAudio

    if ($inMeeting) {
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
