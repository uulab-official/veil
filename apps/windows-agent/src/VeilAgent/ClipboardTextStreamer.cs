using System.Text.Json.Nodes;

namespace Veil.Agent;

/// <summary>
/// Watches the Windows clipboard and broadcasts guest copies as <c>clipboard.text.set</c> or
/// <c>clipboard.image.set</c>.
/// </summary>
/// <remarks>
/// Text and images share one sequence, because the host treats them as two kinds of one clipboard and
/// rejects an older sequence of either. When the clipboard holds both (a spreadsheet range, rich text),
/// only the text is sent; see docs/protocol.md "Clipboard Image". A file copy (<c>CF_HDROP</c>) is checked
/// first and wins over any text the source also wrote, the way Finder's file URLs win on the Mac; the files
/// are staged in the shared folder and named with <c>clipboard.files.set</c> ("Clipboard Files").
/// </remarks>
public sealed class ClipboardTextStreamer
{
    private readonly IWindowsDesktop desktop;
    private readonly TimeSpan interval;
    private readonly ClipboardFileExport? fileExport;
    private readonly Func<DateTime> utcNow;
    private int sequence;
    private uint lastFileClipboardSequence;
    private string? lastFileDropKey;
    private string? lastBroadcastText;
    private string? lastBroadcastImageSha256;
    private uint lastImageClipboardSequence;

    /// <param name="fileExport">Stages Explorer file copies for the host. Null leaves files on the guest.</param>
    public ClipboardTextStreamer(
        IWindowsDesktop desktop,
        TimeSpan? interval = null,
        ClipboardFileExport? fileExport = null,
        Func<DateTime>? utcNow = null
    )
    {
        this.desktop = desktop;
        this.interval = interval ?? TimeSpan.FromMilliseconds(500);
        this.fileExport = fileExport;
        this.utcNow = utcNow ?? (() => DateTime.UtcNow);
    }

    public async Task StreamAsync(
        Func<JsonObject, CancellationToken, Task> onClipboardText,
        CancellationToken cancellationToken
    )
    {
        using var timer = new PeriodicTimer(interval);

        while (await timer.WaitForNextTickAsync(cancellationToken))
        {
            if (fileExport is not null && IsFileDropAvailable())
            {
                await PollFilesAsync(fileExport, onClipboardText, cancellationToken);
                continue;
            }

            // The clipboard no longer holds files, so copying the same files again later is a new copy.
            lastFileDropKey = null;

            string? text;
            try
            {
                text = await desktop.GetClipboardTextAsync(cancellationToken);
            }
            catch (Exception error) when (error is not OperationCanceledException)
            {
                // Windows clipboard access is contended by design (any app can hold OpenClipboard
                // briefly); a transient failure here must not permanently kill clipboard sync for the
                // rest of the agent's process lifetime. Matches the fallback pattern
                // WindowFrameStreamer already uses for transient per-tick capture failures.
                Console.Error.WriteLine(
                    $"ClipboardTextStreamer: transient clipboard read failure. {error.GetType().Name}: {error.Message}"
                );
                continue;
            }

            if (text is null)
            {
                await PollImageAsync(onClipboardText, cancellationToken);
                continue;
            }

            if (text == lastBroadcastText)
            {
                continue;
            }

            // A different kind of content replaced the last image, so copying that image again later must
            // count as a new copy rather than a repeat.
            lastBroadcastImageSha256 = null;

            if (desktop.TryConsumeHostClipboardEcho(text))
            {
                lastBroadcastText = text;
                continue;
            }

            sequence += 1;
            lastBroadcastText = text;
            await onClipboardText(ClipboardTextEvent(sequence, text), cancellationToken);
        }
    }

