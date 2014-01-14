/*
     File: AppDelegate.m
 Abstract: Main app controller.
  Version: 1.0
 
 Disclaimer: IMPORTANT:  This Apple software is supplied to you by Apple
 Inc. ("Apple") in consideration of your agreement to the following
 terms, and your use, installation, modification or redistribution of
 this Apple software constitutes acceptance of these terms.  If you do
 not agree with these terms, please do not use, install, modify or
 redistribute this Apple software.
 
 In consideration of your agreement to abide by the following terms, and
 subject to these terms, Apple grants you a personal, non-exclusive
 license, under Apple's copyrights in this original Apple software (the
 "Apple Software"), to use, reproduce, modify and redistribute the Apple
 Software, with or without modifications, in source and/or binary forms;
 provided that if you redistribute the Apple Software in its entirety and
 without modifications, you must retain this notice and the following
 text and disclaimers in all such redistributions of the Apple Software.
 Neither the name, trademarks, service marks or logos of Apple Inc. may
 be used to endorse or promote products derived from the Apple Software
 without specific prior written permission from Apple.  Except as
 expressly stated in this notice, no other rights or licenses, express or
 implied, are granted by Apple herein, including but not limited to any
 patent rights that may be infringed by your derivative works or by other
 works in which the Apple Software may be incorporated.
 
 The Apple Software is provided by Apple on an "AS IS" basis.  APPLE
 MAKES NO WARRANTIES, EXPRESS OR IMPLIED, INCLUDING WITHOUT LIMITATION
 THE IMPLIED WARRANTIES OF NON-INFRINGEMENT, MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE, REGARDING THE APPLE SOFTWARE OR ITS USE AND
 OPERATION ALONE OR IN COMBINATION WITH YOUR PRODUCTS.
 
 IN NO EVENT SHALL APPLE BE LIABLE FOR ANY SPECIAL, INDIRECT, INCIDENTAL
 OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 INTERRUPTION) ARISING IN ANY WAY OUT OF THE USE, REPRODUCTION,
 MODIFICATION AND/OR DISTRIBUTION OF THE APPLE SOFTWARE, HOWEVER CAUSED
 AND WHETHER UNDER THEORY OF CONTRACT, TORT (INCLUDING NEGLIGENCE),
 STRICT LIABILITY OR OTHERWISE, EVEN IF APPLE HAS BEEN ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 
 Copyright (C) 2013 Apple Inc. All Rights Reserved.
 
 */

#import "AppDelegate.h"

#import "Common.h"
#import "HelperTool.h"

#include <ServiceManagement/ServiceManagement.h>

@interface AppDelegate () {
    AuthorizationRef    _authRef;
}

// for IB

@property (nonatomic, assign, readwrite) IBOutlet NSWindow *    window;
@property (nonatomic, assign, readwrite) IBOutlet NSTextView *  textView;

- (IBAction)installAction:(id)sender;
- (IBAction)getVersionAction:(id)sender;
- (IBAction)readLicenseAction:(id)sender;
- (IBAction)writeLicenseAction:(id)sender;
- (IBAction)bindAction:(id)sender;

// private stuff

@property (atomic, copy,   readwrite) NSData *                  authorization;
@property (atomic, strong, readwrite) NSXPCConnection *         helperToolConnection;

@end

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note
{
    #pragma unused(note)
    OSStatus                    err;
    AuthorizationExternalForm   extForm;
    
    assert(self.window != nil);

    // Create our connection to the authorization system.
    //
    // If we can't create an authorization reference then the app is not going to be able
    // to do anything requiring authorization.  Generally this only happens when you launch
    // the app in some wacky, and typically unsupported, way.  In the debug build we flag that 
    // with an assert.  In the release build we continue with self->_authRef as NULL, which will 
    // cause all authorized operations to fail.
    
    err = AuthorizationCreate(NULL, NULL, 0, &self->_authRef);
    if (err == errAuthorizationSuccess) {
        err = AuthorizationMakeExternalForm(self->_authRef, &extForm);
    }
    if (err == errAuthorizationSuccess) {
        self.authorization = [[NSData alloc] initWithBytes:&extForm length:sizeof(extForm)];
    }
    assert(err == errAuthorizationSuccess);
    
    // If we successfully connected to Authorization Services, add definitions for our default 
    // rights (unless they're already in the database).
    
    if (self->_authRef) {
        [Common setupAuthorizationRights:self->_authRef];
    }
    
    [self.window makeKeyAndOrderFront:self];
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender
{
    #pragma unused(sender)
    return YES;
}

- (void)logText:(NSString *)text
    // Logs the specified text to the text view.
{
    // any thread
    assert(text != nil);
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [[self.textView textStorage] appendAttributedString:[[NSAttributedString alloc] initWithString:text]];
    }];
}

- (void)logWithFormat:(NSString *)format, ...
    // Logs the formatted text to the text view.
{
    va_list ap;

    // any thread
    assert(format != nil);

    va_start(ap, format);
    [self logText:[[NSString alloc] initWithFormat:format arguments:ap]];
    va_end(ap);
}

- (void)logError:(NSError *)error
    // Logs the error to the text view.
{
    // any thread
    assert(error != nil);
    [self logWithFormat:@"error %@ / %d\n", [error domain], (int) [error code]];
}

