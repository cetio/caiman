module caiman.digest.anura;

import caiman.digest;
import caiman.digest.circe;
import caiman.serialization;

public static @digester class Anura
{
public:
static:
pure:
    void encrypt(ref ubyte[] data, string key)
    {
        if (key.length != 128)
            throw new Throwable("Key is not 1024 bits!");

        key = cast(string)digest!Circe(cast(ubyte[])key[0..32], 0xFC2AB8FFFFF)~
            cast(string)digest!Circe(cast(ubyte[])key[32..64], 0xCCABB72DA)~
            cast(string)digest!Circe(cast(ubyte[])key[64..96], 0xABC0001700)~
            cast(string)digest!Circe(cast(ubyte[])key[96..128], 0x0000D7FFF);
        ulong rola = (cast(ulong*)key.ptr)[0] ^ (cast(ulong*)key.ptr)[1] | 32;
        ulong rolb = (cast(ulong*)key.ptr)[2] ^ (cast(ulong*)key.ptr)[3] | 32;
        ulong rolc = (cast(ulong*)key.ptr)[4] ^ (cast(ulong*)key.ptr)[5] | 32;
        ulong rold = (cast(ulong*)key.ptr)[6] ^ (cast(ulong*)key.ptr)[7] | 32;
        ulong roba = (cast(ulong*)key.ptr)[12] ^ (cast(ulong*)key.ptr)[8] | rola;
        ulong robb = (cast(ulong*)key.ptr)[13] ^ (cast(ulong*)key.ptr)[9] | rolb;
        ulong robc = (cast(ulong*)key.ptr)[14] ^ (cast(ulong*)key.ptr)[10] | rolc;
        ulong robd = (cast(ulong*)key.ptr)[15] ^ (cast(ulong*)key.ptr)[11] | rold;

        ulong[16] set = [
            rola,
            rolb,
            rolc,
            rold,
            roba,
            robb,
            robc,
            robd,
            rola ^ roba,
            rolb ^ robb,
            rolc ^ robc,
            rold ^ robd,
            rola * roba,
            rolb * robb,
            rolc * robc,
            rold * robd,
        ];

        vacpp(data, 8);

        foreach (i; 0..200)
        {
            ptrdiff_t factor = ((set[i % 16] * i) % ((data.length / 16_384) | 2)) | 1;  
            for (ptrdiff_t j = factor; j < data.length; j += factor)
            {
                ubyte b0 = data[j];
                data[j] = data[j - factor];
                data[j - factor] = b0;
            }
        }

        foreach (i; 0..2)
        {
            foreach (j, ref _b; cast(ulong[])data)
            {
                ptrdiff_t ri = ~i;
                ptrdiff_t si = i % 8;
                _b ^= (rola << si) ^ (ri * robd);
                _b ^= (rolb << si) ^ (ri * robc);
                _b ^= (rolc << si) ^ (ri * robb);
                _b ^= (rold << si) ^ (ri * roba);
            }

            foreach (j, ref b; (cast(ulong[])data)[1..$])
                b ^= data.ptr[j - 1];
        }
    }

    void decrypt(ref ubyte[] data, string key)
    {
        if (key.length != 128)
            throw new Throwable("Key is not 1024 bits!");

        key = cast(string)digest!Circe(cast(ubyte[])key[0..32], 0xFC2AB8FFFFF)~
            cast(string)digest!Circe(cast(ubyte[])key[32..64], 0xCCABB72DA)~
            cast(string)digest!Circe(cast(ubyte[])key[64..96], 0xABC0001700)~
            cast(string)digest!Circe(cast(ubyte[])key[96..128], 0x0000D7FFF);
        ulong rola = (cast(ulong*)key.ptr)[0] ^ (cast(ulong*)key.ptr)[1] | 32;
        ulong rolb = (cast(ulong*)key.ptr)[2] ^ (cast(ulong*)key.ptr)[3] | 32;
        ulong rolc = (cast(ulong*)key.ptr)[4] ^ (cast(ulong*)key.ptr)[5] | 32;
        ulong rold = (cast(ulong*)key.ptr)[6] ^ (cast(ulong*)key.ptr)[7] | 32;
        ulong roba = (cast(ulong*)key.ptr)[12] ^ (cast(ulong*)key.ptr)[8] | rola;
        ulong robb = (cast(ulong*)key.ptr)[13] ^ (cast(ulong*)key.ptr)[9] | rolb;
        ulong robc = (cast(ulong*)key.ptr)[14] ^ (cast(ulong*)key.ptr)[10] | rolc;
        ulong robd = (cast(ulong*)key.ptr)[15] ^ (cast(ulong*)key.ptr)[11] | rold;

        ulong[16] set = [
            rola,
            rolb,
            rolc,
            rold,
            roba,
            robb,
            robc,
            robd,
            rola ^ roba,
            rolb ^ robb,
            rolc ^ robc,
            rold ^ robd,
            rola * roba,
            rolb * robb,
            rolc * robc,
            rold * robd,
        ];

        if (data.length % 8 != 0)
            vacpp(data, 8);

        foreach_reverse (i; 0..2)
        {
            foreach_reverse (j, ref b; (cast(ulong[])data)[1..$])
                b ^= data.ptr[j - 1];

            foreach_reverse (j, ref _b; cast(ulong[])data)
            {
                ptrdiff_t ri = ~i;
                ptrdiff_t si = i % 8;
                _b ^= (rola << si) ^ (ri * robd);
                _b ^= (rolb << si) ^ (ri * robc);
                _b ^= (rolc << si) ^ (ri * robb);
                _b ^= (rold << si) ^ (ri * roba);
            }
        }

        foreach_reverse (i; 0..200)
        {
            ptrdiff_t factor = ((set[i % 16] * i) % ((data.length / 16_384) | 2)) | 1;  
            ptrdiff_t s = factor;
            for (; s < data.length; s += factor) { }
            s -= factor;
            for (; s >= factor; s -= factor)
            {
                ubyte b0 = data[s];
                data[s] = data[s - factor];
                data[s - factor] = b0;
            }
        }

        unvacpp(data);
    }
}