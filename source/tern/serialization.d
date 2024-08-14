/// General-purpose binary serializer and deserializer for arbitrary data types.
module tern.serialization;

// TODO: Json, yaml, etc.
public import tern.object : Endianness;
import tern.object : factory, makeEndian;
import tern.traits;

public:
static:
pure:
/**
 * Recursively serializes `val` with the provided endianness.
 *
 * Params:
 *  RAW = If true, arrays won't have their length serialized. Defaults to false.
 *  val = The value to be serialized.
 *  endianness = The endianness to be serialized to. Defaults to native.
 * 
 * Returns:
 *  Serialized byte array.
 */
@trusted ubyte[] serialize(bool RAW = false, T)(T val, Endianness endianness = Endianness.Native)
{
    static if (isArray!T)
    {
        ubyte[] bytes;
        static if (!RAW)
            bytes ~= val.length.makeEndian(endianness).serialize!RAW();
            
        foreach (u; val)
            bytes ~= u.makeEndian(endianness).serialize!RAW();
        return bytes;
    }
    else static if (hasChildren!T)
    {
        ubyte[] bytes;
        foreach (field; Fields!T)
        {
            static if (!isEnum!(getChild!(T, field)))
                bytes ~= __traits(getMember, val, field).makeEndian(endianness).serialize!RAW();
        }
        return bytes;
    }
    else
    {
        T t = val.makeEndian(endianness);
        return (cast(ubyte*)&t)[0..T.sizeof].dup;
    }
}

/**
 * Recursively deserializes `val` with the provided endianness.
 *
 * Params:
 *  T = Type to deserialize to.
 *  bytes = The bytes to be deserialized.
 *  len = The length of the deserialized data as it were if a `T[]`. Defaults to -1
 *  endianness = The endianness to be serialized to. Defaults to native.
 * 
 * Returns:
 *  The deserialized value of `T`.
 */
@trusted deserialize(T, B)(B bytes, size_t len = -1, Endianness endianness = Endianness.Native)
    if (isDynamicArray!B && (is(ElementType!B == ubyte) || is(ElementType!B == byte)))
{
    T ret = factory!T;
    size_t offset;
    static if (isArray!T)
    {
        static if (isDynamicArray!T && isMutable!(ElementType!T))
        {
            if (len == -1)
                len = deserialize!size_t(bytes[offset..(offset += size_t.sizeof)]).makeEndian(endianness);
            ret = new T(len);
        }
        else static if (isStaticArray!T)
        {
            len = Length!T;
        }

        if (bytes.length < len * ElementType!T.sizeof)
            bytes ~= new ubyte[(len * ElementType!T.sizeof) - bytes.length];

        foreach (i; 0..len)
        static if (isMutable!(ElementType!T))
            ret[i] = bytes[offset..(offset += ElementType!T.sizeof)].deserialize!(ElementType!T).makeEndian(endianness);
        else
            ret ~= bytes[offset..(offset += ElementType!T.sizeof)].deserialize!(ElementType!T).makeEndian(endianness);

        return ret;
    }
    else static if (hasChildren!T)
    {
        if (bytes.length < sizeof!T)
            bytes ~= new ubyte[sizeof!T - bytes.length];

        foreach (field; Fields!T)
        {
            static if (isMutable!(getChild!(T, field)))
                __traits(getMember, ret, field) = deserialize!(TypeOf!(T, field))(bytes[offset..(offset += TypeOf!(T, field).sizeof)]).makeEndian(endianness);
        }
        return ret;
    }
    else
    {
        if (bytes.length < T.sizeof)
            bytes ~= new ubyte[T.sizeof - bytes.length];

        return (*cast(T*)bytes[offset..(offset += T.sizeof)].ptr).makeEndian(endianness);
    }
}

/**
 * Pads `data` right to `size` with zeroes.
 *
 * Params:
 *  data = The bytes to be padded.
 *  size = The size of `data` after padding.
 */
void sachp(ref ubyte[] data, size_t size)
{
    data ~= new ubyte[data.length % size == 0 ? 0 : size - (data.length % size)];
}

/**
 * Pads `data` right to `size` with metadata after for later unpadding.
 *
 * Params:
 *  data = The bytes to be padded.
 *  size = The size of `data` after padding.
 */
void vacpp(ref ubyte[] data, size_t size)
{
    if (size < 8 || size > 2 ^^ 24)
        throw new Throwable("Invalid vacpp padding size!");

    size_t margin = size - (data.length % size) + size;
    data ~= new ubyte[margin == size ? 0 : margin];
    data[$-5..$] = cast(ubyte[])"VacPp";
    data[$-8..$-5] = margin.serialize!true()[0..3];
}

/**
 * Unpads `data` assuming it was padded previously with `vacpp`.
 *
 * Params:
 *  data = The bytes to be unpadded.
 */
void unvacpp(ref ubyte[] data) 
{
    if (data.length < 8)
        throw new Throwable("Invalid data length for vacpp!");

    if (data[$-5..$] != cast(ubyte[])"VacPp")
        throw new Throwable("Invalid padding signature in vacpp!");

    uint margin = data[$-8..$-5].deserialize!uint();
    data = data[0..(data.length - margin)];
}

/**
 * Encodes `val` as a variable length integer.
 *
 * Params:
 *  val = The integer to be encoded.
 *
 * Returns:
 *  Array of bytes representing `val` in its variable length form.
 */
ubyte[] varEncode(T)(T val)
    if (isIntegral!T)
{
    if (val == 0)
        return [0];

    val <<= 3;
    ubyte[] bytes;
    while (val > 0)
    {
        bytes ~= cast(ubyte)(val & 0xFF);
        val >>= 8;
    }
    // Encode the number of bytes to read after this as the first 3 bits
    bytes[0] |= ((bytes.length - 1) & 0b0000_0111);
    return bytes;
}

/**
 * Decodes `bytes` as a variable length integer into a ulong.
 *
 * Params:
 *  bytes = Bytes representing a variable length integer.
 * 
 * Returns:
 *  A ulong as `bytes` decoded.
 */
ulong varDecode(ubyte[] bytes)
{
    ulong ret;
    // Extract the number of bytes used to represent the value from the first byte
    ubyte numBytes = (bytes[0] & 0b0000_0111) + 1;
    foreach_reverse (b; bytes[1..numBytes])
        ret = (ret << 8) | b;
    ret = (ret << 8) | bytes[0];
    return ret >> 3;
}

/+
// read T
// - count
// - condition
// - prefixed (arrays)
// write T
// - count
// - condition
// - prefixed (arrays)
// align
// - bound
// step
// - to
// - by
// - until
// run
// - function
// - parameters

// eval stack
// block reference

package enum BlockFlags : ubyte
{
    Prefixed = 1 << 0,
    NoForward = 1 << 1,
    Success = 1 << 2,
    Fail = 1 << 3,
}

package struct Read(T)
{
    BlockFlags flags;
    size_t count;
}

package struct Write(T)
{
    bool condition;
    size_t count;
    bool prefix;
}

package struct Align
{
    bool condition;
    size_t bound;
}

package struct Step(T)
{
    bool condition;
    union
    {
        size_t to;
        Read!T until;
    }
}

package struct Run(F)
{
    bool condition;
}

public:
T read(T, ARGS...)(ARGS args)
{

}+/