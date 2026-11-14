using System.Runtime.InteropServices;

namespace Veil.Agent;

/// <summary>
/// Reads the composed desktop through DXGI Desktop Duplication and copies window regions out of it.
/// </summary>
/// <remarks>
/// Copying the screen with GDI, or asking the app to draw itself with PrintWindow, cost about 30 ms a frame
/// in the guest whatever the window, which held mirrored windows near 20 frames a second. Desktop
/// Duplication hands over the desktop image DWM already composed, and only when it changed, so an unchanged
/// desktop costs nothing and a changed one one copy:
/// <see href="https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/desktop-dup-api"/>.
///
/// Like a GDI screen copy, the image shows whatever is on top, so callers use it only for a window that is
/// fully visible. It covers the first output of the first adapter that has one, which is the only display
/// a Veil guest has. Anything unexpected (no output, a rotated or non-BGRA desktop, the secure desktop
/// taking over, a mode change) makes it report <see cref="CopyResult.Unavailable"/>, and the caller falls
/// back to the GDI paths; a failed start is retried after a pause rather than on every frame.
///
/// The COM calls go through vtable slots, numbered as in the Windows SDK's <c>dxgi.h</c>,
/// <c>dxgi1_2.h</c>, and <c>d3d11.h</c>, so the agent needs no graphics package.
/// </remarks>
internal sealed unsafe class DesktopDuplicationCapture
{
    public static DesktopDuplicationCapture Shared { get; } = new();

    public enum CopyResult
    {
        Unavailable,
        /// <summary>The desktop has not changed since the caller's version.</summary>
        Unchanged,
        Copied
    }

    private static readonly TimeSpan RestartPause = TimeSpan.FromSeconds(2);
    private const uint FirstFrameTimeoutMilliseconds = 100;
    private readonly object gate = new();
    private nint device;
    private nint context;
    private nint duplication;
    private nint staging;
    private bool imageInSystemMemory;
    private WindowRect desktop = new(0, 0, 0, 0);
    private byte[] desktopPixels = [];
    private long version;
    private bool hasPendingCopy;
    private long lastPresentTime;
    private FrameChanges? pendingChanges;
    private DateTime nextStartAttempt = DateTime.MinValue;

    /// <summary>
    /// Copies <paramref name="region"/> (screen pixels) into <paramref name="destination"/> as tightly packed
    /// BGRA rows, unless the desktop is unchanged since <paramref name="knownVersion"/>, which is updated.
    /// </summary>
    public CopyResult TryCopy(WindowRect region, byte[] destination, ref long knownVersion)
    {
        if (!OperatingSystem.IsWindows())
        {
            return CopyResult.Unavailable;
        }

        // Never wait for another capture: if a DXGI call ever stalls, the other windows fall back to GDI
        // instead of piling thread-pool threads up behind it and starving the agent's message handling.
        if (!Monitor.TryEnter(gate))
        {
            return CopyResult.Unavailable;
        }

        try
        {
            // The first frame after starting carries the whole desktop, but may not be ready at once; without
            // it a desktop that then stays still never yields an image, and every capture fell back to GDI.
            if (!EnsureStarted() || !Refresh(version == 0 ? FirstFrameTimeoutMilliseconds : 0) || version == 0)
            {
                return CopyResult.Unavailable;
            }

            var left = region.X - desktop.X;
            var top = region.Y - desktop.Y;
            if (left < 0 || top < 0
                || left + region.Width > desktop.Width
                || top + region.Height > desktop.Height
                || destination.Length < region.Width * region.Height * 4)
            {
                return CopyResult.Unavailable;
            }

            if (knownVersion == version)
            {
                return CopyResult.Unchanged;
            }

            var cropTimer = System.Diagnostics.Stopwatch.StartNew();
            var rowBytes = region.Width * 4;
            var desktopRowBytes = desktop.Width * 4;
            for (var row = 0; row < region.Height; row++)
            {
                Buffer.BlockCopy(
                    desktopPixels,
                    (top + row) * desktopRowBytes + left * 4,
                    destination,
                    row * rowBytes,
                    rowBytes
                );
            }

            FrameCaptureDiagnostics.Shared.Record("duplicationCrop", cropTimer.Elapsed.TotalMilliseconds);
            knownVersion = version;
            return CopyResult.Copied;
        }
        finally
        {
            Monitor.Exit(gate);
        }
    }

