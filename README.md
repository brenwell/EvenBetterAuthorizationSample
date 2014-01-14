Read Me About EvenBetterAuthorizationSample
===========================================
1.0

EvenBetterAuthorizationSample shows how to factor privileged operations out of your application and into a privileged helper tool that is run by launchd.  When your application must do privileged operations, Apple recommends that you use this approach because it improves security by:

o ensuring that your privileged code inherits a trusted environment

o reducing the amount of code that runs with elevated privileges

o making your privileged code easier to audit for security

EvenBetterAuthorizationSample uses modern technology--namely SMJobBless, introduced in 10.6, and NSXPCConnection, introduced in 10.8--to radically reduce the code needed to support privileged helper tools as compared to older samples.

You should study this sample if your application needs ongoing access to privileged operations.  For example, if you're writing a packet capture tool (where the underlying technology, BPF, is only available to a privileged process) and you want to make it available to users in a controlled and configurable fashion (determined by an authorization right), EvenBetterAuthorizationSample is for you.  On the other hand, if your application needs elevated privileges for a one-off task, such as installing or uninstalling, you should consider alternative techniques, such as an installer package.

EvenBetterAuthorizationSample requires OS X 10.8 or later, which is when NSXPCConnection was introduced.

Packing List
------------
The sample contains the following items:

o Read Me About EvenBetterAuthorizationSample.txt -- This file.

o EvenBetterAuthorizationSample.xcodeproj -- An Xcode project for the program.

o build -- A pre-built version of the above.

o App -- A directory containing code for the standard application.

o App-Sandboxed -- A directory containing code for the sandboxed application.  This uses a non-sandboxed XPC service to talk to the privileged helper tool.

IMPORTANT: This technique is useful if you're deploying your app outside of the Mac App Store and want to opt in to sandboxing.  It won't help you if you plan to deploy via the Mac App Store; Mac App Store apps are not allowed to use elevated privileges under any circumstances (see clause 2.27 of the "Mac App Store Review Guidelines").

<https://developer.apple.com/appstore/mac/resources/approval/guidelines.html>

o Common -- A directory containing code and resources shared between the application and the privileged helper tool.

o HelperTool -- A directory containing code for the helper tool.

o Uninstall.sh -- A shell script to uninstall the privileged helper tool and remove its items from the authorization database.  This is helpful during development, because it allows you to reset your system to a known state.

Within the "App" directory you'll find:

o App-Info.plist - The Info.plist for the application itself.  Pay particular attention to the SMPrivilegedExecutables property.

o AppDelegate.{h,m} -- The application delegate, where all the interesting application code resides.

o Base.lproj -- A directory containing the app's .xib file.

o {en,de}.lproj -- A directory containing the localized strings for English and German, respectively.

Note: See the discussion of localization in the "Notes" section, below.

o main.m -- Standard application boilerplate.

You'll find a similar structure within the "App-Sandboxed" directory.  The main difference is the addition of an "XPCService" directory, which contains:

o XPCService-Info.plist -- The Info.plist for the XPC service.  Pay particular attention to the SMPrivilegedExecutables property.

o main.m -- The main function for the XPC service.  This simply instantiates and calls the XPCService class.

o XPCService.{h,m} -- The header file contains the definitions required to call the XPC service.  The implementation file contains the code that implements this service.

Within the "Common" directory you'll find:

o Common.{h,m} -- Code that's shared between the application and the helper tool.  Specifically, this is where all information about the privileged operations implemented by the privileged helper tool is stored, including the declaration of the protocol used to drive the NSXPCConnection (HelperToolProtocol).

o {en,de}.lproj -- A directory containing the localized strings for the authorization rights, in English and German respectively.

Within the "HelperTool" directory you'll find:

o HelperTool-Info.plist -- The Info.plist for the helper tool.  Pay particular attention to the SMAuthorizedClients property.  When you build the project this property list is placed in a custom section within the helper tool executable.  See the Other Linker Flags (OTHER_LDFLAGS) build setting in the "HelperTool" target.

o HelperTool-Launchd.plist -- The launchd property list for the help tool.  See <x-man-page://5/launchd.plist> for details.  When you build the project this property list is placed in a custom section within the helper tool executable.  See the Other Linker Flags (OTHER_LDFLAGS) build setting in the "HelperTool" target.

o HelperTool.{h,m} -- The main class of the helper tool; all the interesting helper tool code resides here.

o main.m -- A main function that instantiates a HelperTool object and then runs it.

Using the Sample
----------------
To test the sample, just launch the pre-built binary.  You'll see a window with four buttons:

o Install -- Click this button to install the privileged helper tool; this will prompt you for an admin password.

