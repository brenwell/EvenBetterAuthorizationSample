/*
     File: XPCService.m
 Abstract: The main object in the XPC service.
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

#import "XPCService.h"

#import "Common.h"
#import "HelperTool.h"

#include <ServiceManagement/ServiceManagement.h>

@interface XPCService () <NSXPCListenerDelegate, XPCServiceProtocol>

@property (atomic, strong, readonly ) NSXPCListener *    listener;
@property (atomic, copy,   readonly ) NSData *           authorization;
@property (atomic, strong, readonly ) NSOperationQueue * queue;

@property (atomic, strong, readwrite) NSXPCConnection *  helperToolConnection;      // only accessed or modified by operations on self.queue

@end

@implementation XPCService {
    AuthorizationRef    _authRef;
}

- (id)init
{
    self = [super init];
    if (self != nil) {
        OSStatus                    err;
        AuthorizationExternalForm   extForm;
        
        self->_listener = [NSXPCListener serviceListener];
        assert(self->_listener != nil);     // this code must be run from an XPC service

        self->_listener.delegate = self;

        err = AuthorizationCreate(NULL, NULL, 0, &self->_authRef);
        if (err == errAuthorizationSuccess) {
            err = AuthorizationMakeExternalForm(self->_authRef, &extForm);
        }
        if (err == errAuthorizationSuccess) {
            self->_authorization = [[NSData alloc] initWithBytes:&extForm length:sizeof(extForm)];
        }
        assert(err == errAuthorizationSuccess);
        
        self->_queue = [[NSOperationQueue alloc] init];
        [self->_queue setMaxConcurrentOperationCount:1];
    }
    return self;
}

- (void)dealloc
{
    if (self->_authRef != NULL) {
        (void) AuthorizationFree(self->_authRef, 0);
    }
}

- (void)run
{
    [self.listener resume];     // never comes back
}

- (BOOL)listener:(NSXPCListener *)listener shouldAcceptNewConnection:(NSXPCConnection *)newConnection
    // Called by our XPC listener when a new connection comes in.  We configure the connection
    // with our protocol and ourselves as the main object.
{
    assert(listener == self.listener);
    #pragma unused(listener)
    assert(newConnection != nil);

    newConnection.exportedInterface = [NSXPCInterface interfaceWithProtocol:@protocol(XPCServiceProtocol)];
    newConnection.exportedObject = self;
    [newConnection resume];
    
    return YES;
}

- (void)installHelperToolWithReply:(void(^)(NSError * error))reply
    // Part of XPCServiceProtocol.  Called by the app to install the helper tool.
{
    Boolean             success;
    CFErrorRef          error;
    
    success = SMJobBless(
        kSMDomainSystemLaunchd,
        CFSTR("com.example.apple-samplecode.EBAS.HelperTool"),
        self->_authRef,
        &error
    );

    if (success) {
        reply(nil);
    } else {
        assert(error != NULL);
        reply((__bridge NSError *) error);
        CFRelease(error);
    }
}

- (void)setupAuthorizationRights
    // Part of XPCServiceProtocol.  Called by the app at startup time to set up our 
    // authorization rights in the authorization database.
{
    [Common setupAuthorizationRights:self->_authRef];
}

- (void)connectWithEndpointAndAuthorizationReply:(void(^)(NSXPCListenerEndpoint * endpoint, NSData * authorization))reply
    // Part of XPCServiceProtocol.  Called by the app to get an endpoint that's 
    // connected to the helper tool.  This a also returns the XPC service's authorization 
    // reference so that the app can pass that to the requests it sends to the helper tool.  
    // Without this authorization will fail because the app is sandboxed.
{
    // Because we access helperToolConnection, we have to run on the operation queue.
    
    [self.queue addOperationWithBlock:^{

        // Create our connection to the helper tool if it's not already in place.
        
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
                // If the connection gets invalidated then, on our operation queue thread, nil out our
                // reference to it.  This ensures that we attempt to rebuild it the next time around.
                self.helperToolConnection.invalidationHandler = nil;
                [self.queue addOperationWithBlock:^{
                    self.helperToolConnection = nil;
                    NSLog(@"connection invalidated");
                }];
            };
            #pragma clang diagnostic pop
            [self.helperToolConnection resume];
        }

        // Call the helper tool to get the endpoint we need.
        
        [[self.helperToolConnection remoteObjectProxyWithErrorHandler:^(NSError * proxyError) {
            NSLog(@"connect failed: %@ / %d", [proxyError domain], (int) [proxyError code]);
            reply(nil, nil);
        }] connectWithEndpointReply:^(NSXPCListenerEndpoint *replyEndpoint) {
            reply(replyEndpoint, self.authorization);
        }];
    }];
}

@end