    /// <summary>Takes the newest desktop image, if DWM presented one since the last call.</summary>
    private bool Refresh(uint timeoutMilliseconds)
    {
        // A copy issued on an earlier call may have finished by now.
        if (hasPendingCopy && !ResolvePendingCopy(wait: false))
        {
            return false;
        }

        FrameInfo info;
        nint resource;
        var result = Call(duplication, DuplicationAcquireNextFrame, timeoutMilliseconds, (nint)(&info), (nint)(&resource));
        if (result == DXGI_ERROR_WAIT_TIMEOUT)
        {
            return true;
        }
        if (result < 0)
        {
            // Access lost: the secure desktop, a mode change, or a full-screen app took the output.
            Stop();
            return Fail("AcquireNextFrame", result);
        }

        try
        {
            // A frame with no present only moved the pointer; the desktop image is the same.
            if (info.LastPresentTime == 0 && version != 0)
            {
                return true;
            }
            if (lastPresentTime != 0 && info.LastPresentTime > lastPresentTime)
            {
                // QueryPerformanceCounter ticks between presents, as milliseconds.
                FrameCaptureDiagnostics.Shared.Record(
                    "dwmPresentInterval",
                    (info.LastPresentTime - lastPresentTime) * 1000.0 / System.Diagnostics.Stopwatch.Frequency);
            }
            if (info.LastPresentTime != 0)
            {
                lastPresentTime = info.LastPresentTime;
            }

            var readTimer = System.Diagnostics.Stopwatch.StartNew();
            // Copying the whole desktop took 16 ms a frame at Mac-screen resolutions; DWM reports which
            // parts moved and which changed, so only those are copied once there is an image to update.
            // The changes are relative to the previous frame, so that one has to be in the image first.
            if (hasPendingCopy && !ResolvePendingCopy(wait: true))
            {
                return false;
            }
            var changes = version == 0 ? null : ReadFrameChanges(info.TotalMetadataBufferSize);
            var usesStaging = staging != 0;
            var read = usesStaging ? ReadThroughStaging(resource, changes) : ReadMappedDesktop(changes);
            FrameCaptureDiagnostics.Shared.Record(
                usesStaging ? "duplicationReadStaging" : "duplicationReadMapped",
                readTimer.Elapsed.TotalMilliseconds);
            return read;
        }
        finally
        {
            Release(resource);
            Call(duplication, DuplicationReleaseFrame);
        }
    }

    private bool ReadMappedDesktop(FrameChanges? changes)
    {
        MappedRect mapped;
        var mapTimer = System.Diagnostics.Stopwatch.StartNew();
        var mapResult = Call(duplication, DuplicationMapDesktopSurface, (nint)(&mapped));
        FrameCaptureDiagnostics.Shared.Record("duplicationMap", mapTimer.Elapsed.TotalMilliseconds);
        if (mapResult < 0)
        {
            Stop();
            return Fail("MapDesktopSurface", mapResult);
        }

        try
        {
            var copyTimer = System.Diagnostics.Stopwatch.StartNew();
            CopyChanges((byte*)mapped.Bits, mapped.Pitch, changes);
            FrameCaptureDiagnostics.Shared.Record("duplicationCopy", copyTimer.Elapsed.TotalMilliseconds);
            return true;
        }
        finally
        {
            Call(duplication, DuplicationUnMapDesktopSurface);
        }
    }

