/// Blitting of data from one type to another, cloning, and more
module tern.blit;

import std.conv;
import tern.traits;
import tern.meta;
import tern.memory;
import tern.serialization;

public:
static:
/**
 * Shallow clones a value.
 *
 * Params:
 *  val = The value to be shallow cloned.
 *
 * Returns:
 *  A shallow clone of the provided value.
 *
 * Example:
 * ```d
 * A a;
 * A b = a.dup();
 * ```
 */
pragma(inline)
@trusted T dup(T)(T val)
    if (!isArray!T && !isAssignableTo!(T, Object))
{
    return val;
}

/**
 * Deep clones a value.
 *
 * Params:
 *  val = The value to be deep cloned.
 *
 * Returns:
 *  A deep clone of the provided value.
 *
 * Example:
 * ```d
 * B a; // where B is a class containing indirection
 * B b = a.ddup();
 * ```
 */
pragma(inline)
@trusted T ddup(T)(T val)
    if (!isArray!T && !isAssociativeArray!T)
{
    static if (!hasIndirections!T || (isPointer!T || wrapsIndirection!T))
        return val;
    else
    {
        T ret = factory!T;
        static foreach (field; FieldNames!T)
        {
            static if (isMutable!(TypeOf!(T, field)))
            {
                static if (!hasIndirections!(TypeOf!(T, field)))
                    __traits(getMember, ret, field) = __traits(getMember, val, field);
                else
                    __traits(getMember, ret, field) = __traits(getMember, val, field).ddup();
            }
        }
        return ret;
    }
}

/// ditto
pragma(inline)
@trusted T ddup(T)(T arr)
    if (isArray!T && !isAssociativeArray!T)
{
    T ret;
    foreach (u; arr)
        ret ~= u.ddup();
    return ret;
}

/// ditto
pragma(inline)
@trusted T ddup(T)(T arr)
    if (isAssociativeArray!T)
{
    T ret;
    foreach (key, value; arr)
        ret[key.ddup()] = value.ddup();
    return ret;
}

/**
 * Duplicates `val` using soft[de]serialization, avoiding deep cloning.
 *
 * Params:
 *  val = The value to be duplicated.
 *
 * Returns:
 *  Clone of `val`
 */
pragma(inline)
@trusted T qdup(T)(T val)
{
    static if (is(T == class))
    {
        T ret = factory!T;
        copy(*cast(void**)val, *cast(void**)ret, __traits(classInstanceSize, T));
        return ret;
    }
    else static if (isArray!T)
    {
        size_t size = ElementType!T.sizeof * val.length;
        T ret = factory!T(size / ElementType!T.sizeof);
        copy(cast(void*)val.ptr, cast(void*)ret.ptr, size);
        return ret;
    }
    else
    {
        T ret = factory!T;
        copy(cast(void*)&val, cast(void*)&ret, T.sizeof);
        return ret;
    }
}

/**
 * Blits all members or array elements onto another value.
 * 
 * Params:
 *  lhs = Side to have values blitted to.
 *  rhs = Side to have values blitted from.
 */
pragma(inline)
@trusted void blit(T, F)(ref F lhs, T rhs)
    if ((!isIntrinsicType!F && !isIntrinsicType!T) || (isArray!T && isArray!F && !isAssociativeArray!T))
{
    static if (isArray!F && isArray!T)
    {
        if (!rhs.length == lhs.length)
            throw new Throwable("Cannot blit rhs to lhs when sizes do not match!");

        foreach (i, u; rhs)
            lhs[i] = cast(ElementType!F)u;
    }
    else
    {
        static foreach (field; FieldNames!F)
        {
            static if (hasMember!(T, field) && isMutable!(TypeOf!(T, field)) && isMutable!(TypeOf!(F, field)))
                __traits(getMember, lhs, field) = cast(TypeOf!(F, field))__traits(getMember, rhs, field);
        }
    }
}

/** 
 * Checks if `F` may be converted to `T`
 *
 * Params:
 *  F = Type to check if can convert from
 *  T = Type to check if can convert to
 *  EXPLICIT = Must be able to reinterpret cast? Defaults to false.
 */
