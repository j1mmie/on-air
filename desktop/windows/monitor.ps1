# Monitors Discord voice and Zoom audio, updating the on-air indicator.
# Checks Discord first; skips Zoom if Discord is already active.
#
# Detection:
#   Discord: Discord Local RPC (IPC) — subscribes to VOICE_CHANNEL_SELECT
#            events from the running Discord client. Requires a one-time
#            OAuth consent popup the first time the script runs.
#   Zoom:    Windows Audio Session API (WASAPI) — CptHost.exe only has an audio
#            session during an active meeting.
#
# Usage:
#   $env:ONAIR_SERVER_URL = "http://192.168.1.1:5000"
#   $env:ONAIR_NAME = "Ashley"
#   .\monitor.ps1
#
# List network adapters and their router MAC addresses (useful during setup):
#   .\monitor.ps1 -ListNetworks
#
# ── Discord IPC setup ────────────────────────────────────────────────────────
#
# 1. Go to https://discord.com/developers/applications and create an application.
# 2. Under OAuth2, add http://localhost as a redirect URI and save.
# 3. Copy the Client ID (General Information) and Client Secret (OAuth2).
# 4. Store them as user environment variables:
#      [Environment]::SetEnvironmentVariable("ONAIR_DISCORD_CLIENT_ID",     "...", "User")
#      [Environment]::SetEnvironmentVariable("ONAIR_DISCORD_CLIENT_SECRET", "...", "User")
#
# On first run, Discord will show a one-time consent popup — click Authorize.
# The token is saved to %LOCALAPPDATA%\OnAirMonitor\discord_token.json and
# refreshed automatically; you will not be prompted again.
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
#                             -Trigger $trigger -Settings $settings -Force
#
# 4. To suppress the console window: open Task Scheduler, find OnAirMonitor,
#    Properties → General → "Run whether user is logged on or not", enter password.
#
# To start now:  Start-ScheduledTask  -TaskName "OnAirMonitor"
# To stop:       Stop-ScheduledTask   -TaskName "OnAirMonitor"
# To remove:     Unregister-ScheduledTask -TaskName "OnAirMonitor" -Confirm:$false
#
# ── Viewing logs ─────────────────────────────────────────────────────────────
#
# When running via Task Scheduler, output is written to:
#   %LOCALAPPDATA%\OnAirMonitor\monitor.log
#
# To tail it in real time:
#   Get-Content "$env:LOCALAPPDATA\OnAirMonitor\monitor.log" -Wait -Tail 20