    private bool ReadThroughStaging(nint resource, FrameChanges? changes)
    {
        nint texture;
        var textureId = IID_ID3D11Texture2D;
        if (Call(resource, QueryInterfaceSlot, (nint)(&textureId), (nint)(&texture)) is var queryResult and < 0)
        {
            if (imageInSystemMemory)
            {
                // No texture behind this frame; read the mapped surface from now on.
                Release(staging);
                staging = 0;
                Fail("QueryInterface(ID3D11Texture2D); using MapDesktopSurface", queryResult);
                return ReadMappedDesktop(changes);
            }
            Stop();
            return Fail("QueryInterface(ID3D11Texture2D)", queryResult);
        }

        try
        {
            var copyTimer = System.Diagnostics.Stopwatch.StartNew();
            if (changes is null)
            {
                CallVoid(context, ContextCopyResource, staging, texture);
            }
            else
            {
                // Only what changed; moved areas are shifted in the kept image instead.
                foreach (var rect in changes.Dirty)
                {
                    if (Clamp(rect) is not { } area)
                    {
                        continue;
                    }
                    var box = new Box
                    {
                        Left = (uint)area.Left,
                        Top = (uint)area.Top,
                        Front = 0,
                        Right = (uint)(area.Left + area.Width),
                        Bottom = (uint)(area.Top + area.Height),
                        Back = 1
                    };
                    CopySubresourceRegion(staging, (uint)area.Left, (uint)area.Top, texture, (nint)(&box));
                }
            }
            FrameCaptureDiagnostics.Shared.Record("duplicationStagingCopy", copyTimer.Elapsed.TotalMilliseconds);
            hasPendingCopy = true;
            pendingChanges = changes;
        }
        finally
        {
            Release(texture);
        }

        return ResolvePendingCopy(wait: false);
    }

    /// <summary>
    /// Reads the copied rectangles out of the staging texture into the kept image.
    /// </summary>
    /// <remarks>
    /// Mapping right after the copy waited about 14 ms a frame for the guest's software renderer to finish
    /// it. Without <paramref name="wait"/> the map returns at once while the copy is still running, and the
    /// image is updated on a later call instead, one sampling interval later at most.
    /// </remarks>
    private bool ResolvePendingCopy(bool wait)
    {
        MappedSubresource mapped;
        var mapTimer = System.Diagnostics.Stopwatch.StartNew();
        var result = Call(context, ContextMap, staging, 0u, D3D11_MAP_READ, wait ? 0u : D3D11_MAP_FLAG_DO_NOT_WAIT, (nint)(&mapped));
        FrameCaptureDiagnostics.Shared.Record(wait ? "duplicationStagingMapWait" : "duplicationStagingMap", mapTimer.Elapsed.TotalMilliseconds);
        if (result == DXGI_ERROR_WAS_STILL_DRAWING)
        {
            return true;
        }
        if (result < 0)
        {
            Stop();
            return Fail("Map(staging)", result);
        }

        try
        {
            CopyChanges((byte*)mapped.Data, (int)mapped.RowPitch, pendingChanges);
            hasPendingCopy = false;
            pendingChanges = null;
            return true;
        }
        finally
        {
            CallVoid(context, ContextUnmap, staging, 0u);
        }
    }

    /// <summary>Rectangles DWM reports for the acquired frame, in desktop pixels.</summary>
    private sealed record FrameChanges(MoveRect[] Moves, NativeRect[] Dirty);

