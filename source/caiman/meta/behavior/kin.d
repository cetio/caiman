module caiman.meta.behavior.kin;

import std.traits;
import caiman.meta.traits;
import caiman.meta.algorithm;

/** 
 * Wraps a type with modified or optional fields.
 *
 * Remarks:
 * - Cannot wrap an intrinsic type (ie: `string`, `int`, `bool`)
 * - Accepts syntax `Kin!A(TYPE, NAME, CONDITION...)` or `Kin!A(TYPE, NAME...)` interchangably.
 * - Use `Kin.asOriginal()` to extract `T` in the original layout.
 * 
 * Examples:
 * ```d
 * struct A { int a; }
 * Kin!(A, long, "a", false, int, "b") k1; // a is still a int, but now a field b has been added
 * Kin!(A, long, "a", true, int, "b") k2; // a is now a long and a field b has been added
 * ```
 */
// TODO: Find a faster way to do this, do not regenerate every call
//       Apply changes on parent to self
public struct Kin(T, ARGS...)
    if (!isIntrinsicType!T)
{
    // Import all the types for functions so we don't have any import errors
    static foreach (func; FunctionNames!T)
    {
        static if (hasParents!(ReturnType!(__traits(getMember, T, func))))
            mixin("import "~moduleName!(ReturnType!(__traits(getMember, T, func)))~";");
    }

    // Define overrides (ie: Kin!A(uint, "a") where "a" is already a member of A)
    static foreach (field; FieldNames!T)
    {
        static foreach (i, ARG; ARGS)
        {
            static if (i % 3 == 1)
            {
                static assert(is(typeof(ARG) == string),
                    "Field name expected, found " ~ ARG.stringof); 

                static if (i == ARGS.length - 1 && ARG == field)
                {
                    static if (hasParents!(ARGS[i - 1]))
                        mixin("import "~moduleName!(ARGS[i - 1])~";");

                    mixin(fullyQualifiedName!(ARGS[i - 1])~" "~ARG~";");
                }
            }
            else static if (i % 3 == 2)
            {
                static assert(is(typeof(ARG) == bool) || isType!ARG,
                    "Type or boolean value expected, found " ~ ARG.stringof);
                    
                static if (is(typeof(ARG) == bool) && ARGS[i - 1] == field && ARG == true)
                {
                    static if (hasParents!(ARGS[i - 2]))
                        mixin("import "~moduleName!(ARGS[i - 2])~";");

                    mixin(fullyQualifiedName!(ARGS[i - 2])~" "~ARGS[i - 1]~";");
                }
                else static if (isType!ARG && is(typeof(ARGS[i - 1]) == string) && ARGS[i - 1] == field)
                {
                    static if (hasParents!(ARGS[i - 2]))
                        mixin("import "~moduleName!(ARGS[i - 2])~";");

                    mixin(fullyQualifiedName!(ARGS[i - 2])~" "~ARGS[i - 1]~";");
                }
            }/* 
            static if (i % 2 == 0)
            {
                static assert(isType!ARG,
                    "Type expected, found " ~ ARG.stringof); 
            }
            else static if (i % 2 == 1 && ARG == field)
            {
                static assert(is(typeof(ARG) == string),
                    "Field name expected, found " ~ ARG.stringof); 

                static if (hasParents!(ARGS[i - 1]))
                    mixin("import "~moduleName!(ARGS[i - 1])~";");

                mixin(fullyQualifiedName!(ARGS[i - 1])~" "~ARG~";");
            } */
        }

        static if (hasParents!(typeof(__traits(getMember, T, field))))
            mixin("import "~moduleName!(typeof(__traits(getMember, T, field)))~";");

        static if (!seqContains!(field, ARGS))
            mixin(fullyQualifiedName!(typeof(__traits(getMember, T, field)))~" "~field~";");
    }

    // Define all of the optional fields
    static foreach (i, ARG; ARGS)
    {
        static if (i % 3 == 1)
        {
            static assert(is(typeof(ARG) == string),
                "Field name expected, found " ~ ARG.stringof); 

            static if (i == ARGS.length - 1 && is(typeof(ARG) == string))
            {
                static if (hasParents!(ARGS[i - 1]))
                    mixin("import "~moduleName!(ARGS[i - 1])~";");

                static if (!seqContains!(ARG, FieldNames!T))
                    mixin(fullyQualifiedName!(ARGS[i - 1])~" "~ARG~";");
            }
        }
        else static if (i % 3 == 2)
        {
            static assert(is(typeof(ARG) == bool) || isType!ARG,
                "Type or boolean value expected, found " ~ ARG.stringof);
            
            static if (is(typeof(ARG) == bool) && ARG == true)
            {
                static if (hasParents!(ARGS[i - 2]))
                    mixin("import "~moduleName!(ARGS[i - 2])~";");

                static if (!seqContains!(ARGS[i - 1], FieldNames!T))
                    mixin(fullyQualifiedName!(ARGS[i - 2])~" "~ARGS[i - 1]~";");
            }
            else static if (isType!ARG && is(typeof(ARGS[i - 1]) == string))
            {
                static if (hasParents!(ARGS[i - 2]))
                    mixin("import "~moduleName!(ARGS[i - 2])~";");

                static if (!seqContains!(ARGS[i - 1], FieldNames!T))
                    mixin(fullyQualifiedName!(ARGS[i - 2])~" "~ARGS[i - 1]~";");
            }
        }
    }

    /**
     * Extracts the content of this Kin as `T` in its original layout.
     *
     * Returns:
     * Contents of this Kin as `T` in its original layout.
     */
    T asOriginal()
    {
        static if (is(T == class) || is(T == interface))
            T val = new T();
        else 
            T val;
        static if (hasChildren!T)
        static foreach (field; FieldNames!T)
        {
            __traits(getMember, val, field) = cast(typeof(__traits(getMember, val, field)))mixin(field);
        }
        return val;
        /* ubyte[] bytes;
        static foreach (field; FieldNames!T)
        {
            static if (staticIndexOf!(field, FieldNames!T) > 0)
            {
                // Account for alignment, this is a huge block of code but it really is just
                // (last offset - current offset) - last sizeof
                // (8 - 4) - 2 = 2 (padded by 2)
                bytes ~= new ubyte[
                    (__traits(getMember, T, field).offsetof - __traits(getMember, T, FieldNames!T[staticIndexOf!(field, FieldNames!T) - 1]).offsetof)
                     - typeof(__traits(getMember, T, FieldNames!T[staticIndexOf!(field, FieldNames!T) - 1])).sizeof];
            }

            {
                auto val = cast(typeof(__traits(getMember, T, field)))__traits(getMember, this, field);
                bytes ~= (cast(ubyte*)&val)[0..typeof(__traits(getMember, T, field)).sizeof];
            }
        }
        return *cast(T*)bytes.ptr; */
    }

    // Define the original type as an alias so operators & function calls work like normal
    alias asOriginal this;
}

unittest
{
    struct Person 
    {
        string name;
        int age;
    }

    Kin!(Person, long, "age", true, bool, "isStudent") modifiedPerson;

    modifiedPerson.name = "Bob";
    modifiedPerson.age = 30;
    modifiedPerson.isStudent = false;

    Person originalPerson = modifiedPerson.asOriginal();

    assert(modifiedPerson.name == "Bob");
    assert(modifiedPerson.age == 30);
    assert(is(typeof(modifiedPerson.age) == long));
    assert(modifiedPerson.isStudent == false);

    assert(originalPerson.name == "Bob");
    assert(originalPerson.age == 30);
}