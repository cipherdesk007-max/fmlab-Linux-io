//
//  main.m
//  iSH
//
//  Created by Theodore Dubois on 10/17/17.
//

#import <UIKit/UIKit.h>
#import "AppDelegate.h"
#import "ExceptionExfiltrator.h"
#ifdef LINUXRUNNER
#import "LinuxRunner/BootLog.h"
#include "FMLAB/FMLABLingua.inc.m"   // FMLAB: traduzione italiana della parte Objective-C
static void LRUncaughtException(NSException *exception) {
    LRBootEvent("uncaught Objective-C exception; retaining upstream termination behavior");
    iSHExceptionHandler(exception);
}
#endif

int main(int argc, char * argv[]) {
#ifdef LINUXRUNNER
    NSSetUncaughtExceptionHandler(LRUncaughtException);
#else
    NSSetUncaughtExceptionHandler(iSHExceptionHandler);
#endif
    @autoreleasepool {
#ifdef LINUXRUNNER
        LRStartupInitialize();
        // FMLAB: lingua dell'app. Di base inglese; l'italiano si sceglie in Impostazioni → FMLAB → Language.
        {
            NSUserDefaults *d = NSUserDefaults.standardUserDefaults;
            NSString *lingua = [d stringForKey:@"FMLAB.lingua"];
            if (lingua == nil) { lingua = @"en"; [d setObject:lingua forKey:@"FMLAB.lingua"]; }
            [d setObject:@[lingua] forKey:@"AppleLanguages"];
            FMLABAttivaTraduzione(lingua);   // traduce anche schermo del desktop, menu e avvisi
        }
        LRBootEvent("application initialization: entering UIApplicationMain");
#endif
        return UIApplicationMain(argc, argv, nil, NSStringFromClass([AppDelegate class]));
    }
}
