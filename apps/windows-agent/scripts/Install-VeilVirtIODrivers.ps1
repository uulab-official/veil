param(
    [string[]]$DriverFolders = @("NetKVM", "viogpudo", "viorng", "Balloon", "vioserial"),
    [switch]$SingleBootDisplay,
    # A display driver installed a moment ago brings its monitor up a few seconds later.
    [int]$DisplayWaitSeconds = 0,
    [string]$LogPath = "$env:windir\Temp\veil-virtio.log"
)

# Installs Windows 11 Arm64 VirtIO drivers from the attached virtio-win media and, on request, keeps
# Windows on one display while QEMU still attaches both ramfb and virtio-gpu.
#
# Callers:
# - The answer file's specialize pass runs this as SYSTEM, before OOBE, with the default folder list.
#   Its RunSynchronous Path holds at most 259 characters, so the list lives here instead.
# - Bootstrap-VeilAgentFromMedia.ps1 runs it at first sign-in with -DriverFolders @() -SingleBootDisplay.
# - Repair-VeilAgentConnectivity.ps1 runs it elevated for VMs installed before viogpudo was added.
#
# It never fails the caller: Windows Setup must not stop on a driver problem, and repair still has
# firewall and agent work to do. pnputil output goes to $LogPath.
# https://learn.microsoft.com/windows-hardware/drivers/devtest/pnputil-command-syntax

$ErrorActionPreference = "Continue"

function Write-VeilVirtIOLog {
    param([string]$Message)

    $Line = "$(Get-Date -Format o) $Message"
    Write-Host $Line
    try {
        Add-Content -LiteralPath $LogPath -Value $Line
    } catch {
    }
}

function Find-VeilVirtIOMediaRoot {
    # Drive letters differ between installs; every virtio-win release labels its volume
    # virtio-win-<version>, the same prefix the host pins in VirtioWinDriverMedia.swift.
    $Drive = [IO.DriveInfo]::GetDrives() |
        Where-Object { $_.IsReady -and $_.VolumeLabel -like "virtio-win*" } |
        Select-Object -First 1
    if ($Drive) {
        return $Drive.RootDirectory.FullName
    }

    return $null
}

function Install-VeilVirtIODriverFolders {
    param([string[]]$Folders)

    if (-not $Folders -or $Folders.Count -eq 0) {
        return
    }

    $MediaRoot = Find-VeilVirtIOMediaRoot
    if (-not $MediaRoot) {
        Write-VeilVirtIOLog "No virtio-win media is attached; skipping $($Folders -join ', ')."
        return
    }

    foreach ($Folder in $Folders) {
        $DriverRoot = Join-Path $MediaRoot "$Folder\w11\ARM64"
        $InfFiles = @(Get-ChildItem -LiteralPath $DriverRoot -Filter "*.inf" -File -ErrorAction SilentlyContinue)
        if ($InfFiles.Count -eq 0) {
            Write-VeilVirtIOLog "No Windows 11 ARM64 INF under $DriverRoot."
            continue
        }

        foreach ($InfFile in $InfFiles) {
            Write-VeilVirtIOLog "pnputil /add-driver $($InfFile.FullName) /install"
            pnputil /add-driver "$($InfFile.FullName)" /install 2>&1 | ForEach-Object { Write-VeilVirtIOLog "$_" }
            Write-VeilVirtIOLog "pnputil exited with $LASTEXITCODE for $Folder."
        }
    }
}

function Select-VeilSingleBootDisplay {
    # With viogpudo installed and ramfb still attached, Windows extends the desktop across both: the
    # ramfb monitor that Veil shows stays primary at 800x600 and a second, unseen virtio-gpu monitor
    # sits beside it, where windows can open out of view. Cloning the two fails (they are on
    # different display adapters), so keep only one. Measured with QEMU 11.1.3 and virtio-win
    # 0.1.302: SDC_TOPOLOGY_EXTERNAL keeps the ramfb monitor, SDC_TOPOLOGY_INTERNAL the virtio-gpu
    # one. Windows remembers the choice for this pair of monitors only, so a later boot on
    # virtio-gpu alone is unaffected.
    # https://learn.microsoft.com/windows/win32/api/winuser/nf-winuser-setdisplayconfig
    if (-not ("VeilDisplayTopology" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public static class VeilDisplayTopology {
    private delegate bool MonitorEnumProc(IntPtr monitor, IntPtr deviceContext, IntPtr rect, IntPtr data);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr deviceContext, IntPtr clip, MonitorEnumProc callback, IntPtr data);

    [DllImport("user32.dll")]
    public static extern int SetDisplayConfig(uint pathCount, IntPtr paths, uint modeCount, IntPtr modes, uint flags);

    // Asked live each time; System.Windows.Forms.Screen caches the list for the life of the process.
    public static int ActiveMonitorCount() {
        int count = 0;
        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (m, d, r, p) => { count++; return true; }, IntPtr.Zero);
        return count;
    }
}
"@
    }

    $Deadline = (Get-Date).AddSeconds($DisplayWaitSeconds)
    $MonitorCount = [VeilDisplayTopology]::ActiveMonitorCount()
    while ($MonitorCount -lt 2 -and (Get-Date) -lt $Deadline) {
        Start-Sleep -Milliseconds 500
        $MonitorCount = [VeilDisplayTopology]::ActiveMonitorCount()
    }

    if ($MonitorCount -lt 2) {
        Write-VeilVirtIOLog "Windows shows $MonitorCount display; nothing to select."
        return
    }

    $SdcApply = 0x80
    $SdcTopologyExternal = 0x8
    $Result = [VeilDisplayTopology]::SetDisplayConfig(0, [IntPtr]::Zero, 0, [IntPtr]::Zero, $SdcApply -bor $SdcTopologyExternal)
    Write-VeilVirtIOLog "Windows shows $MonitorCount displays; SetDisplayConfig(SDC_TOPOLOGY_EXTERNAL) returned $Result."
}

try {
    Install-VeilVirtIODriverFolders -Folders $DriverFolders
    if ($SingleBootDisplay) {
        Select-VeilSingleBootDisplay
    }
} catch {
    Write-VeilVirtIOLog "VirtIO driver step failed: $($_.Exception.Message)"
}

exit 0
