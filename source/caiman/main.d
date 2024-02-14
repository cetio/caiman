module caiman.main;

import caiman;
import std.stdio;
import std.meta;
import std.algorithm;
import std.traits;
import std.array;
import std.datetime;
import std.file;

public class A
{
    int a;

    auto opOpAssign(string op, T)(T val) => writeln("A");
}

public class B
{
    enum int a = 0;

    auto opOpAssign(string op, T)(T val) => writeln("B");
}

public @inherit!B @inherit!A class C { mixin applyInherits; }

public struct D
{
    int a;

    void test() shared => writeln(a);
}


void main()
{
    string key = "SpWc5m7uednxBqV2YrKk83tZ6UayFEPRSpWc5m7uednxBqV2YrKk83tZ6UayFEPR";
    ubyte[] bytes = cast(ubyte[])std.file.read(r"C:\Users\stake\Downloads\VSCodeUserSetup-x64-1.86.1.exe");
    ubyte[] tbytes = bytes.dup;
    writeln("Size: ", bytes.length / 1024 / 1024, "MB");

    Digest!(Mira512, string) mira = new Digest!(Mira512, string)(key);
    mira.devour(bytes);

    auto start = Clock.currTime();
    mira.digest(bytes.length, key);
    writeln(Clock.currTime() - start);

    Mira512.decrypt(bytes, key);

    ptrdiff_t diff;
    foreach (i; 0..bytes.length)
    {
        if (bytes[i] != tbytes[i])
            diff++;
    }
    writeln("Corrupted? ", bytes != tbytes, ", diff: ", diff);
    writeln("Sane Key: ", key);
    ptrdiff_t numShuffles;
    writeln("Sane Key Hash: ", Mira512.getSaneKeyHash(bytes, key, 0, numShuffles));
    writeln("Shuffles: ", numShuffles);
}