public template canConv(F, T, bool EXPLICIT = false)
{
    enum canConv = 
    {
        static if (isImplement!(T, F))
            return true;

        static if (EXPLICIT && (is(T == class) != is(F == class)))
            return false;

        static if (isArray!F || isArray!T)
        {
            static if (isAssociativeArray!F || isAssociativeArray!T)
                throw new Throwable("Conversions between associative arrays are not supported!");
            else static if (isStaticArray!F == isStaticArray!T)
                return !EXPLICIT && (isArray!F == isArray!T) && canConv!(ElementType!F, ElementType!T, EXPLICIT);
            else static if ((isStaticArray!F && (!is(ElementType!F == ubyte) && !is(ElementType!F == byte) && !isSomeChar(ElementType!F))))
                static assert(0, "Casts from a static array to a non static array type must be from a byte type or char type, not "~F.stringof~"!");
        }

        static if (FieldNames!F.length > FieldNames!T.length && EXPLICIT)
            return false;

        static if (!isIntrinsicType!F && !isIntrinsicType!T)
        static foreach (i, field; FieldNames!F)
        {
            static if ((FieldNames!T.length <= i || FieldNames!T[i] != field || !is(TypeOf!(F, field) == TypeOf!(T, field))) && EXPLICIT)
                return false;
            else static if (!seqContains!(field, FieldNames!T) && !EXPLICIT)
                return false;
        }

        return true;
    }();
}

/**
 * Converts/casts `val` from type `F` to type `T`, returning ref if possible.
 *
 * Params:
 *  T = Type to convert/cast to.
 *  F = Type to convert/cast from.
 *  val = Value to convert/cast.
 */
pragma(inline)
@trusted auto ref T to(T, F)(ref F val)
{
    static if (isSomeString!T)
        return std.conv.to!string(val);
    else static if (isSomeString!F)
        return std.conv.to!F(val);
    else static if (canConv!(F, T, true))
        return val.reinterpret!T;
    else static if (canConv!(F, T))
        return val.conv!T;
    else
        static assert(0, "Cannot convert or cast from type "~F.stringof~" to type "~T.stringof~"!");
}

pragma(inline)
@trusted auto ref T to(T, F)(F val)
{
    static if (isSomeString!T)
        return std.conv.to!string(val);
    else static if (isSomeString!F)
        return std.conv.to!F(val);
    else static if (canConv!(F, T, true))
        return val.reinterpret!T;
    else static if (canConv!(F, T))
        return val.conv!T;
    else
        static assert(0, "Cannot convert or cast from type "~F.stringof~" to type "~T.stringof~"!");
}

/// ditto
pragma(inline)
@trusted auto ref T to(T, F)(F val, uint radix, LetterCase letterCase = LetterCase.upper)
{
    static if (isSomeString!T)
        return std.conv.to!string(val, radix, letterCase);
    else static if (isSomeString!F)
        return std.conv.to!F(val, radix, letterCase);
    else static if (canConv!(F, T, true))
        return val.reinterpret!T;
    else static if (canConv!(F, T))
        return val.conv!T;
    else
        static assert(0, "Cannot convert or cast from type "~F.stringof~" to type "~T.stringof~"!");
}

/** 
 * Casts `val` of type `F` to type `T`, returning ref if possible.
 *
 * Params:
 *  T = Type to cast to.
 *  F = Type to cast from.
 *  val = Value to reinterpret cast.
 *
 * Returns: 
 *  `val` as `T`
 */
pragma(inline)
@trusted auto ref T reinterpret(T, F)(F val)
{
    static if (__traits(compiles, { T _ = cast(T)val; }))
        return cast(T)val;
    else
        return *cast(T*)&val;
}

/** 
 * Converts `val` of type `F` to type `T`, returning ref if possible.
 *
 * Params:
 *  T = Type to convert to.
 *  F = Type to convert from.
 *  val = Value to convert.
 *
 * Returns: 
 *  `val` as `T`
 */
pragma(inline)
@trusted auto ref T conv(T, F)(F val)
    if (!isArray!T && !isAssociativeArray!T)
{
    T ret = factory!T;
    static foreach (field; FieldNames!F)
    {
        static if (hasMember!(T, field) && isMutable!(__traits(getMember, T, field)) && isMutable!(__traits(getMember, F, field)))
            __traits(getMember, ret, field) = cast(TypeOf!(T, field))__traits(getMember, val, field);
    }
    return ret;
}