    /// <summary>
    /// The frame's move and dirty rectangles, or null when they cannot be read and the whole image must
    /// be copied instead.
    /// </summary>
    private FrameChanges? ReadFrameChanges(uint metadataSize)
    {
        if (metadataSize == 0)
        {
            return new FrameChanges([], []);
        }

        var moves = new MoveRect[metadataSize / (uint)sizeof(MoveRect) + 1];
        var dirty = new NativeRect[metadataSize / (uint)sizeof(NativeRect) + 1];
        uint moveBytes, dirtyBytes;
        fixed (MoveRect* moveBuffer = moves)
        fixed (NativeRect* dirtyBuffer = dirty)
        {
            if (Call(duplication, DuplicationGetFrameMoveRects,
                    (uint)(moves.Length * sizeof(MoveRect)), (nint)moveBuffer, (nint)(&moveBytes)) < 0
                || Call(duplication, DuplicationGetFrameDirtyRects,
                    (uint)(dirty.Length * sizeof(NativeRect)), (nint)dirtyBuffer, (nint)(&dirtyBytes)) < 0)
            {
                return null;
            }
        }

        var changes = new FrameChanges(
            moves[..(int)(moveBytes / (uint)sizeof(MoveRect))],
            dirty[..(int)(dirtyBytes / (uint)sizeof(NativeRect))]
        );
        // Kilopixels changed, reported like a time so it shows in the same table.
        FrameCaptureDiagnostics.Shared.Record(
            "duplicationDirtyKilopixels",
            changes.Dirty.Sum(rect => (double)Math.Max(0, rect.Right - rect.Left) * Math.Max(0, rect.Bottom - rect.Top)) / 1000);
        return changes;
    }

    /// <summary>
    /// Updates the kept desktop image: moved areas first, from the image as it was, then changed areas
    /// from the new frame, the order the Desktop Duplication sample applies them in. Without
    /// <paramref name="changes"/> the whole frame is copied.
    /// </summary>
    private void CopyChanges(byte* source, int pitch, FrameChanges? changes)
    {
        var rowBytes = desktop.Width * 4;
        fixed (byte* destination = desktopPixels)
        {
            if (changes is null)
            {
                for (var row = 0; row < desktop.Height; row++)
                {
                    Buffer.MemoryCopy(source + (long)row * pitch, destination + (long)row * rowBytes, rowBytes, rowBytes);
                }
            }
            else
            {
                foreach (var move in changes.Moves)
                {
                    ApplyMove(destination, rowBytes, move);
                }
                foreach (var rect in changes.Dirty)
                {
                    if (Clamp(rect) is not { } area)
                    {
                        continue;
                    }
                    var (left, top, width, height) = area;
                    var bytes = width * 4;
                    for (var row = top; row < top + height; row++)
                    {
                        Buffer.MemoryCopy(
                            source + (long)row * pitch + left * 4,
                            destination + (long)row * rowBytes + left * 4,
                            bytes,
                            bytes);
                    }
                }
            }
        }
        version += 1;
    }

    private void ApplyMove(byte* image, int rowBytes, MoveRect move)
    {
        if (Clamp(move.Destination) is not { } area)
        {
            return;
        }
        var (left, top, width, height) = area;
        var sourceLeft = move.SourceX;
        var sourceTop = move.SourceY;
        if (sourceLeft < 0 || sourceTop < 0
            || sourceLeft + width > desktop.Width || sourceTop + height > desktop.Height)
        {
            return;
        }

        // Source and destination can overlap, so the moved block goes through a copy first.
        var bytes = width * 4;
        var block = new byte[bytes * height];
        fixed (byte* blockBuffer = block)
        {
            for (var row = 0; row < height; row++)
            {
                Buffer.MemoryCopy(image + (long)(sourceTop + row) * rowBytes + sourceLeft * 4,
                    blockBuffer + (long)row * bytes, bytes, bytes);
            }
            for (var row = 0; row < height; row++)
            {
                Buffer.MemoryCopy(blockBuffer + (long)row * bytes,
                    image + (long)(top + row) * rowBytes + left * 4, bytes, bytes);
            }
        }
    }

    private (int Left, int Top, int Width, int Height)? Clamp(NativeRect rect)
    {
        var left = Math.Max(0, rect.Left);
        var top = Math.Max(0, rect.Top);
        var right = Math.Min(desktop.Width, rect.Right);
        var bottom = Math.Min(desktop.Height, rect.Bottom);
        return right > left && bottom > top ? (left, top, right - left, bottom - top) : null;
    }

    private bool EnsureStarted()
    {
        if (duplication != 0)
        {
            return true;
        }
        if (DateTime.UtcNow < nextStartAttempt)
        {
            return false;
        }

        try
        {
            if (Start())
            {
                return true;
            }
        }
        catch (Exception error) when (error is DllNotFoundException or EntryPointNotFoundException)
        {
            Fail(error.GetType().Name);
        }

        Stop();
        nextStartAttempt = DateTime.UtcNow + RestartPause;
        return false;
    }

