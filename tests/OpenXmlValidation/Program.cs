// See https://aka.ms/new-console-template for more information
using DocumentFormat.OpenXml.Packaging;
using DocumentFormat.OpenXml.Validation;
using System.Security.Cryptography;
using System.Text.Json;

var failed = false;
var reports = new List<object>();
var target = DocumentFormat.OpenXml.FileFormatVersions.Office2007;
var firstPath = 0;
if (args.Length > 0 && args[0] == "--office-version") {
    if (args.Length < 3 || args[1] is not ("Office2007" or "Office2013")) {
        Console.Error.WriteLine("usage: [--office-version Office2007|Office2013] FILE...");
        return 4;
    }
    target = args[1] == "Office2013" ? DocumentFormat.OpenXml.FileFormatVersions.Office2013 : target;
    firstPath = 2;
}
if (args.Length == firstPath) { Console.Error.WriteLine("At least one file is required"); return 4; }
foreach (var path in args.Skip(firstPath)) {
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
        using OpenXmlPackage document = Path.GetExtension(path).ToLowerInvariant() is ".docx" or ".docm"
            ? WordprocessingDocument.Open(snapshot, false)
            : SpreadsheetDocument.Open(snapshot, false);
        var validator = new OpenXmlValidator(target);
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
    tool = "DocumentFormat.OpenXml", version = "3.3.0", target = target.ToString(), reports
}, new JsonSerializerOptions { WriteIndented = true }));
return failed ? 2 : 0;