o Get Version -- Click this to get the version number of the currently installed helper tool.  There is no authorization right for this operation.  All users can do it all the time.

o Read License -- Click this to ask the privileged helper tool to return the make-believe software license key.

The authorization right for this operation defaults to allowing anyone to do it, meaning that any user on the system can run the make-believe app controlled by this license key.  However, a system admin can change this default by editing the right specification for the "com.example.apple-samplecode.EBAS.readLicenseKey" right in the authorization policy database (currently "/etc/authorization").  For example, the system admin could change this right so that only certain users can read the license key and thus run the app.

o Write License -- Click this to ask the privileged helper tool to save the make-believe software license key.

The authorization right for this operation defaults to requiring admin authentication.  However, a system admin can change this default by editing the right specification for the "com.example.apple-samplecode.EBAS.writeLicenseKey" right in the authorization policy database.

o Bind -- Click this to ask the privileged helper tool to open IPv4 and IPv6 TCP sockets bound to port 80 and return the descriptors to the application.  An app might use an operation like this to enable an in-app web server.

The authorization right for this operation defaults to allowing anyone to do it.  Again, a system admin can change this default by editing the right specification in the authorization database, this time for the "com.example.apple-samplecode.EBAS.startWebService" right.

Building the Sample
-------------------
The sample was built using Xcode 4.6.3 on OS X 10.8.4.  It assumes you're using an Apple-issued Developer ID.  If you don't have a Developer ID, you should get one before proceeding.

<https://developer.apple.com/resources/developer-id/>

Before you build you need to adjust some Info.plist values to match your Developer ID.  Specifically, search the entire sample code directory hierarchy for all instances of "SKMME9E2Y8" and replace it with the User ID value from your "Developer ID Application" certificate.

WARNING: There's more than one instance of this string, in more than one file.

Once you've done that you should be able to just open the project and choose Product > Build.  This will build the "App" target, which builds the tool courtesy of a target dependency on the "HelperTool" target.  The final application will end up in the build directory, as per normal, with a copy of the tool embedded within its package.

You can also select the "App-Sandboxed" scheme to build the sandboxed version of the app, along with its associated XPC service and helper tool.

How it Works
------------
EvenBetterAuthorizationSample uses four critical technologies:

o launchd -- launchd manages daemons on OS X.  Most critically for this sample, it allows you to set up a daemon that:

- runs with elevated privileges (that is, with an effective and real user ID of 0, that is, runs as root)

- is launched on demand, based on inter-process communication (IPC)

So the privileged helper tool, installed as a launchd daemon, can lurk on the system consuming very few resources and then spring into life when it's needed by the app.

You can learn more about launchd by reading:

- its man page, <x-man-page://5/launchd.plist>

- "Daemons and Services Programming Guide"

<https://developer.apple.com/library/mac/>

o SMJobBless -- This API lets you securely install a launchd daemon.  You can learn more about this API by reading the "Service Management Framework Reference".

<https://developer.apple.com/library/mac/>

For a focused example on how to use the API, look at the SMJobBless sample code.

<http://developer.apple.com/library/mac/#samplecode/SMJobBless/>

EvenBetterAuthorizationSample uses SMJobBless to install its privileged helper tool as a launchd daemon.

IMPORTANT: The SMJobBless sample code contains a tool, "SMJobBlessUtil.py", that can help you set up SMJobBless code signing correctly.

o NSXPCConnection -- NSXPCConnection makes it very easy to do XPC-based IPC from Cocoa code.  EvenBetterAuthorizationSample uses this to communicate between the app and the privileged helper tool.

NSXPCConnection is documented in the "NSXPCConnection Class Reference", other related class references, and by WWDC 2012 Session 241 "Cocoa Interprocess Communication with XPC".

<https://developer.apple.com/library/mac/>

<https://developer.apple.com/videos/wwdc/2012/>

o Authorization Services -- With all of the above in place, it's possible to run code with elevated privileges.  The question is, how can you ensure that this facility isn't misused?  The answer to that is Authorization Services.  EvenBetterAuthorizationSample uses Authorization Services to restrict access to its privileged helper tool based on authorization right specifications in the authorization policy database ("/etc/authorization").  It installs a default set of authorization right specifications that are appropriate for most users, but a site administrator can edit the database to meet their specific needs.

To learn more about Authorization Services, read the "Authentication, Authorization, and Permissions Guide".

<https://developer.apple.com/library/mac/>

The goal of EvenBetterAuthorizationSample is to bring all of these technologies together into one place in order to illustrate the overall concept.

Adopting These Technologies
---------------------------
WARNING: Before writing any privileged code, you should read the "Secure Coding Guide".

