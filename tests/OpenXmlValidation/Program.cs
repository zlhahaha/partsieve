// See https://aka.ms/new-console-template for more information
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using System.Security.Cryptography;
using System.Text.Json;

var failed = false;
var reports = new List<object>();
foreach (var path in args) {
    try {
        // WPS may keep a file open. Validate a bounded byte snapshot so the
        // SDK's default file-sharing mode does not conflict with the client.
        using var file = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
        const int cap = 32 * 1024 * 1024;
        if (file.Length > cap) throw new InvalidDataException("Test input exceeds 32 MiB");
        using var snapshot = new MemoryStream();
        var buffer = new byte[65536];
        int count;
        while ((count = file.Read(buffer, 0, buffer.Length)) != 0) {
            if (snapshot.Length + count > cap) throw new InvalidDataException("Input grew beyond test limit");
            snapshot.Write(buffer, 0, count);
        }
        var sha256 = Convert.ToHexString(SHA256.HashData(snapshot.ToArray())).ToLowerInvariant();
        snapshot.Position = 0;
        using var document = SpreadsheetDocument.Open(snapshot, false);
        var validator = new OpenXmlValidator(DocumentFormat.OpenXml.FileFormatVersions.Office2007);
        var errors = validator.Validate(document).Take(100).Select(e => new {
            e.Id, e.Description, Part = e.Part?.Uri.ToString(), XPath = e.Path?.XPath
        }).ToArray();
        failed |= errors.Length != 0;
        reports.Add(new { path, sha256, status = errors.Length == 0 ? "Pass" : "Fail", errors });
    } catch (Exception ex) {
        failed = true;
        reports.Add(new { path, status = "Fail", error = ex.Message });
    }
}
Console.WriteLine(JsonSerializer.Serialize(new {
    tool = "DocumentFormat.OpenXml", version = "3.3.0", target = "Office2007", reports
}, new JsonSerializerOptions { WriteIndented = true }));
return failed ? 2 : 0;