/// ditto
pragma(inline)
@trusted auto ref T conv(T : U[], U, F)(F val)
    if (isArray!T && !isAssociativeArray!T)
{
    static if (isStaticArray!T)
        T ret;
    else
        T ret = new U[val.length];
    foreach (i, u; val)
        ret[i] = u.to!U;
    return ret;
}

/// Creates a new instance of `T` dynamically based on its traits, with optional construction args.
pragma(inline)
T factory(T, ARGS...)(ARGS args)
{
    static if (isDynamicArray!T)
    {
        static if (ARGS.length == 0)
            return new T(0);
        else
            return new T(args);
    }
    else static if (isReferenceType!T)
        return new T(args);
    else 
    {
        static if (ARGS.length != 0)
            return T(args);
        else
            return T.init;
    }
}

/**
 * Dynamically tries to load an element from `val`, this is useful for arbitrary range types.
 *
 * Params:
 *  index = Index to load from `val`
 *  val = The value to store the element into.
 *
 * Returns:
 *  The loaded element.
 */
pragma(inline)
ref auto loadElem(size_t index, T)(T val)
{
    static if (__traits(compiles, { auto _ = val[0]; }))
        return val[index];
    else
        static assert(T.stringof~" has no indexing!");
}

/**
 * Dynamically tries to store `ahs` into `val`, this is useful for arbitrary range types.
 *
 * Params:
 *  val = The value to store the element into.
 *  ahs = The value to be stored.
 *  index = Index to store `ahs` into.
 *
 * Returns:
 *  The stored element.
 *
 * Remarks:
 *  Resorts to a forced memory copy if no index assignment allowed. Here be dragons.
 */
pragma(inline)
auto storeElem(A, T)(T val, A ahs, size_t index)
{
    static if (__traits(compiles, { auto _ = (val[0] = ahs); }))
        return val[index] = ahs;
    else static if (__traits(compiles, { auto _ = val[0]; }))
    {
        copy(cast(void*)&ahs, cast(void*)&val[index], A.sizeof);
        return val[index];
    }
    else
        static assert(T.stringof~" has no indexing!");
}

/**
 * Dynamically tries toload a slice from `val`, this is useful for arbitrary range types.
 *
 * Params:
 *  val = The value to load the slice from.
 *
 * Returns:
 *  The loaded slice.
 */
pragma(inline)
auto loadSlice(T)(T val, size_t start, size_t end)
{
    static if (__traits(compiles, { auto _ = val[start..end]; }))
        return val[start..end];
    else
        static assert(T.stringof~" has no slicing!");
}

/**
 * Dynamically tries to store a slice into `val`, this is useful for arbitrary range types.
 *
 * Params:
 *  val = The value to store the slice into.
 *
 * Returns:
 *  The stored slice.
 *
 * Remarks:
 *  Resorts to a forced memory copy if no slicing assignment allowed. Here be dragons.
 */
pragma(inline)
auto storeSlice(A, T)(T val, A ahs, size_t start, size_t end) 
{
    static if (__traits(compiles, { auto _ = (val[start..end] = ahs); }))
        return val[start..end] = ahs;
    else static if (__traits(compiles, { auto _ = val[start]; }))
    {
        copy(cast(void*)ahs.ptr, cast(void*)&val[start], typeof(ahs[0]).sizeof * ahs.length);
        return val[start..end];
    }
    else
        static assert(T.stringof~" has no slicing!");
    return val;
}

/**
 * Dynamically tries to load the length of `val`, this is useful for arbitrary range types.
 *
 * Params:
 *  val = The value to load the length of.
 *
 * Remarks:
 *  Returns 1 if `T` has no length apparent.
 *
 * Returns:
 *  The loaded length.
 */
pragma(inline)
size_t loadLength(size_t DIM : 0, T)(T val)
{
    static if (__traits(compiles, { auto _ = val.opDollar!DIM; }))
        return val.opDollar!DIM;
    else static if (DIM == 0)
        return opDollar();
    else static if (isForward!T)
    {
        size_t length;
        foreach (u; val[DIM])
            length++;
        return length;
    }
    else
        return 1;
}

/// ditto
pragma(inline)
size_t loadLength(T)(T val)
{
    static if (__traits(compiles, { auto _ = val.opDollar(); }))
        return val.opDollar();
    else static if (__traits(compiles, { auto _ = val.length; }))
        return val.length;
    else static if (isForward!T)
    {
        size_t length;
        foreach (u; val)
            length++;
        return length;
    }
    else
        return 1;
}