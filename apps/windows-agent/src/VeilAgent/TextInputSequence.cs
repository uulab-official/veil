namespace Veil.Agent;

/// <summary>
/// The key presses that go before typed text, kept apart from <c>SendInput</c> so they can be tested off Windows.
/// </summary>
internal static class TextInputSequence
{
    internal const int VirtualKeyBack = 0x08;

    /// <summary>A down and up Backspace per code unit to delete, for <c>input.text</c>'s <c>replaceLength</c>.</summary>
    internal static IReadOnlyList<(int VirtualKey, bool KeyUp)> Backspaces(int count)
    {
        var steps = new List<(int VirtualKey, bool KeyUp)>(Math.Max(0, count) * 2);
        for (var index = 0; index < count; index++)
        {
            steps.Add((VirtualKeyBack, false));
            steps.Add((VirtualKeyBack, true));
        }
        return steps;
    }
}