<https://developer.apple.com/library/mac/>

EvenBetterAuthorizationSample uses a selection of recently-introduced, nice, high-level APIs, meaning that it contains very little boileplate code for you to copy directly into your app.  Probably the only code worth copying verbatim is in Common.{h,m}, which contains code that's likely to be useful for any app that implements an Authorization Services-restricted privileged helper tool.  You will, of course, need to custom the info about the specific right (in sCommandInfo).  This will require you to think carefully about what privileged operations your app needs to do, and how those operations should be protected by authorization rights.

Next you will probably want to look at the HelperTool directory.  This tool makes a good starting point for your privileged helper tool.  It's reasonable to copy the code en masse and then customize it from there.  Specifically, you should change:

o kHelperToolMachServiceName, to use a service name based on your bundle identifier

o "HelperTool-Launchd.plist" and "HelperTool-Info.plist", to match

o the code signing information in "HelperTool-Info.plist"

o HelperToolProtocol, to remove the current sample methods and replace them with the methods needed by your app

o "HelperTool.m", to match the changes to HelperToolProtocol

IMPORTANT: These last two points should be informed by the authorization rights you decided on when modifying sCommandInfo.

Finally, you should look at the test app's source code and integrate the relevant chunks of code into your app.  Look at the "App" target for a normal app, or the "App-Sandboxed" target if your app is sandboxed.

IMPORTANT: With regards sandboxing, see the note about the Mac App Store, above.

Caveats
-------
A real application that uses this technology will have to deal with updating its privileged helper tool.  This is harder than it should be because of limitations in SMJobBless (specifically, SMJobBless requests authorization /before/ doing its version check <rdar://problem/10280469>).  The best way to deal with updates is:

1. implement a 'get version' operation, that your app can use to determine the version of the installed tool

2. have the app update the tool if the returned version is too old

The sample does not show this directly, but it does show each of the steps.  For step 1, look at the code path executed by the "Get Version" button.  Doing step 2 simply involves calling SMJobBless, which will do the update on your behalf.

It's not currently possible <rdar://problem/14630599> for an XPC-based launchd daemon to safely:

o adopt launchd transactions (see the discussion of "EnableTransactions" in <x-man-page://5/launchd.plist>)

o take advantage of XPC transactions (see the discussion in <x-man-page://3/xpc_transaction_begin>) 

o implement its own idle timeout (where the daemon automatically exits after a certain period of inactivity)

EvenBetterAuthorizationSample simply ignores this problem, which is less than ideal (for example, it prevents the daemon from exiting on idle) but nevertheless reasonable given the focus of the sample.  In a real product you can implement a reliable workaround that uses app-specific knowledge (app-level retry, idempotent operations, and so on).

It would be nice if the privileged helper tool was itself sandboxed, something that would limit the potential damage caused by an errant tool.  Alas, it's currently not possible to sandbox a third party daemon <rdar://problem/12253780>.

Notes
-----
The bundle identifiers for this sample start with "com.example.apple-samplecode.EBAS" rather than "com.apple.EBAS" because the authorization policy database ("/etc/authorization" on current systems) has a wildcard rule for "com.apple.".  If we use a bundle identifier starting with "com.apple." then our attempt to add a custom right would be treated as an an attempt to modify the policy database.  Such modifications require that you authenticate as an admin user.

Also, the bundle identifier uses "EBAS" rather than "EvenBetterAuthorizationSample" because NSXPCConnection has problems with long service names on OS X 10.8.x (longer than 64 characters).

The sample includes a complete German localization.  This allows you to see how Authorization Services handles localized right descriptions.  Be aware, however, that most of the buttons in the main user interface (everything except "Install") are not localized; that's because these buttons correspond to privileged operations rather than user-level activities (that is, they are localized into "Geek" :-).  The same logic applies to the log strings that appear in the main window as you perform actions and to the name "EvenBetterAuthorizationSample" itself.

The sample stores the make-believe license key in "/var/root/Library/Preferences/xxx.plist" rather than in "/Library/Preferences/xxx.plist".  This is a natural consequence of the helper tool using NSUserDefaults, but it's also the right thing to do because it means that folks have to go through the helper tool (and hence the Authorization Services check) in order to read the license key.

Credits and Version History
---------------------------
If you find any problems with this sample, please file a bug against it.

<http://developer.apple.com/bugreporter/>

1.0dX (Aug 2012..Aug 2013) shipped to a limited number of developers on a one-to-one basis.

1.0 (Aug 2013) was the first widely-shipped version.

Share and Enjoy

Apple Developer Technical Support
Core OS/Hardware

27 Aug 2013