    private bool Start()
    {
        nint factory = 0, adapter = 0, output = 0, output1 = 0;
        try
        {
            var factoryId = IID_IDXGIFactory1;
            if (CreateDXGIFactory1(&factoryId, &factory) is var factoryResult and < 0)
            {
                return Fail("CreateDXGIFactory1", factoryResult);
            }

            for (uint index = 0; ; index++)
            {
                if (Call(factory, FactoryEnumAdapters, index, (nint)(&adapter)) is var adapterResult and < 0)
                {
                    return Fail("EnumAdapters (no adapter with an output)", adapterResult);
                }
                if (Call(adapter, AdapterEnumOutputs, 0u, (nint)(&output)) >= 0)
                {
                    break;
                }
                Release(adapter);
                adapter = 0;
            }

            OutputDesc outputDesc;
            if (Call(output, OutputGetDesc, (nint)(&outputDesc)) < 0
                || outputDesc.Rotation is not (DXGI_MODE_ROTATION_UNSPECIFIED or DXGI_MODE_ROTATION_IDENTITY))
            {
                return Fail("Output GetDesc or rotation");
            }

            nint createdDevice, createdContext;
            int featureLevel;
            if (D3D11CreateDevice(adapter, D3D_DRIVER_TYPE_UNKNOWN, 0, 0, null, 0, D3D11_SDK_VERSION,
                    &createdDevice, &featureLevel, &createdContext) is var deviceResult and < 0)
            {
                return Fail("D3D11CreateDevice", deviceResult);
            }
            device = createdDevice;
            context = createdContext;

            var output1Id = IID_IDXGIOutput1;
            nint createdDuplication;
            if (Call(output, QueryInterfaceSlot, (nint)(&output1Id), (nint)(&output1)) is var output1Result and < 0)
            {
                return Fail("QueryInterface(IDXGIOutput1)", output1Result);
            }
            if (Call(output1, Output1DuplicateOutput, device, (nint)(&createdDuplication)) is var duplicateResult and < 0)
            {
                return Fail("DuplicateOutput", duplicateResult);
            }
            duplication = createdDuplication;

            DuplicationDesc duplicationDesc;
            CallVoid(duplication, DuplicationGetDesc, (nint)(&duplicationDesc));
            var width = (int)duplicationDesc.Width;
            var height = (int)duplicationDesc.Height;
            if (width <= 0 || height <= 0 || duplicationDesc.Format != DXGI_FORMAT_B8G8R8A8_UNORM)
            {
                return Fail($"Unsupported desktop {width}x{height} format {duplicationDesc.Format}");
            }

            imageInSystemMemory = duplicationDesc.DesktopImageInSystemMemory != 0;
            FrameCaptureDiagnostics.Shared.RecordDuplicationMode(
                $"{width}x{height} @ {duplicationDesc.RefreshNumerator}/{duplicationDesc.RefreshDenominator} Hz, " +
                $"system memory {imageInSystemMemory}");
            // Created even for a desktop image in system memory: MapDesktopSurface copies the whole desktop
            // out on every call (13 ms a frame on a Veil guest), while the staging texture takes just the
            // changed rectangles.
            {
                var textureDesc = new Texture2DDesc
                {
                    Width = (uint)width,
                    Height = (uint)height,
                    MipLevels = 1,
                    ArraySize = 1,
                    Format = DXGI_FORMAT_B8G8R8A8_UNORM,
                    SampleCount = 1,
                    Usage = D3D11_USAGE_STAGING,
                    CpuAccessFlags = D3D11_CPU_ACCESS_READ
                };
                nint createdStaging;
                if (Call(device, DeviceCreateTexture2D, (nint)(&textureDesc), (nint)0, (nint)(&createdStaging)) is var textureResult and < 0)
                {
                    if (!imageInSystemMemory)
                    {
                        return Fail("CreateTexture2D(staging)", textureResult);
                    }
                    createdStaging = 0;
                }
                staging = createdStaging;
            }

            desktop = new WindowRect(outputDesc.Left, outputDesc.Top, width, height);
            desktopPixels = new byte[width * height * 4];
            version = 0;
            return true;
        }
        finally
        {
            Release(output1);
            Release(output);
            Release(adapter);
            Release(factory);
        }
    }

