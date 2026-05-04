# Monitors Discord voice and Zoom audio, updating the on-air indicator.
# Checks Discord first; skips Zoom if Discord is already active.
#
# Detection uses the Windows Audio Session API (WASAPI) to find which process
# PIDs have active audio sessions, matched against Discord/Zoom process IDs.
#
# Usage:
#   $env:ONAIR_SERVER_URL = "http://192.168.1.1:5000"
#   $env:ONAIR_NAME = "Ashley"
#   .\monitor.ps1
#
# List network adapters and their router MAC addresses (useful during setup):
#   .\monitor.ps1 -ListNetworks
#
# ── Startup (Task Scheduler) ─────────────────────────────────────────────────
#
# 1. Allow the script to run (once, in an elevated PowerShell):
#      Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
#
# 2. Store your settings as user environment variables (survives reboots):
#      [Environment]::SetEnvironmentVariable("ONAIR_SERVER_URL",   "http://192.168.1.1:5000", "User")
#      [Environment]::SetEnvironmentVariable("ONAIR_NAME",         "Ashley",                  "User")
#      [Environment]::SetEnvironmentVariable("ONAIR_ROUTER_MAC",   "a4:3e:51:00:00:00",       "User")
#
# 3. Register the scheduled task (runs at login, stays running):
#      $script  = "$HOME\path\to\on-air\desktop\windows\monitor.ps1"
#      $action  = New-ScheduledTaskAction -Execute "powershell.exe" `
#                   -Argument "-NonInteractive -WindowStyle Hidden -File `"$script`""
#      $trigger = New-ScheduledTaskTrigger -AtLogOn
#      $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit 0 -RestartCount 3 `
#                    -RestartInterval (New-TimeSpan -Minutes 1)
#      Register-ScheduledTask -TaskName "OnAirMonitor" -Action $action `
#                             -Trigger $trigger -Settings $settings
#
# To start now:  Start-ScheduledTask  -TaskName "OnAirMonitor"
# To stop:       Stop-ScheduledTask   -TaskName "OnAirMonitor"
# To remove:     Unregister-ScheduledTask -TaskName "OnAirMonitor" -Confirm:$false

param(
    [string]$ServerUrl    = $env:ONAIR_SERVER_URL,
    [string]$Name         = $env:ONAIR_NAME,
    [string]$RouterMac    = $env:ONAIR_ROUTER_MAC,
    [int]   $PollSeconds  = 5,
    [int]   $RenewSeconds = 60,
    [switch]$ListNetworks
)

if (-not $ServerUrl) { $ServerUrl = "http://192.168.1.1:5000" }
if (-not $Name)      { $Name      = "desktop" }

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

# ── Network check ───────────────────────────────────────────────────────────

function Get-RouterMacs {
    $ifIndices = (Get-NetAdapter |
        Where-Object { $_.MediaType -in '802.3', 'Native 802.11' -and $_.Status -eq 'Up' }).ifIndex
    $gateways = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ErrorAction SilentlyContinue |
        Where-Object { $_.ifIndex -in $ifIndices }).NextHop | Select-Object -Unique
    foreach ($gateway in $gateways) {
        $entry = arp -a $gateway | Where-Object { $_ -match [regex]::Escape($gateway) }
        if ($entry -match '(([0-9a-f]{2}-){5}[0-9a-f]{2})') {
            ($Matches[1] -replace '-', ':').ToLower()
        }
    }
}

