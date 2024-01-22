module caiman.make;

import std.string;
import caiman.traits;
import std.file;
import std.algorithm;
import std.stdio : writeln;
import std.traits;
import std.conv;
import std.meta;
import std.array;
import caiman.regex;

/// Used internally for generating C# conventions conforming names.
private static pure string toPascalCase(string input) 
{
    auto words = input.split(".");
    auto result = appender!string;

    foreach (word; words) 
    {
        if (!word.empty)
            result.put(toUpper(word[0]).to!string~word[1..$]~".");
    }

    return result.data[0..$-1];
}

/**
    Automatic C# and .h binding generator.

    Remarks:
        Same requirements as `traits.getImports` \
        Depends on Importer for C# \
        Depends on types having accessors generated using `mixin accessors`
*/
public template make(alias root, string dest)
{
    // TODO: Generic instantiations
    //       Top-level functions (see cor.d)
    public void csharp(string[] inherits...) 
    {
        const string cs = dest~"\\csharp\\"~fullyQualifiedName!root.toPascalCase();
        foreach (mod; getImports!root)
        {
            string path = cs~"\\"~fullyQualifiedName!mod.toPascalCase()~"\\";
            if (path.exists)
                path.rmdirRecurse;
            path.mkdirRecurse;

            string prev;
            // First 3 are pretty much guaranteed to be modules
            foreach (type; __traits(allMembers, mod)[2..$])
            {
                alias T = __traits(getMember, mod, type);
                static if (isType!T && !isTemplate!T && isAggregateType!T)
                {
                    string file = path~type~".cs";
                    if (prev != file && prev != null)
                        prev.append("\n}");
                    prev = file;

                    string[] tinherits = inherits.dup;
                    static if (getImplements!T.length > 0)
                        tinherits ~= getImplements!T[$-1].stringof;

                    if (tinherits.length != 0)
                        file.append("// Auto generated by caiman.make\nnamespace "~fullyQualifiedName!root.toPascalCase()[0..fullyQualifiedName!root.toPascalCase().lastIndexOf('.')]~";\n\npublic unsafe sealed class "~type~" : "~tinherits.joiner(", ").array.to!string~"\n{\n");
                    else 
                        file.append("// Auto generated by caiman.make\nnamespace "~fullyQualifiedName!root.toPascalCase()[0..fullyQualifiedName!root.toPascalCase().lastIndexOf('.')]~";\n\npublic unsafe sealed class "~type~"\n{\n");

                    foreach (member; __traits(allMembers, T))
                    {
                        alias A = __traits(getMember, T, member);
                        static if (isType!A && is(A == enum))
                        {
                            alias J = OriginalType!(typeof(__traits(getMember, A, __traits(allMembers, A)[0])));
                            string enumType = fullyQualifiedName!J.replace("ubyte", "byte");

                            static if (staticIndexOf!(flags, __traits(getAttributes, A)) != -1)
                                file.append("    [Flags]\n    public enum "~__traits(identifier, A)~" : "~enumType~"\n    {\n");
                            else
                                file.append("    public enum "~__traits(identifier, A)~" : "~enumType~"\n    {\n");

                            foreach (memenum; __traits(allMembers, A))
                                file.append("        "~memenum~" = "~(cast(J)__traits(getMember, A, memenum)).to!string~",\n");
                            file.append("    }\n\n");
                            
                        }
                        else static if (isCallable!A && isFunction!A && isExport!A)
                        {
                            string retType = ReturnType!A.stringof.replace("ubyte", "byte").replace("wchar", "char").replace("char", "byte");
                            //string generics = retType.findSplitAfter("!").array.to!string;
                            string mangle = type~"_"~__traits(identifier, A).pragmatize();
                            
                            if (retType.canFind("!"))
                                continue;
                           
                            static if (isStaticArray!(ReturnType!A))
                            {
                                Regex re = regex!(r"\[\d+\]").ctor();
                                string size;

                                if (re.matchFirst(retType) != null)
                                {
                                    size = re.matchFirst(retType)[0][1..$-1];
                                    retType = retType.replace(size, "[");
                                }
                                
                                file.append("    [DllImport(\"dll\")]\n    [return: MarshalAs(UnmanagedType.LPArray, SizeConst = "~size~")]\n    private extern static "~retType~" "~mangle~"_get(nint p)\n");
                                file.append("    [DllImport(\"dll\")]\n    [return: MarshalAs(UnmanagedType.LPArray, SizeConst = "~size~")]\n    private extern static "~retType~" "~mangle~"_set(nint p, [MarshalAs(UnmanagedType.LPArray, SizeConst = "~size~")] "~retType~" v)\n");
                                file.append("    public "~retType~" "~__traits(identifier, A)~" { get { return "~mangle~"_get(_ptr); } set { "~mangle~"_set(_ptr, value) } }\n");
                            }
                            else static if (isPointer!(ReturnType!A))
                                file.append("    public "~retType~" "~__traits(identifier, A)~" { get { return ("~retType~")Core.Importer.Call<nint>(\""~mangle~"_get\", _ptr); } set { Core.Importer.Call<nint>(\""~mangle~"_set\", _ptr, (nint)value); } }\n");
                            else
                                file.append("    public "~retType~" "~__traits(identifier, A)~" { get { return Core.Importer.Call<"~retType~">(\""~mangle~"_get\", _ptr); } set { Core.Importer.Call<"~retType~">(\""~mangle~"_set\", _ptr, value); } }\n");
                        }
                    }
                }
            }
            if (prev != null)
                prev.append("\n}");
        }
    }
}