    private static bool Fail(string stage, int result = 0)
    {
        FrameCaptureDiagnostics.Shared.RecordDuplicationFailure(
            result == 0 ? stage : $"{stage} 0x{result:X8}");
        return false;
    }

    private void Stop()
    {
        Release(staging);
        Release(duplication);
        Release(context);
        Release(device);
        staging = duplication = context = device = 0;
        version = 0;
        hasPendingCopy = false;
        pendingChanges = null;
    }

    private static void Release(nint unknown)
    {
        if (unknown != 0)
        {
            ((delegate* unmanaged[Stdcall]<nint, uint>)Slot(unknown, ReleaseSlot))(unknown);
        }
    }

    private static void* Slot(nint unknown, int index) => (*(void***)unknown)[index];

    // Function pointers whose signatures use generic type parameters are rejected at run time
    // (BadImageFormatException), so each COM signature in use has its own helper.
    private static int Call(nint self, int slot) =>
        ((delegate* unmanaged[Stdcall]<nint, int>)Slot(self, slot))(self);

    private static int Call(nint self, int slot, nint a) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, int>)Slot(self, slot))(self, a);

    private static int Call(nint self, int slot, uint a, nint b) =>
        ((delegate* unmanaged[Stdcall]<nint, uint, nint, int>)Slot(self, slot))(self, a, b);

    private static int Call(nint self, int slot, nint a, nint b) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, nint, int>)Slot(self, slot))(self, a, b);

    private static int Call(nint self, int slot, uint a, nint b, nint c) =>
        ((delegate* unmanaged[Stdcall]<nint, uint, nint, nint, int>)Slot(self, slot))(self, a, b, c);

    private static int Call(nint self, int slot, nint a, nint b, nint c) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, nint, nint, int>)Slot(self, slot))(self, a, b, c);

    private static int Call(nint self, int slot, nint a, uint b, uint c, uint d, nint e) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, uint, uint, uint, nint, int>)Slot(self, slot))(self, a, b, c, d, e);

    private static void CallVoid(nint self, int slot, nint a) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, void>)Slot(self, slot))(self, a);

    private static void CallVoid(nint self, int slot, nint a, nint b) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, nint, void>)Slot(self, slot))(self, a, b);

    private void CopySubresourceRegion(nint destination, uint x, uint y, nint source, nint box) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, uint, uint, uint, uint, nint, uint, nint, void>)
            Slot(context, ContextCopySubresourceRegion))(context, destination, 0, x, y, 0, source, 0, box);

    private static void CallVoid(nint self, int slot, nint a, uint b) =>
        ((delegate* unmanaged[Stdcall]<nint, nint, uint, void>)Slot(self, slot))(self, a, b);

    // IUnknown
    private const int QueryInterfaceSlot = 0;
    private const int ReleaseSlot = 2;
    // IDXGIFactory: IDXGIObject ends at slot 6.
    private const int FactoryEnumAdapters = 7;
    // IDXGIAdapter
    private const int AdapterEnumOutputs = 7;
    // IDXGIOutput / IDXGIOutput1
    private const int OutputGetDesc = 7;
    private const int Output1DuplicateOutput = 22;
    // IDXGIOutputDuplication
    private const int DuplicationGetDesc = 7;
    private const int DuplicationAcquireNextFrame = 8;
    private const int DuplicationGetFrameDirtyRects = 9;
    private const int DuplicationGetFrameMoveRects = 10;
    private const int DuplicationMapDesktopSurface = 12;
    private const int DuplicationUnMapDesktopSurface = 13;
    private const int DuplicationReleaseFrame = 14;
    // ID3D11Device
    private const int DeviceCreateTexture2D = 5;
    // ID3D11DeviceContext: ID3D11DeviceChild ends at slot 6.
    private const int ContextMap = 14;
    private const int ContextUnmap = 15;
    private const int ContextCopySubresourceRegion = 46;
    private const int ContextCopyResource = 47;

    private const int DXGI_ERROR_WAIT_TIMEOUT = unchecked((int)0x887A0027);
    private const uint DXGI_FORMAT_B8G8R8A8_UNORM = 87;
    private const uint DXGI_MODE_ROTATION_UNSPECIFIED = 0;
    private const uint DXGI_MODE_ROTATION_IDENTITY = 1;
    private const int D3D_DRIVER_TYPE_UNKNOWN = 0;
    private const uint D3D11_SDK_VERSION = 7;
    private const uint D3D11_USAGE_STAGING = 3;
    private const uint D3D11_CPU_ACCESS_READ = 0x20000;
    private const uint D3D11_MAP_READ = 1;
    private const uint D3D11_MAP_FLAG_DO_NOT_WAIT = 0x100000;
    private const int DXGI_ERROR_WAS_STILL_DRAWING = unchecked((int)0x887A000A);

    private static readonly Guid IID_IDXGIFactory1 = new("770aae78-f26f-4dba-a829-253c83d1b387");
    private static readonly Guid IID_IDXGIOutput1 = new("00cddea8-939b-4b83-a340-a685226666cc");
    private static readonly Guid IID_ID3D11Texture2D = new("6f15aaf2-d208-4e89-9ab4-489535d34f9c");

    [StructLayout(LayoutKind.Sequential)]
    private struct FrameInfo
    {
        public long LastPresentTime;
        public long LastMouseUpdateTime;
        public uint AccumulatedFrames;
        public int RectsCoalesced;
        public int ProtectedContentMaskedOut;
        public int PointerX;
        public int PointerY;
        public int PointerVisible;
        public uint TotalMetadataBufferSize;
        public uint PointerShapeBufferSize;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct DuplicationDesc
    {
        // DXGI_MODE_DESC
        public uint Width;
        public uint Height;
        public uint RefreshNumerator;
        public uint RefreshDenominator;
        public uint Format;
        public uint ScanlineOrdering;
        public uint Scaling;
        public uint Rotation;
        public int DesktopImageInSystemMemory;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct OutputDesc
    {
        public fixed char DeviceName[32];
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
        public int AttachedToDesktop;
        public uint Rotation;
        public nint Monitor;
    }

    /// <summary>D3D11_BOX.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct Box
    {
        public uint Left;
        public uint Top;
        public uint Front;
        public uint Right;
        public uint Bottom;
        public uint Back;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct NativeRect
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    /// <summary>DXGI_OUTDUPL_MOVE_RECT.</summary>
    [StructLayout(LayoutKind.Sequential)]
    private struct MoveRect
    {
        public int SourceX;
        public int SourceY;
        public NativeRect Destination;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MappedRect
    {
        public int Pitch;
        public nint Bits;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct MappedSubresource
    {
        public nint Data;
        public uint RowPitch;
        public uint DepthPitch;
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct Texture2DDesc
    {
        public uint Width;
        public uint Height;
        public uint MipLevels;
        public uint ArraySize;
        public uint Format;
        public uint SampleCount;
        public uint SampleQuality;
        public uint Usage;
        public uint BindFlags;
        public uint CpuAccessFlags;
        public uint MiscFlags;
    }

    [DllImport("dxgi.dll")]
    private static extern int CreateDXGIFactory1(Guid* riid, nint* factory);

    [DllImport("d3d11.dll")]
    private static extern int D3D11CreateDevice(
        nint adapter,
        int driverType,
        nint software,
        uint flags,
        int* featureLevels,
        uint featureLevelCount,
        uint sdkVersion,
        nint* device,
        int* featureLevel,
        nint* immediateContext);
}
