using System.Buffers.Binary;
using System.IO;
using System.Text;
using System.Text.Json;
using JT.Copilot.Application.Models;
using JT.Copilot.Application.Text;
using JT.Copilot.Infrastructure.Storage;
using Vosk;

namespace JT.Copilot.IntegrationTests;

public sealed class VoskDomainCorrectionTests
{
    [Fact]
    public void LocalVoskFixture_CorrectsBusinessTerms()
    {
        var audioPath = Path.GetFullPath("artifacts/test-domain-terms-zh.wav");
        if (!File.Exists(audioPath) || !Directory.Exists(AppPaths.VoskModelDirectory))
        {
            return;
        }

        using var model = new Model(AppPaths.VoskModelDirectory);
        using var recognizer = new VoskRecognizer(model, 16_000.0f);
        var pcm = ReadWaveData(audioPath);

        for (var offset = 0; offset < pcm.Length; offset += 3_200)
        {
            var length = Math.Min(3_200, pcm.Length - offset);
            recognizer.AcceptWaveform(pcm.AsSpan(offset, length).ToArray(), length);
        }

        var rawText = ParseText(recognizer.FinalResult());
        var corrected = new DomainTermCorrector().Correct(
            rawText,
            new AppSettings().CustomVocabulary);

        Assert.Contains("CRM系统", corrected);
        Assert.Contains("积分兑礼", corrected);
        Assert.Contains("OK吗", corrected);
        Assert.Contains("项目背景", corrected);
        Assert.Contains("业务目标", corrected);
        Assert.DoesNotContain("新奥尔良", corrected);
        Assert.DoesNotContain("积分队里", corrected);
    }

    private static byte[] ReadWaveData(string path)
    {
        var bytes = File.ReadAllBytes(path);
        using var stream = new MemoryStream(bytes);
        using var reader = new BinaryReader(stream, Encoding.ASCII, leaveOpen: true);

        if (reader.ReadUInt32() != 0x46464952)
        {
            throw new InvalidDataException("WAV file is missing the RIFF header.");
        }

        _ = reader.ReadUInt32();
        _ = reader.ReadUInt32();
        while (stream.Position + 8 <= stream.Length)
        {
            var chunkId = reader.ReadUInt32();
            var chunkLength = BinaryPrimitives.ReadInt32LittleEndian(reader.ReadBytes(4));
            var chunkStart = checked((int)stream.Position);
            if (chunkId == 0x61746164)
            {
                return bytes.AsSpan(chunkStart, chunkLength).ToArray();
            }

            stream.Position = chunkStart + chunkLength + (chunkLength % 2);
        }

        throw new InvalidDataException("WAV file is missing the data chunk.");
    }

    private static string ParseText(string json)
    {
        using var document = JsonDocument.Parse(json);
        return document.RootElement.TryGetProperty("text", out var text)
            ? text.GetString() ?? string.Empty
            : string.Empty;
    }
}
