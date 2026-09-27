using System.Collections;
using System.Reflection;
using System.Runtime.CompilerServices;
using System.Security.Cryptography;
using System.Text.Json;
using DMCompiler;
using DMCompiler.Compiler.DM;
using DMCompiler.Compiler.DM.AST;
using DMCompiler.Compiler.DMPreprocessor;
using DMCompiler.Compiler;

if (args.Length is not (3 or 4) || (args.Length == 4 && args[3] != "--reuse-if-current")) {
    Console.Error.WriteLine("usage: OpenDreamBridge <project.dme> <output.jsonl> <OpenDream compiler directory> [--reuse-if-current]");
    return 2;
}

var manifest = Path.GetFullPath(args[0]);
var outputPath = Path.GetFullPath(args[1]);
var compilerDirectory = Path.GetFullPath(args[2]);
var compilerPath = Path.Combine(compilerDirectory, "DMCompiler.dll");
var bridgePath = Assembly.GetExecutingAssembly().Location;
if (args.Length == 4 && Reusable(outputPath, manifest, compilerPath, bridgePath)) {
    Console.Error.WriteLine("OpenDream AST cache hit: included files, compiler, bridge, and output checksum match");
    return 0;
}
var compiler = new DMCompiler.DMCompiler {
    Settings = new DMCompilerSettings { Files = [manifest], DMVersion = 516, DMBuild = 1687, MacroDefines = new Dictionary<string, string> { ["CIBUILDING"] = "" } }
};
compiler.AddResourceDirectory(Path.GetDirectoryName(manifest)!, Location.Internal);
var preprocessor = new DMPreprocessor(compiler, true);
preprocessor.DefineMacro("CIBUILDING", "");
preprocessor.IncludeFile(Path.GetDirectoryName(manifest), Path.GetFileName(manifest), false);
preprocessor.IncludeFile(Path.Combine(compilerDirectory, "DMStandard"), "_Standard.dm", true);
var parser = new DMParser(compiler, new DMLexer("<unknown>", preprocessor));
var ast = parser.File();
var errorCount = (int?)typeof(DMCompiler.DMCompiler)
    .GetField("_errorCount", BindingFlags.Instance | BindingFlags.NonPublic)?
    .GetValue(compiler) ?? -1;
if (compiler.UniqueEmissions.Contains(WarningCode.ErrorRecoveryActivated)) {
    Console.Error.WriteLine("OpenDream recovered from a parse error; refusing an incomplete AST");
    return 3;
}
if (errorCount != 0) {
    Console.Error.WriteLine($"OpenDream reported {errorCount} frontend errors; refusing an unverified AST");
    return 4;
}
var includedFiles = (HashSet<string>?)typeof(DMPreprocessor)
    .GetField("_includedFiles", BindingFlags.Instance | BindingFlags.NonPublic)?
    .GetValue(preprocessor);
if (includedFiles is null) {
    Console.Error.WriteLine("Cannot identify OpenDream's included source files");
    return 5;
}
var sourceFiles = includedFiles.OrderBy(path => path, StringComparer.Ordinal)
    .Select(path => new { path, sha256 = HexHash(path) }).ToArray();
var temporaryOutput = outputPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
using var output = new StreamWriter(temporaryOutput);
output.WriteLine(JsonSerializer.Serialize(new { kind = "bridge-meta", schemaVersion = 4,
    dmVersion = 516, dmBuild = 1687, frontendErrors = errorCount, manifestPath = manifest, sourceFiles,
    compilerPath, compilerSha256 = HexHash(compilerPath),
    bridgePath, bridgeSha256 = HexHash(bridgePath) }));
var seen = new HashSet<DMASTNode>(ReferenceEqualityComparer.Instance);
foreach (var statement in ast.BlockInner.Statements) {
    Walk(statement);
}
output.Dispose();
File.Move(temporaryOutput, outputPath, true);
File.WriteAllText(outputPath + ".sha256", HexHash(outputPath));

string HexHash(string path) {
    using var stream = File.OpenRead(path);
    return System.Convert.ToHexString(SHA256.HashData(stream)).ToLowerInvariant();
}

bool Reusable(string path, string manifestFile, string compilerDll, string bridgeDll) {
    try {
        if (!File.Exists(path) || !File.Exists(path + ".sha256") ||
            File.ReadAllText(path + ".sha256").Trim() != HexHash(path)) return false;
        using var reader = new StreamReader(path);
        using var document = JsonDocument.Parse(reader.ReadLine() ?? "");
        var meta = document.RootElement;
        if (meta.GetProperty("schemaVersion").GetInt32() != 4 ||
            meta.GetProperty("frontendErrors").GetInt32() != 0 ||
            meta.GetProperty("manifestPath").GetString() != manifestFile ||
            meta.GetProperty("compilerPath").GetString() != compilerDll ||
            meta.GetProperty("compilerSha256").GetString() != HexHash(compilerDll) ||
            meta.GetProperty("bridgePath").GetString() != bridgeDll ||
            meta.GetProperty("bridgeSha256").GetString() != HexHash(bridgeDll)) return false;
        foreach (var source in meta.GetProperty("sourceFiles").EnumerateArray()) {
            var file = source.GetProperty("path").GetString();
            if (file is null || source.GetProperty("sha256").GetString() != HexHash(file)) return false;
        }
        return true;
    } catch (Exception) {
        return false;
    }
}

