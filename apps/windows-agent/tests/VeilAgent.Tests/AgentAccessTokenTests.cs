using System.Text;

namespace Veil.Agent.Tests;

public sealed class AgentAccessTokenTests
{
    private const string Token = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

    [Fact]
    public void AcceptsEveryConnectionWhenTheMachineCarriesNoToken()
    {
        Assert.True(AgentAccessToken.IsAuthorized(new Dictionary<string, string>(), expected: null));
    }

    [Fact]
    public void AcceptsOnlyTheSameToken()
    {
        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        Assert.False(AgentAccessToken.IsAuthorized(headers, Token));

        headers["x-veil-agent-token"] = Token;
        Assert.True(AgentAccessToken.IsAuthorized(headers, Token));

        headers["X-Veil-Agent-Token"] = Token[..^1] + "0";
        Assert.False(AgentAccessToken.IsAuthorized(headers, Token));

        headers["X-Veil-Agent-Token"] = "";
        Assert.False(AgentAccessToken.IsAuthorized(headers, Token));
    }

    [Fact]
    public void FindsTheTokenAmongOemStrings()
    {
        Assert.Equal(Token, AgentAccessToken.FromOemStrings(["vendor string", AgentAccessToken.OemStringPrefix + Token]));
        Assert.Null(AgentAccessToken.FromOemStrings(["vendor string"]));
        // Too short, or not hex: not a token Veil wrote.
        Assert.Null(AgentAccessToken.FromOemStrings([AgentAccessToken.OemStringPrefix + "abc"]));
        Assert.Null(AgentAccessToken.FromOemStrings([AgentAccessToken.OemStringPrefix + new string('z', 64)]));
    }

    [Fact]
    public void ReadsOemStringsFromARawSmbiosTable()
    {
        var table = new List<byte>();
        // Type 1 (system information), formatted area of 8 bytes, two strings.
        table.AddRange([1, 8, 0x01, 0x00, 1, 2, 0, 0]);
        table.AddRange(Encoding.ASCII.GetBytes("QEMU\0Standard PC\0\0"));
        // Type 11 (OEM strings), formatted area of 5 bytes, two strings.
        table.AddRange([11, 5, 0x02, 0x00, 2]);
        table.AddRange(Encoding.ASCII.GetBytes("other\0" + AgentAccessToken.OemStringPrefix + Token + "\0\0"));
        // Type 32 with no strings ends in two zero bytes.
        table.AddRange([32, 4, 0x03, 0x00, 0, 0]);
        // End of table.
        table.AddRange([127, 4, 0x04, 0x00, 0, 0]);

        var strings = AgentAccessToken.OemStrings(table.ToArray());

        Assert.Equal(["other", AgentAccessToken.OemStringPrefix + Token], strings);
        Assert.Equal(Token, AgentAccessToken.FromOemStrings(strings));
    }

    [Fact]
    public void ToleratesATruncatedTable()
    {
        byte[] table = [11, 5, 0x02, 0x00, 1, (byte)'a', (byte)'b'];
        Assert.Empty(AgentAccessToken.OemStrings(table));
        Assert.Empty(AgentAccessToken.OemStrings([11, 2]));
    }

    [Fact]
    public void ReadsTheStructureQemuWritesForTheTokenFile()
    {
        // Type 11 as the bundled QEMU 11.1.3 and its EDK2 firmware laid it out for
        // -smbios type=11,path=<token file>, dumped with the UEFI shell's smbiosview -t 11 on 2026-11-14.
        var table = new List<byte> { 0x0B, 0x05, 0x00, 0x0E, 0x01 };
        table.AddRange(Encoding.ASCII.GetBytes(AgentAccessToken.OemStringPrefix + Token));
        table.AddRange([0x00, 0x00]);
        table.AddRange([127, 4, 0xFF, 0xFE, 0, 0]);

        Assert.Equal(Token, AgentAccessToken.FromOemStrings(AgentAccessToken.OemStrings(table.ToArray())));
    }
}
