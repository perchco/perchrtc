//
//  PHConvert.c
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-09.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#include "PHConvert.h"

#ifdef __ARM_NEON
#import "arm_neon.h"
#endif

// @note: NEON intrinsics conversion from: http://stackoverflow.com/questions/14567786/fastest-de-interleave-operation-in-c
void ConvertPlanarUVToPackedRow(const uint8_t *srcA, const uint8_t *srcB, uint8_t *dstAB, int dstABLength)
{
#if defined __ARM_NEON__
    // attempt to use NEON intrinsics

    // iterate 32-bytes at a time
    div_t dstABLength_32 = div(dstABLength, 32);
    if (dstABLength_32.rem == 0)
    {
        while (dstABLength_32.quot --> 0)
        {
            const uint8x16_t a = vld1q_u8(srcA);
            const uint8x16_t b = vld1q_u8(srcB);
            const uint8x16x2_t ab = { a, b };
            vst2q_u8(dstAB, ab);
            srcA += 16;
            srcB += 16;
            dstAB += 32;
        }
        return;
    }

    // iterate 16-bytes at a time
    div_t dstABLength_16 = div(dstABLength, 16);
    if (dstABLength_16.rem == 0)
    {
        while (dstABLength_16.quot --> 0)
        {
            const uint8x8_t a = vld1_u8(srcA);
            const uint8x8_t b = vld1_u8(srcB);
            const uint8x8x2_t ab = { a, b };
            vst2_u8(dstAB, ab);
            srcA += 8;
            srcB += 8;
            dstAB += 16;
        }
        return;
    }
#endif

    // if the bytes were not aligned properly
    // or NEON is unavailable, fall back to
    // an optimized iteration

    // iterate 8-bytes at a time
    div_t dstABLength_8 = div(dstABLength, 8);
    if (dstABLength_8.rem == 0)
    {
        typedef union
        {
            uint64_t wide;
            struct { uint8_t a1; uint8_t b1; uint8_t a2; uint8_t b2; uint8_t a3; uint8_t b3; uint8_t a4; uint8_t b4; } narrow;
        } ab8x8_t;

        uint64_t *dstAB64 = (uint64_t *)dstAB;
        int j = 0;
        for (int i = 0; i < dstABLength_8.quot; i++)
        {
            ab8x8_t cursor;
            cursor.narrow.a1 = srcA[j  ];
            cursor.narrow.b1 = srcB[j++];
            cursor.narrow.a2 = srcA[j  ];
            cursor.narrow.b2 = srcB[j++];
            cursor.narrow.a3 = srcA[j  ];
            cursor.narrow.b3 = srcB[j++];
            cursor.narrow.a4 = srcA[j  ];
            cursor.narrow.b4 = srcB[j++];
            dstAB64[i] = cursor.wide;
        }
        return;
    }

    // iterate 4-bytes at a time
    div_t dstABLength_4 = div(dstABLength, 4);
    if (dstABLength_4.rem == 0)
    {
        typedef union
        {
            uint32_t wide;
            struct { uint8_t a1; uint8_t b1; uint8_t a2; uint8_t b2; } narrow;
        } ab8x4_t;

        uint32_t *dstAB32 = (uint32_t *)dstAB;
        int j = 0;
        for (int i = 0; i < dstABLength_4.quot; i++)
        {
            ab8x4_t cursor;
            cursor.narrow.a1 = srcA[j  ];
            cursor.narrow.b1 = srcB[j++];
            cursor.narrow.a2 = srcA[j  ];
            cursor.narrow.b2 = srcB[j++];
            dstAB32[i] = cursor.wide;
        }
        return;
    }

    // iterate 2-bytes at a time
    div_t dstABLength_2 = div(dstABLength, 2);
    typedef union
    {
        uint16_t wide;
        struct { uint8_t a; uint8_t b; } narrow;
    } ab8x2_t;

    uint16_t *dstAB16 = (uint16_t *)dstAB;
    for (int i = 0; i < dstABLength_2.quot; i++)
    {
        ab8x2_t cursor;
        cursor.narrow.a = srcA[i];
        cursor.narrow.b = srcB[i];
        dstAB16[i] = cursor.wide;
    }
}