void Walk(DMASTNode node) {
    if (!seen.Add(node)) return;
    if (node is DMASTProcDefinition proc) {
        output.WriteLine(JsonSerializer.Serialize(new {
            kind = "proc",
            owner = proc.ObjectPath.ToString(),
            name = proc.Name,
            file = proc.Location.SourceFile,
            line = proc.Location.Line,
            parameters = proc.Parameters.Select(p => new { p.Name, type = p.ObjectType?.ToString(), valueType = p.Type?.ToString(), defaultValue = Node(p.Value) }).ToArray(),
            returnType = proc.ReturnTypes?.ToString(),
            body = Node(proc.Body)
        }, new JsonSerializerOptions { MaxDepth = 1024 }));
    } else if (node is DMASTObjectVarDefinition field) {
        output.WriteLine(JsonSerializer.Serialize(new {
            kind = "field",
            owner = field.ObjectPath.ToString(),
            name = field.Name,
            file = field.Location.SourceFile,
            line = field.Location.Line,
            type = field.Type?.ToString(),
            valueType = field.ValType.ToString(),
            initializer = Node(field.Value)
        }, new JsonSerializerOptions { MaxDepth = 1024 }));
    } else if (node.GetType().Name == "DMASTObjectVarOverride") {
        // Parent type overrides change the real inheritance graph without
        // changing the textual path hierarchy. Keep the AST value for Rust to
        // validate; a nonconstant parent must never become a guessed edge.
        var nodeType = node.GetType();
        var name = nodeType.GetField("VarName")?.GetValue(node)?.ToString();
        var value = nodeType.GetField("Value")?.GetValue(node) as DMASTNode;
        if (name == "parent_type") {
            output.WriteLine(JsonSerializer.Serialize(new {
                kind = "type-parent",
                owner = nodeType.GetField("ObjectPath")?.GetValue(node)?.ToString(),
                file = node.Location.SourceFile,
                line = node.Location.Line,
                expression = Node(value)
            }, new JsonSerializerOptions { MaxDepth = 1024 }));
        } else {
            output.WriteLine(JsonSerializer.Serialize(new {
                kind = "field-override",
                owner = nodeType.GetField("ObjectPath")?.GetValue(node)?.ToString(),
                name,
                file = node.Location.SourceFile,
                line = node.Location.Line,
                initializer = Node(value)
            }, new JsonSerializerOptions { MaxDepth = 1024 }));
        }
    }
    foreach (var child in Children(node)) Walk(child);
}

object? Node(DMASTNode? node) {
    if (node is null) return null;
    var fields = new Dictionary<string, object?>();
    foreach (var field in node.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance)) {
        if (field.Name == "Location") continue;
        fields[field.Name] = Convert(field.GetValue(node));
    }
    if (node is DMASTProcStatementVarDeclaration local) {
        fields["Name"] = local.Name;
        fields["Type"] = local.Type?.ToString();
        fields["ValueType"] = local.ValType.ToString();
        fields["IsGlobal"] = local.IsGlobal;
    }
    if (node.GetType().Name == "DMASTModifiedType" &&
        node.GetType().GetField("VarOverrides")?.GetValue(node) is IEnumerable overrides) {
        // OpenDream currently represents these as KeyValuePair values. The
        // generic fallback below stringifies pairs, losing both the
        // initializer AST and its source location. Preserve the old field for
        // schema-4 readers and add a structured form for type inference.
        fields["VarOverridesAst"] = overrides.Cast<object?>().Select(item => {
            if (item is ITuple tuple && tuple.Length == 2)
                return new { name = tuple[0]?.ToString(), value = Convert(tuple[1]) };
            if (item is null) throw new InvalidDataException("OpenDream returned a null modified-type override");
            var pairType = item.GetType();
            if (pairType.GetProperty("Key") is null || pairType.GetProperty("Value") is null)
                throw new InvalidDataException($"Unsupported OpenDream modified-type override: {pairType.FullName}");
            var key = pairType.GetProperty("Key")?.GetValue(item);
            var value = pairType.GetProperty("Value")?.GetValue(item);
            return new { name = key?.ToString(), value = Convert(value) };
        }).ToArray();
    }
    return new { kind = node.GetType().Name, file = node.Location.SourceFile, line = node.Location.Line, fields };
}

object? Convert(object? value) {
    if (value is null) return null;
    if (value is DMASTNode node) return Node(node);
    if (value is DMASTDereference.Operation operation) {
        var fields = new Dictionary<string, object?>();
        foreach (var field in operation.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance)) {
            if (field.Name == "Location") continue;
            fields[field.Name] = Convert(field.GetValue(operation));
        }
        return new { kind = operation.GetType().Name, fields };
    }
    if (value is float f && !float.IsFinite(f)) return f.ToString();
    if (value is double d && !double.IsFinite(d)) return d.ToString();
    if (value is string or bool or int or float or double or long) return value;
    if (value is IEnumerable enumerable) return enumerable.Cast<object?>().Select(Convert).ToArray();
    var valueType = value.GetType();
    if (valueType.Assembly == typeof(DMASTNode).Assembly &&
        valueType.Namespace?.StartsWith("DMCompiler.Compiler.DM.AST", StringComparison.Ordinal) == true) {
        var fields = new Dictionary<string, object?>();
        foreach (var field in valueType.GetFields(BindingFlags.Public | BindingFlags.Instance)) {
            fields[field.Name] = Convert(field.GetValue(value));
        }
        return new { kind = valueType.Name, fields };
    }
    return value.ToString();
}

IEnumerable<DMASTNode> Children(DMASTNode node) {
    foreach (var field in node.GetType().GetFields(BindingFlags.Public | BindingFlags.Instance)) {
        if (field.GetValue(node) is DMASTNode child) yield return child;
        else if (field.GetValue(node) is IEnumerable enumerable and not string) {
            foreach (var item in enumerable) if (item is DMASTNode nested) yield return nested;
        }
    }
}

return 0;
