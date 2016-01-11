//
//  PHLog.h
//
//  Created by Christopher Eagleston on 2016-01-10.
//
//

#import <CocoaLumberjack/DDLog.h>

#ifdef DEBUG
static const int ddLogLevel = LOG_LEVEL_VERBOSE;
#else
static const int ddLogLevel = LOG_LEVEL_WARN;
#endif