param(
    [string]$ServerUrl           = $env:ONAIR_SERVER_URL,
    [string]$Name                = $env:ONAIR_NAME,
    [string]$RouterMac           = $env:ONAIR_ROUTER_MAC,
    [string]$DiscordClientId     = $env:ONAIR_DISCORD_CLIENT_ID,
    [string]$DiscordClientSecret = $env:ONAIR_DISCORD_CLIENT_SECRET,
    [int]   $PollSeconds         = 5,
    [int]   $RenewSeconds        = 60,
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

# ── Discord IPC ──────────────────────────────────────────────────────────────

$discordState         = [hashtable]::Synchronized(@{ InCall = $false })
$tokenPath            = "$env:LOCALAPPDATA\OnAirMonitor\discord_token.json"
$script:discordIpcJob = $null

function Start-DiscordIpcMonitor {
    if (-not $DiscordClientId -or -not $DiscordClientSecret) {
        Log "ONAIR_DISCORD_CLIENT_ID or ONAIR_DISCORD_CLIENT_SECRET not set; Discord detection disabled"
        return
    }

    $rs = [runspacefactory]::CreateRunspace()
    $rs.Open()
    $rs.SessionStateProxy.SetVariable('discordState',  $discordState)
    $rs.SessionStateProxy.SetVariable('clientId',      $DiscordClientId)
    $rs.SessionStateProxy.SetVariable('clientSecret',  $DiscordClientSecret)
    $rs.SessionStateProxy.SetVariable('tokenPath',     $tokenPath)

    $ps = [powershell]::Create()
    $ps.Runspace = $rs
    $null = $ps.AddScript({
        function Write-Frame([IO.Stream]$s, [int]$op, [string]$json) {
            $b = [Text.Encoding]::UTF8.GetBytes($json)
            $f = [byte[]]::new(8 + $b.Length)
            [BitConverter]::GetBytes([int32]$op).CopyTo($f, 0)
            [BitConverter]::GetBytes([int32]$b.Length).CopyTo($f, 4)
            $b.CopyTo($f, 8)
            $s.Write($f, 0, $f.Length)
        }

        function Read-Frame([IO.Stream]$s) {
            $h = [byte[]]::new(8); $n = 0
            while ($n -lt 8) {
                $r = $s.Read($h, $n, 8 - $n)
                if ($r -le 0) { return $null }
                $n += $r
            }
            $len = [BitConverter]::ToInt32($h, 4)
            $b = [byte[]]::new($len); $n = 0
            while ($n -lt $len) {
                $r = $s.Read($b, $n, $len - $n)
                if ($r -le 0) { return $null }
                $n += $r
            }
            [Text.Encoding]::UTF8.GetString($b) | ConvertFrom-Json
        }

        function Send-Cmd([IO.Stream]$s, [string]$cmd, $cmdArgs) {
            $payload = [pscustomobject]@{
                cmd   = $cmd
                args  = $cmdArgs
                nonce = [guid]::NewGuid().ToString()
            } | ConvertTo-Json -Compress -Depth 5
            Write-Frame $s 1 $payload
        }

        function Get-Token([IO.Stream]$pipe) {
            # Try stored token
            if (Test-Path $tokenPath) {
                $t   = Get-Content $tokenPath -Raw | ConvertFrom-Json
                $exp = [datetime]::Parse($t.expires_at, $null,
                           [Globalization.DateTimeStyles]::RoundtripKind)
                if ($exp -gt [datetime]::UtcNow.AddMinutes(5)) { return $t.access_token }
                # Try refresh token
                if ($t.refresh_token) {
                    try {
                        $body = "grant_type=refresh_token" +
                                "&refresh_token=$([uri]::EscapeDataString($t.refresh_token))" +
                                "&client_id=$clientId" +
                                "&client_secret=$([uri]::EscapeDataString($clientSecret))"
                        $r = Invoke-RestMethod 'https://discord.com/api/oauth2/token' `
                                 -Method Post -Body $body `
                                 -ContentType 'application/x-www-form-urlencoded'
                        @{ access_token  = $r.access_token
                           refresh_token = $r.refresh_token
                           expires_at    = [datetime]::UtcNow.AddSeconds($r.expires_in).ToString('o')
                        } | ConvertTo-Json | Set-Content $tokenPath
                        return $r.access_token
                    } catch { }
                }
            }

            # Full auth — Discord shows a one-time consent popup
            Send-Cmd $pipe 'AUTHORIZE' @{ client_id = $clientId; scopes = @('rpc') }
            do { $frame = Read-Frame $pipe } while ($frame -and $frame.cmd -ne 'AUTHORIZE')
            if (-not $frame) { throw 'Pipe closed during AUTHORIZE' }

            $code = $frame.data.code
            $body = "grant_type=authorization_code" +
                    "&code=$([uri]::EscapeDataString($code))" +
                    "&redirect_uri=http%3A%2F%2Flocalhost" +
                    "&client_id=$clientId" +
                    "&client_secret=$([uri]::EscapeDataString($clientSecret))"
            $r = Invoke-RestMethod 'https://discord.com/api/oauth2/token' `
                     -Method Post -Body $body `
                     -ContentType 'application/x-www-form-urlencoded'
            @{ access_token  = $r.access_token
               refresh_token = $r.refresh_token
               expires_at    = [datetime]::UtcNow.AddSeconds($r.expires_in).ToString('o')
            } | ConvertTo-Json | Set-Content $tokenPath
            $r.access_token
        }

        while ($true) {
            $pipe = $null
            try {
                $pipe = [IO.Pipes.NamedPipeClientStream]::new('.', 'discord-ipc-0',
                    [IO.Pipes.PipeDirection]::InOut, [IO.Pipes.PipeOptions]::None)
                $pipe.Connect(5000)

                # Handshake (opcode 0)
                Write-Frame $pipe 0 ('{"v":1,"client_id":"' + $clientId + '"}')
                $frame = Read-Frame $pipe
                if ($frame.evt -ne 'READY') { throw "Expected READY, got $($frame.evt)" }

                # Authenticate
                $token = Get-Token $pipe
                Send-Cmd $pipe 'AUTHENTICATE' @{ access_token = $token }
                do { $frame = Read-Frame $pipe } while ($frame -and $frame.cmd -ne 'AUTHENTICATE')
                if ($frame.evt -eq 'ERROR') {
                    # Token rejected; delete it so next attempt does full auth
                    Remove-Item $tokenPath -Force -ErrorAction SilentlyContinue
                    throw "Authentication rejected: $($frame.data.message)"
                }

                # Get initial voice channel state
                Send-Cmd $pipe 'GET_SELECTED_VOICE_CHANNEL' @{}
                do { $frame = Read-Frame $pipe } while ($frame -and $frame.cmd -ne 'GET_SELECTED_VOICE_CHANNEL')
                $discordState.InCall = ($null -ne $frame.data -and $null -ne $frame.data.id)

                # Subscribe to voice channel changes
                Send-Cmd $pipe 'SUBSCRIBE' @{ evt = 'VOICE_CHANNEL_SELECT' }

                # Event loop
                while ($true) {
                    $frame = Read-Frame $pipe
                    if ($null -eq $frame) { break }
                    if ($frame.evt -eq 'VOICE_CHANNEL_SELECT') {
                        $discordState.InCall = ($null -ne $frame.data.channel_id)
                    }
                }
            } catch { }
            finally {
                $discordState.InCall = $false
                if ($null -ne $pipe) { try { $pipe.Dispose() } catch { } }
            }
            Start-Sleep -Seconds 5
        }
    })
    $script:discordIpcJob = $ps
    $null = $ps.BeginInvoke()
}

# ── App detection ────────────────────────────────────────────────────────────

function Test-DiscordActive { $discordState.InCall }

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

$logDir = "$HOME\AppData\Local\OnAirMonitor"
if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir | Out-Null }
Start-Transcript -Path "$logDir\monitor.log" -Append

# ── Main loop ────────────────────────────────────────────────────────────────

$active            = $false
$lastSent          = [datetime]::MinValue
$networkApplicable = $null   # $null = unknown; $true or $false once determined
$detectedApp       = $null   # last app logged as detected

$routerDisplay = if ($RouterMac) { $RouterMac } else { 'any' }
Write-Host "Monitoring Discord and Zoom (server: $ServerUrl, name: $Name, router: $routerDisplay)"

Start-DiscordIpcMonitor

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
} } finally {
    if ($script:discordIpcJob) { $script:discordIpcJob.Dispose() }
    Log "Shutting down"
    Stop-Transcript
}