    private async Task PollImageAsync(
        Func<JsonObject, CancellationToken, Task> onClipboardEvent,
        CancellationToken cancellationToken
    )
    {
        // An image can be megabytes, so it is only read again once Windows reports a clipboard change.
        var clipboardSequence = desktop.GetClipboardSequenceNumber();
        if (clipboardSequence != 0 && clipboardSequence == lastImageClipboardSequence)
        {
            return;
        }

        byte[]? png;
        try
        {
            png = await desktop.GetClipboardImagePngAsync(cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"ClipboardTextStreamer: transient clipboard image read failure. {error.GetType().Name}: {error.Message}"
            );
            return;
        }

        lastImageClipboardSequence = clipboardSequence;
        if (png is null)
        {
            return;
        }

        // Windows bumps its sequence number when an app re-sets identical content, so the hash, not the
        // sequence number, decides whether this is a new copy.
        var sha256 = ClipboardImageMessage.Sha256Hex(png);
        // The echo is consumed whenever it is seen, even for a repeat: the host can send back an image this
        // agent broadcast earlier, and a mark left behind would later swallow a genuine copy of that image.
        var isHostEcho = desktop.TryConsumeHostClipboardImageEcho(sha256);
        if (sha256 == lastBroadcastImageSha256)
        {
            return;
        }

        lastBroadcastText = null;
        lastBroadcastImageSha256 = sha256;
        if (isHostEcho)
        {
            return;
        }

        var message = ClipboardImageMessage.GuestEvent(sequence + 1, png, sha256);
        if (message is null)
        {
            Console.Error.WriteLine(
                $"ClipboardTextStreamer: skipped a {png.Length}-byte clipboard image outside the protocol bounds."
            );
            return;
        }

        sequence += 1;
        await onClipboardEvent(message, cancellationToken);
    }

    private bool IsFileDropAvailable()
    {
        try
        {
            return desktop.IsClipboardFileDropAvailable();
        }
        catch (Exception error)
        {
            Console.Error.WriteLine(
                $"ClipboardTextStreamer: could not check for clipboard files. {error.GetType().Name}: {error.Message}"
            );
            return false;
        }
    }

    private async Task PollFilesAsync(
        ClipboardFileExport export,
        Func<JsonObject, CancellationToken, Task> onClipboardEvent,
        CancellationToken cancellationToken
    )
    {
        // Staging copies up to 512 MiB, so it runs once per clipboard change, not once per tick.
        var clipboardSequence = desktop.GetClipboardSequenceNumber();
        if (clipboardSequence != 0 && clipboardSequence == lastFileClipboardSequence)
        {
            return;
        }

        IReadOnlyList<string>? paths;
        try
        {
            paths = await desktop.GetClipboardFileDropAsync(cancellationToken);
        }
        catch (Exception error) when (error is not OperationCanceledException)
        {
            Console.Error.WriteLine(
                $"ClipboardTextStreamer: transient clipboard file read failure. {error.GetType().Name}: {error.Message}"
            );
            return;
        }

        lastFileClipboardSequence = clipboardSequence;
        // Text or an image copied after these files is a new copy even if it repeats the last one sent.
        lastBroadcastText = null;
        lastBroadcastImageSha256 = null;
        if (paths is null || paths.Count == 0)
        {
            return;
        }

        // Without a sequence number (zero means unknown) the path list is what tells a repeat from a copy.
        var key = string.Join('\n', paths);
        if (key == lastFileDropKey)
        {
            return;
        }

        lastFileDropKey = key;
        if (export.IsVeilStaged(paths))
        {
            // A host paste placed these in the share; sending them back would echo it.
            return;
        }

        var result = await Task.Run(
            () => export.Stage(paths, utcNow(), ClipboardFileExport.RandomBatchSuffix()),
            cancellationToken
        );
        if (result.RelativePaths is null)
        {
            Console.Error.WriteLine($"ClipboardTextStreamer: did not send copied files to the host. {result.Refusal}");
            return;
        }

        sequence += 1;
        await onClipboardEvent(ClipboardFileExport.GuestEvent(sequence, result.RelativePaths), cancellationToken);
    }

    private static JsonObject ClipboardTextEvent(int sequence, string text) => new()
    {
        ["type"] = MessageTypes.ClipboardTextSet,
        ["requestId"] = $"evt_clipboard_{sequence}",
        ["origin"] = "guest",
        ["sequence"] = sequence,
        ["text"] = text
    };
}
