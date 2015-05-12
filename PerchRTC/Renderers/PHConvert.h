//
//  PHConvert.h
//  PerchRTC
//
//  Created by Christopher Eagleston on 2015-05-09.
//  Copyright (c) 2015 Perch Communications. All rights reserved.
//

#ifndef __PerchRTC__PHConvert__
#define __PerchRTC__PHConvert__

#include <stdio.h>

void ConvertPlanarUVToPackedRow(const uint8_t *srcA, const uint8_t *srcB, uint8_t *dstAB, int dstABLength);

#endif /* defined(__PerchRTC__PHConvert__) */