- (void)connectToHelperTool
    // Ensures that we're connected to our helper tool.
{
    assert([NSThread isMainThread]);
    if (self.helperToolConnection == nil) {
        self.helperToolConnection = [[NSXPCConnection alloc] initWithMachServiceName:kHelperToolMachServiceName options:NSXPCConnectionPrivileged];
        self.helperToolConnection.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(HelperToolProtocol)];
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-retain-cycles"
        // We can ignore the retain cycle warning because a) the retain taken by the
        // invalidation handler block is released by us setting it to nil when the block 
        // actually runs, and b) the retain taken by the block passed to -addOperationWithBlock: 
        // will be released when that operation completes and the operation itself is deallocated 
        // (notably self does not have a reference to the NSBlockOperation).
        self.helperToolConnection.invalidationHandler = ^{
            // If the connection gets invalidated then, on the main thread, nil out our
            // reference to it.  This ensures that we attempt to rebuild it the next time around.
            self.helperToolConnection.invalidationHandler = nil;
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                self.helperToolConnection = nil;
                [self logText:@"connection invalidated\n"];
            }];
        };
        #pragma clang diagnostic pop
        [self.helperToolConnection resume];
    }
}

- (void)connectAndExecuteCommandBlock:(void(^)(NSError *))commandBlock
    // Connects to the helper tool and then executes the supplied command block on the 
    // main thread, passing it an error indicating if the connection was successful.
{
    assert([NSThread isMainThread]);
    
    // Ensure that there's a helper tool connection in place.
    
    [self connectToHelperTool];

    // Run the command block.  Note that we never error in this case because, if there is 
    // an error connecting to the helper tool, it will be delivered to the error handler 
    // passed to -remoteObjectProxyWithErrorHandler:.  However, I maintain the possibility 
    // of an error here to allow for future expansion.

    commandBlock(nil);
}

#pragma mark * IB Actions

- (IBAction)installAction:(id)sender
    // Called when the user clicks the Install button.  This uses SMJobBless to install 
    // the helper tool.
{
    #pragma unused(sender)

    Boolean             success;
    CFErrorRef          error;
    
    success = SMJobBless(
        kSMDomainSystemLaunchd,
        CFSTR("com.example.apple-samplecode.EBAS.HelperTool"),
        self->_authRef,
        &error
    );

    if (success) {
        [self logWithFormat:@"success\n"];
    } else {
        [self logError:(__bridge NSError *) error];
        CFRelease(error);
    }
}

- (IBAction)getVersionAction:(id)sender
    // Called when the user clicks the Get Version button.  This is the simplest form of
    // NSXPCConnection request because it doesn't require any authorization.
{
    #pragma unused(sender)
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [self logError:connectError];
        } else {
            [[self.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                [self logError:proxyError];
            }] getVersionWithReply:^(NSString *version) {
                [self logWithFormat:@"version = %@\n", version];
            }];
        }
    }];
}

- (IBAction)readLicenseAction:(id)sender
    // Called when the user clicks the Read License button.  This is an example of an
    // authorized command that, by default, can be done by anyone.
{
    #pragma unused(sender)
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [self logError:connectError];
        } else {
            [[self.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                [self logError:proxyError];
            }] readLicenseKeyAuthorization:self.authorization withReply:^(NSError * commandError, NSString * licenseKey) {
                if (commandError != nil) {
                    [self logError:commandError];
                } else {
                    [self logWithFormat:@"license = %@\n", licenseKey];
                }
            }];
        }
    }];
}

- (IBAction)writeLicenseAction:(id)sender
    // Called when the user clicks the Write License button.  This is an example of an
    // authorized command that, by default, can only be done by administrators.
{
    #pragma unused(sender)
    NSString *  licenseKey;
    
    // Generate a new random license key so that we can see things change.
    
    licenseKey = [[NSUUID UUID] UUIDString];

    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [self logError:connectError];
        } else {
            [[self.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                [self logError:proxyError];
            }] writeLicenseKey:licenseKey authorization:self.authorization withReply:^(NSError *error) {
                if (error != nil) {
                    [self logError:error];
                } else {
                    [self logWithFormat:@"success\n"];
                }
            }];
        }
    }];
}

- (IBAction)bindAction:(id)sender
    // Called when the user clicks the Bind button.  This is an example of an authorized
    // command that returns file descriptors.
{
    #pragma unused(sender)
    [self connectAndExecuteCommandBlock:^(NSError * connectError) {
        if (connectError != nil) {
            [self logError:connectError];
        } else {
            [[self.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
                [self logError:proxyError];
            }] bindToLowNumberPortAuthorization:self.authorization withReply:^(NSError *error, NSFileHandle *ipv4Handle, NSFileHandle *ipv6Handle) {
                if (error != nil) {
                    [self logError:error];
                } else {
                    // Each of these NSFileHandles has the close-on-dealloc flag set.  If we wanted to hold
                    // on to the underlying descriptor for a long time, we need to call <x-man-page://dup2>
                    // on that descriptor to get our our descriptor that persists beyond the lifetime of
                    // the NSFileHandle.  In this example app, however, we just print the descriptors, which
                    // we can do without any complications.
                    [self logWithFormat:@"IPv4 = %d, IPv6 = %u\n",
                        [ipv4Handle fileDescriptor],
                        [ipv6Handle fileDescriptor]
                    ];
                }
            }];
        }
    }];
}

@end