function Show-Networks {
    $adapters = Get-NetAdapter |
        Where-Object { $_.MediaType -in '802.3', 'Native 802.11' -and $_.Status -eq 'Up' }
    $found = $false
    foreach ($adapter in $adapters) {
        $gateway = (Get-NetRoute -DestinationPrefix '0.0.0.0/0' -ifIndex $adapter.ifIndex `
            -ErrorAction SilentlyContinue).NextHop
        if (-not $gateway) { continue }
        $entry = arp -a $gateway | Where-Object { $_ -match [regex]::Escape($gateway) }
        if ($entry -match '(([0-9a-f]{2}-){5}[0-9a-f]{2})') {
            $mac = ($Matches[1] -replace '-', ':').ToLower()
            Write-Host ("  {0,-20}  gateway: {1,-16}  router mac: {2}" -f $adapter.Name, $gateway, $mac)
            $found = $true
        }
    }
    if (-not $found) { Write-Host "  (no active network adapters found)" }
}

# Returns the matched router MAC if on an applicable network, $null otherwise.
# Returns $null immediately when RouterMac is unset — no filter is configured.
function Get-ApplicableRouterMac {
    if (-not $RouterMac) { return $null }

    $currentMacs = @(Get-RouterMacs)
    foreach ($entry in ($RouterMac -split ',' | ForEach-Object { $_.Trim() })) {
        if ($entry -eq 'lan') {
            if ($currentMacs.Count -gt 0) { return $currentMacs[0] }
        } elseif ($currentMacs -contains $entry) {
            return $entry
        }
    }
    return $null
}

function Test-OnRequiredNetwork {
    if (-not $RouterMac) { return $true }
    return ($null -ne (Get-ApplicableRouterMac))
}

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

function Send-Notification([string]$State) {
    try {
        $null = Invoke-WebRequest -Uri "${ServerUrl}/${State}?name=${Name}" `
            -Method Get -UseBasicParsing -TimeoutSec 5
    } catch {
        Write-Warning "Request failed: $_"
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

function Test-AnyActive {
    # Short-circuits: Zoom is not checked if Discord is already active
    Test-DiscordActive -or Test-ZoomActive
}

function Get-ActiveApp {
    if (Test-DiscordActive) { return "Discord" }
    if (Test-ZoomActive)    { return "Zoom" }
    return $null
}

# ── Helpers ─────────────────────────────────────────────────────────────────

function Log([string]$Message) { Write-Host "$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss') $Message" }

# ── List networks mode ───────────────────────────────────────────────────────

if ($ListNetworks) {
    Write-Host "Active network adapters and router MAC addresses:"
    Show-Networks
    exit
}

# ── Main loop ────────────────────────────────────────────────────────────────

$active            = $false
$lastSent          = [datetime]::MinValue
$networkApplicable = $null   # $null = unknown; $true or $false once determined
$detectedApp       = $null   # last app logged as detected

$routerDisplay = if ($RouterMac) { $RouterMac } else { 'any' }
Write-Host "Monitoring Discord and Zoom (server: $ServerUrl, name: $Name, router: $routerDisplay)"

try { while ($true) {
    $now = [datetime]::UtcNow

    if ($RouterMac) {
        $matchedMac = Get-ApplicableRouterMac
        if ($null -eq $matchedMac) {
            if ($networkApplicable -ne $false) {
                Log "No applicable network found. No checks will be done until an applicable network is joined"
                $networkApplicable = $false
            }
            if ($active) {
                Send-Notification "off"
                Log "Sending OFF signal to Display (left network)"
                $active = $false
            }
            Start-Sleep -Seconds $PollSeconds
            continue
        } elseif ($networkApplicable -ne $true) {
            Log "Discovered applicable network with router mac address $matchedMac"
            $networkApplicable = $true
        }
    }

    $currentApp = Get-ActiveApp
    if ($null -ne $currentApp) {
        if ($currentApp -ne $detectedApp) {
            Log "Detected $currentApp usage"
            $detectedApp = $currentApp
        }
        if (-not $active -or ($now - $lastSent).TotalSeconds -ge $RenewSeconds) {
            Send-Notification "on"
            Log "Sending ON signal to Display"
            $active   = $true
            $lastSent = $now
        }
    } else {
        $detectedApp = $null
        if ($active) {
            Send-Notification "off"
            Log "Sending OFF signal to Display"
            $active = $false
        }
    }

    Start-Sleep -Seconds $PollSeconds
} } finally { Log "Shutting down" }
