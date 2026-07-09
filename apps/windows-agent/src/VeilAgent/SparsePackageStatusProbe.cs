using System.Text.Json;
using System.Text.Json.Nodes;

namespace Veil.Agent;

public interface ISparsePackageStatusProbe
{
    JsonObject? ReadStatus();
}

public sealed class SparsePackageStatusProbe : ISparsePackageStatusProbe
{
    private readonly string statusPath;

    public SparsePackageStatusProbe(string? statusPath = null)
    {
        this.statusPath = statusPath ?? Path.Combine(
            Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "Veil",
            "Agent",
            "package",
            "sparse-package-status.json"
        );
    }

    public JsonObject? ReadStatus()
    {
        if (!File.Exists(statusPath))
        {
            return null;
        }

        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(statusPath));
            var root = document.RootElement;
            return new JsonObject
            {
                ["statusPath"] = statusPath,
                ["stage"] = ReadString(root, "stage") ?? "unknown",
                ["succeeded"] = ReadBoolean(root, "succeeded") ?? false,
                ["message"] = ReadString(root, "message") ?? "",
                ["updatedAt"] = ReadString(root, "updatedAt"),
                ["packagePath"] = ReadString(root, "packagePath"),
                ["certificatePath"] = ReadString(root, "certificatePath")
            };
        }
        catch (Exception error) when (error is IOException or UnauthorizedAccessException or JsonException)
        {
            return new JsonObject
            {
                ["statusPath"] = statusPath,
                ["stage"] = "unreadable",
                ["succeeded"] = false,
                ["message"] = error.Message
            };
        }
    }

    private static string? ReadString(JsonElement root, string propertyName)
    {
        return root.TryGetProperty(propertyName, out var property) && property.ValueKind == JsonValueKind.String
            ? property.GetString()
            : null;
    }

    private static bool? ReadBoolean(JsonElement root, string propertyName)
    {
        return root.TryGetProperty(propertyName, out var property) && property.ValueKind is JsonValueKind.True or JsonValueKind.False
            ? property.GetBoolean()
            : null;
    }
}
