module caiman.formats.pe.dotnet.tables.genericparam;

public struct GenericParam
{
public:
final:
    ushort number;
    ushort flags;
    uint owner;
    ubyte[] name;
}