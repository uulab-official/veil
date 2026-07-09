using System.Runtime.InteropServices;

namespace Veil.Agent;

public interface IPackageIdentityProbe
{
    bool HasPackageIdentity { get; }
}

public sealed class WindowsPackageIdentityProbe : IPackageIdentityProbe
{
    private const int ErrorSuccess = 0;
    private const int ErrorInsufficientBuffer = 122;
    private const int AppModelErrorNoPackage = 15700;

    public bool HasPackageIdentity => TryGetPackageFullName(out _);

    public static bool TryGetPackageFullName(out string? packageFullName)
    {
        packageFullName = null;
        if (!OperatingSystem.IsWindows())
        {
            return false;
        }

        var length = 0;
        var result = GetCurrentPackageFullName(ref length, null);
        if (result == AppModelErrorNoPackage)
        {
            return false;
        }

        if (result != ErrorInsufficientBuffer || length <= 0)
        {
            return false;
        }

        var buffer = new char[length];
        result = GetCurrentPackageFullName(ref length, buffer);
        if (result != ErrorSuccess)
        {
            return false;
        }

        packageFullName = new string(buffer, 0, Math.Max(0, length - 1));
        return packageFullName.Length > 0;
    }

    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = false)]
    private static extern int GetCurrentPackageFullName(ref int packageFullNameLength, char[]? packageFullName);
}
