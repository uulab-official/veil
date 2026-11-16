using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;

namespace Veil.Agent;

/// <summary>
/// The secret a connection must present before the agent accepts it, when the machine carries one.
/// </summary>
/// <remarks>
/// The agent's port is forwarded to the Mac's loopback interface, which every account on the Mac can open,
/// and the connection types, starts programs, and reads the clipboard. Veil puts a random token in the
/// virtual machine's SMBIOS OEM strings (type 11, from a file only the Mac user can read, through QEMU's
/// <c>-smbios type=11,path=</c>), and sends it in the <c>X-Veil-Agent-Token</c> header. Windows exposes the
/// SMBIOS tables to every process through <c>GetSystemFirmwareTable</c>
/// (<see href="https://learn.microsoft.com/windows/win32/api/sysinfoapi/nf-sysinfoapi-getsystemfirmwaretable"/>).
///
/// A machine started without the token, by an older Veil or before Windows restarted, has none, and the
/// agent then accepts connections as before.
/// </remarks>
public static class AgentAccessToken
{
    public const string HeaderName = "X-Veil-Agent-Token";
    public const string OemStringPrefix = "org.uulab.veil.agent-token=";
    private const int MinimumTokenLength = 32;
    private const byte OemStringsType = 11;
    private const byte EndOfTableType = 127;

    private static readonly Lazy<string?> Machine = new(ReadFromFirmware);

    /// <summary>The token this machine was started with, or null when it carries none.</summary>
    public static string? Expected => Machine.Value;

    /// <summary>
    /// Whether the handshake may proceed: always when no token is expected, otherwise only with the same token.
    /// </summary>
    public static bool IsAuthorized(IReadOnlyDictionary<string, string> headers, string? expected)
    {
        if (expected is null)
        {
            return true;
        }
        if (!headers.TryGetValue(HeaderName, out var presented))
        {
            return false;
        }
        return CryptographicOperations.FixedTimeEquals(
            Encoding.UTF8.GetBytes(presented.Trim()),
            Encoding.UTF8.GetBytes(expected));
    }

    /// <summary>The token among SMBIOS OEM strings, or null.</summary>
    public static string? FromOemStrings(IEnumerable<string> strings)
    {
        foreach (var value in strings)
        {
            if (!value.StartsWith(OemStringPrefix, StringComparison.Ordinal))
            {
                continue;
            }
            var token = value[OemStringPrefix.Length..].Trim();
            if (token.Length >= MinimumTokenLength && token.All(char.IsAsciiHexDigit))
            {
                return token;
            }
        }
        return null;
    }

    /// <summary>
    /// The strings of every OEM strings structure (type 11) in raw SMBIOS table data, as the DMTF SMBIOS
    /// specification lays it out: a formatted area of the length its header gives, then strings ending in
    /// two zero bytes.
    /// </summary>
    public static IReadOnlyList<string> OemStrings(ReadOnlySpan<byte> table)
    {
        var strings = new List<string>();
        var offset = 0;
        while (offset + 4 <= table.Length)
        {
            var type = table[offset];
            var length = table[offset + 1];
            if (length < 4 || offset + length > table.Length)
            {
                break;
            }

            var structureStrings = new List<string>();
            var cursor = offset + length;
            while (cursor < table.Length)
            {
                var end = table[cursor..].IndexOf((byte)0);
                if (end < 0)
                {
                    return strings;
                }
                if (end == 0)
                {
                    cursor++;
                    break;
                }
                structureStrings.Add(Encoding.ASCII.GetString(table.Slice(cursor, end)));
                cursor += end + 1;
            }
            // A structure with no strings ends in two zero bytes.
            if (structureStrings.Count == 0 && cursor < table.Length && table[cursor] == 0)
            {
                cursor++;
            }

            if (type == OemStringsType)
            {
                strings.AddRange(structureStrings);
            }
            if (type == EndOfTableType)
            {
                break;
            }
            offset = cursor;
        }
        return strings;
    }

    private static string? ReadFromFirmware()
    {
        if (!OperatingSystem.IsWindows())
        {
            return null;
        }
        try
        {
            var size = GetSystemFirmwareTable(RawSmbiosProvider, 0, null, 0);
            if (size <= RawSmbiosHeaderLength)
            {
                return null;
            }
            var buffer = new byte[size];
            if (GetSystemFirmwareTable(RawSmbiosProvider, 0, buffer, size) != size)
            {
                return null;
            }
            var tableLength = (int)Math.Min(BitConverter.ToUInt32(buffer, 4), (uint)(size - RawSmbiosHeaderLength));
            return FromOemStrings(OemStrings(buffer.AsSpan(RawSmbiosHeaderLength, tableLength)));
        }
        catch (Exception exception) when (exception is DllNotFoundException or EntryPointNotFoundException)
        {
            return null;
        }
    }

    // 'RSMB', and the RawSMBIOSData header before the table: four version bytes and a 32-bit length.
    private const uint RawSmbiosProvider = 0x52534D42;
    private const int RawSmbiosHeaderLength = 8;

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern uint GetSystemFirmwareTable(uint provider, uint tableId, byte[]? buffer, uint bufferSize);
}
