using System.Buffers.Binary;
using System.Text;
using Veil.Agent;

namespace VeilAgent.Tests;

public class FrameChannelCodecTests
{
    private static readonly byte[] Payload = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x01, 0x02];

    private static WindowFrameTile MakeTile(
        string windowId = "hwnd:0003029A",
        int sequence = 7,
        int surfaceWidth = 1280,
        int surfaceHeight = 800,
        double scale = 2,
        bool isKeyFrame = false,
        WindowFrameTileRect? rect = null,
        byte[]? payload = null
    ) => new(
        WindowId: windowId,
        Sequence: sequence,
        SurfaceWidth: surfaceWidth,
        SurfaceHeight: surfaceHeight,
        Scale: scale,
        IsKeyFrame: isKeyFrame,
        Rect: rect ?? new WindowFrameTileRect(16, 32, 64, 48),
        EncodedData: Convert.ToBase64String(payload ?? Payload)
    );

    [Fact]
    public void WritesTheDocumentedHeaderLayout()
    {
        var message = FrameChannelCodec.Encode(MakeTile());
        var windowIdBytes = Encoding.UTF8.GetBytes("hwnd:0003029A");

        Assert.Equal("VFR2", Encoding.ASCII.GetString(message, 0, 4));
        Assert.Equal(FrameChannelCodec.PngFormat, message[4]);
        Assert.Equal(0, message[5]);
        Assert.Equal((ushort)windowIdBytes.Length, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(6, 2)));
        Assert.Equal("hwnd:0003029A", Encoding.UTF8.GetString(message, 8, windowIdBytes.Length));

        var cursor = 8 + windowIdBytes.Length;
        Assert.Equal(7u, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor, 4)));
        Assert.Equal(1280u, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor + 4, 4)));
        Assert.Equal(800u, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor + 8, 4)));
        // Scale travels as an integer thousandth so the format has no float representation ambiguity.
        Assert.Equal(2000u, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor + 12, 4)));
        Assert.Equal((ushort)16, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(cursor + 16, 2)));
        Assert.Equal((ushort)32, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(cursor + 18, 2)));
        Assert.Equal((ushort)64, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(cursor + 20, 2)));
        Assert.Equal((ushort)48, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(cursor + 22, 2)));
        Assert.Equal((uint)Payload.Length, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor + 24, 4)));
    }

    [Fact]
    public void SetsTheKeyFrameFlagOnlyForKeyFrames()
    {
        var keyFrame = FrameChannelCodec.Encode(
            MakeTile(isKeyFrame: true, rect: new WindowFrameTileRect(0, 0, 1280, 800))
        );
        var tile = FrameChannelCodec.Encode(MakeTile());

        Assert.Equal(FrameChannelCodec.KeyFrameFlag, keyFrame[5]);
        Assert.Equal(0, tile[5]);
    }

    [Fact]
    public void CarriesThePayloadAsRawBytesRatherThanBase64()
    {
        var message = FrameChannelCodec.Encode(MakeTile());
        var expectedLength = FrameChannelCodec.HeaderByteCountWithoutWindowId
            + Encoding.UTF8.GetByteCount("hwnd:0003029A")
            + Payload.Length;

        Assert.Equal(expectedLength, message.Length);
        // The whole point of the channel: no 33% base64 inflation on the wire.
        Assert.Equal(Payload, message[^Payload.Length..]);
    }

    [Fact]
    public void CountsWindowIdBytesNotCharacters()
    {
        // A multi-byte window id would misplace every field after the length prefix if this were a
        // character count.
        var windowId = "hwnd:창-0003029A";
        var message = FrameChannelCodec.Encode(MakeTile(windowId: windowId));
        var byteCount = Encoding.UTF8.GetByteCount(windowId);

        Assert.True(byteCount > windowId.Length);
        Assert.Equal((ushort)byteCount, BinaryPrimitives.ReadUInt16BigEndian(message.AsSpan(6, 2)));
        Assert.Equal(windowId, Encoding.UTF8.GetString(message, 8, byteCount));
    }

    [Fact]
    public void RoundsFractionalScaleToThousandths()
    {
        var message = FrameChannelCodec.Encode(MakeTile(scale: 1.25));
        var cursor = 8 + Encoding.UTF8.GetByteCount("hwnd:0003029A");

        Assert.Equal(1250u, BinaryPrimitives.ReadUInt32BigEndian(message.AsSpan(cursor + 12, 4)));
    }

    [Fact]
    public void RejectsATileWithNoPayload()
    {
        Assert.Throws<InvalidOperationException>(() => FrameChannelCodec.Encode(MakeTile(payload: [])));
    }

    [Fact]
    public void RejectsATileWithNoWindowId()
    {
        Assert.Throws<InvalidOperationException>(() => FrameChannelCodec.Encode(MakeTile(windowId: "")));
    }

    [Fact]
    public void RejectsATileThatFallsOutsideTheSurface()
    {
        // Compositing a rectangle that does not fit would either trap or silently corrupt the surface.
        Assert.Throws<InvalidOperationException>(
            () => FrameChannelCodec.Encode(MakeTile(rect: new WindowFrameTileRect(1270, 0, 64, 48)))
        );
        Assert.Throws<InvalidOperationException>(
            () => FrameChannelCodec.Encode(MakeTile(rect: new WindowFrameTileRect(-1, 0, 64, 48)))
        );
        Assert.Throws<InvalidOperationException>(
            () => FrameChannelCodec.Encode(MakeTile(rect: new WindowFrameTileRect(0, 0, 0, 48)))
        );
    }

    [Fact]
    public void RejectsAKeyFrameThatDoesNotCoverTheSurface()
    {
        // The host has nothing to composite onto until a key frame arrives, so a partial key frame would
        // leave undefined pixels with no way to detect it.
        Assert.Throws<InvalidOperationException>(
            () => FrameChannelCodec.Encode(MakeTile(isKeyFrame: true, rect: new WindowFrameTileRect(0, 0, 64, 48)))
        );
    }

    [Fact]
    public void RejectsAnImplausibleSurfaceSize()
    {
        Assert.Throws<InvalidOperationException>(() => FrameChannelCodec.Encode(MakeTile(surfaceWidth: 0)));
        Assert.Throws<InvalidOperationException>(
            () => FrameChannelCodec.Encode(MakeTile(surfaceWidth: FrameChannelCodec.MaximumSurfaceDimension + 1))
        );
    }

    [Fact]
    public void RejectsAWindowIdBeyondTheLengthPrefix()
    {
        var windowId = new string('a', FrameChannelCodec.MaximumWindowIdByteCount + 1);

        Assert.Throws<InvalidOperationException>(() => FrameChannelCodec.Encode(MakeTile(windowId: windowId)));
    }
}

public class FrameChannelRoutingTests
{
    [Theory]
    [InlineData("GET /frames HTTP/1.1", "/frames")]
    [InlineData("GET /frames?token=1 HTTP/1.1", "/frames")]
    [InlineData("GET / HTTP/1.1", "/")]
    [InlineData("GET /control HTTP/1.1", "/control")]
    [InlineData("GET", "/")]
    public void ParsesTheRequestPath(string requestLine, string expected)
    {
        Assert.Equal(expected, WebSocketAgentServer.RequestPath(requestLine));
    }

    [Theory]
    [InlineData("/frames", true)]
    [InlineData("/frames/", true)]
    [InlineData("/FRAMES", true)]
    [InlineData("/", false)]
    [InlineData("/control", false)]
    [InlineData("/frames/extra", false)]
    public void RoutesOnlyTheFrameChannelPath(string path, bool expected)
    {
        // Control connections must never be silently switched to binary frames, so anything that is not
        // exactly the frame path stays on the JSON path.
        Assert.Equal(expected, WebSocketAgentServer.IsFrameChannelPath(path));
    }
}
