using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// How long each step of a frame capture takes, and which capture method ran, reported in agent health.
/// </summary>
/// <remarks>
/// Mirrored drawing ran near 20 frames a second against a 60 Hz target with the host spending 1-2 ms a
/// tile, so the time is in the guest. The guest's own logs are out of the host's reach, so the numbers
/// travel in the health reply the host already polls. Means are exponentially weighted so they follow the
/// current workload instead of the whole session.
/// </remarks>
public sealed class FrameCaptureDiagnostics
{
    public static FrameCaptureDiagnostics Shared { get; } = new();

    public const string AutomaticStrategy = "auto";
    public const string ScreenCopyStrategy = "screen";
    public const string PrintWindowStrategy = "printWindow";
    public const string DuplicationStrategy = "duplication";

    private const double Smoothing = 0.1;
    private readonly object gate = new();
    private readonly Dictionary<string, (double Mean, double Max, long Count)> phases = new();
    private readonly Dictionary<string, long> methodCounts = new();
    private string strategy = AutomaticStrategy;
    private string? lastDuplicationFailure;

    /// <summary>Why Desktop Duplication last fell back, for the health reply.</summary>
    public void RecordDuplicationFailure(string reason)
    {
        lock (gate)
        {
            lastDuplicationFailure = $"{DateTime.UtcNow:O} {reason}";
        }
    }

    /// <summary>
    /// The capture method in force: automatic, or one forced for comparison from the host.
    /// </summary>
    public string Strategy
    {
        get
        {
            lock (gate)
            {
                return strategy;
            }
        }
    }

    /// <summary>Returns false for an unknown strategy, which is ignored.</summary>
    public bool SetStrategy(string value)
    {
        if (value is not (AutomaticStrategy or ScreenCopyStrategy or PrintWindowStrategy or DuplicationStrategy))
        {
            return false;
        }

        lock (gate)
        {
            strategy = value;
            phases.Clear();
            methodCounts.Clear();
        }
        return true;
    }

    public void Record(string phase, double milliseconds)
    {
        lock (gate)
        {
            if (phases.TryGetValue(phase, out var current))
            {
                phases[phase] = (
                    current.Mean + Smoothing * (milliseconds - current.Mean),
                    Math.Max(current.Max, milliseconds),
                    current.Count + 1
                );
            }
            else
            {
                phases[phase] = (milliseconds, milliseconds, 1);
            }
        }
    }

    public void RecordMethod(string method)
    {
        lock (gate)
        {
            methodCounts[method] = methodCounts.GetValueOrDefault(method) + 1;
        }
    }

    public JsonObject Snapshot()
    {
        lock (gate)
        {
            var phaseObject = new JsonObject();
            foreach (var (name, value) in phases.OrderBy(pair => pair.Key, StringComparer.Ordinal))
            {
                phaseObject[name] = new JsonObject
                {
                    ["meanMilliseconds"] = Math.Round(value.Mean, 2),
                    ["maxMilliseconds"] = Math.Round(value.Max, 2),
                    ["count"] = value.Count
                };
            }

            var methodObject = new JsonObject();
            foreach (var (name, count) in methodCounts.OrderBy(pair => pair.Key, StringComparer.Ordinal))
            {
                methodObject[name] = count;
            }

            return new JsonObject
            {
                ["strategy"] = strategy,
                ["phases"] = phaseObject,
                ["methods"] = methodObject,
                ["lastDuplicationFailure"] = lastDuplicationFailure
            };
        }
    }
}
