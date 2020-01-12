# HelperTool + XPCService Project Setup

This is how to set everything up (I believe) 

>
The original Apple Doc for this project can be found in README-APPLE

In this example the 3 identifiers for the 3 targets are

Name | Identifier
------------- | -------------
Broker (Main app) | `com.blackwellapps.Broker`
BrokerHelper (HelperTool) | `com.blackwellapps.BrokerHelper`
XPCService | `com.blackwellapps.XPCService`

---

## 1 Add Copy File build phase

**Main App**
Add `Copy File` build phase to main app target: 
Destination: Wrapper 
Subpath: Contents/LibraryXPCServices, 
Codesign on Copy:Disable.

![screen shot 2015-04-17 at 15 35 48](https://cloud.githubusercontent.com/assets/802618/7202989/818cccd8-e517-11e4-84c9-8969aeb57430.png)

**XPCService**
Add `Copy File` build phase to XPCService target: 
Destination: Wrapper 
Subpath: Contents/Library/LaunchServices, 
Codesign on Copy:Disable.

![screen shot 2015-04-17 at 15 37 12](https://cloud.githubusercontent.com/assets/802618/7203009/b480a27c-e517-11e4-8279-43608d28934f.png)

---

## 2 Modify Info.plists

**XPCService-Info.plist** (Tools owned after installation)

Add a new key value pair to the **XPCService's** `Info.plist` 
* **Key:** *"Tools owned after installation"*
* **Type:** dictionary
  
Inside this new dictionary add a another key value pair: 
* **Key:** `Your helper's bundle identifier`
* **Type:** string
* **Value:** *"anchor apple generic and certificate leaf[subject.CN] = `Certificate Name` and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */"*
  
![screen shot 2015-04-17 at 15 55 47](https://cloud.githubusercontent.com/assets/802618/7203345/43782dfe-e51a-11e4-8bf9-4286b5045e45.png)

**HelperTool-Info.plist** (Clients allowed to add and remove tool)

Add a new key value pair the HelperTools's `Info.plist` 
* **Key:** *"Clients allowed to add and remove tool"*
* **Type:** array

As this is an array, we will add a new item to the 0 index:
* **Key/Position:** "Item 0"
* **Type:** string
* **Value:** *"identifier `XPCService identifier` and anchor apple generic and certificate leaf[subject.CN] = `Certificate Name` and certificate 1[field.1.2.840.113635.100.6.2.1] /* exists */"*

![screen shot 2015-04-17 at 15 38 38](https://cloud.githubusercontent.com/assets/802618/7203043/f3ea52e6-e517-11e4-8f8b-7c2bda6cb2cf.png)

---

## 3 Developer ID
Choose Developer ID:* in Code Signing Identity in build settings for each targets.

**Main App**

![screen shot 2015-04-17 at 15 46 53](https://cloud.githubusercontent.com/assets/802618/7203194/2607019c-e519-11e4-8218-017742d072dc.png)

**XPCService**

![screen shot 2015-04-17 at 15 46 45](https://cloud.githubusercontent.com/assets/802618/7203200/2e3bfef8-e519-11e4-9140-e3ef4d3b3b67.png)

**HelperTool**

![screen shot 2015-04-17 at 15 46 59](https://cloud.githubusercontent.com/assets/802618/7203182/1e527af8-e519-11e4-92ed-50a399e0d714.png)

---

## 4 Build
Build the app.

---

## 5 SMJobBlessUtil.py
Use `SMJobBlessUtil.py` cli script

  **Update Info.plist:**

  Format: `$ ./SMJobBlessUtil.py setreq <XPCService path> <XPCService's Info.plist path> <Helper's Info.plist>`

```shell
./SMJobBlessUtil.py setreq Build/Products/Debug/com.blackwellapps.XPCService.xpc XPCService/XPCService-Info.plist BrokerHelper/HelperTool-Info.plist HelperTool/HelperTool-Info.plist
```
  
  **Check Code Signing status:**
  
  Format: `$ ./SMJobBlessUtil.py check <XPCservice path>`
  
```shell
./SMJobBlessUtil.py check Build/Products/Debug/com.blackwellapps.XPCService.xpc
```
 
---  
  
## Troubleshooting
* If it doesn't pass the CLI `check` then make sure #3 is correct
* Also Make sure each .plist file is set as Info.plist in the corresponding Target's Build settings.

---

## Credit

Got some of this from this gist https://gist.github.com/xiao99xiao/0509091001bdd6259249
