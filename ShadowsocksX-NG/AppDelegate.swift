//
//  AppDelegate.swift
//  ShadowsocksX-NG
//
//  Created by 邱宇舟 on 16/6/5.
//  Copyright © 2016年 qiuyuzhou. All rights reserved.
//

import Cocoa
import Carbon
import RxCocoa
import RxSwift

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate, NSUserNotificationCenterDelegate {
    
    var qrcodeWinCtrl: SWBQRCodeWindowController!
    var preferencesWinCtrl: PreferencesWindowController!
    var editUserRulesWinCtrl: UserRulesController!
    var allInOnePreferencesWinCtrl: PreferencesWinController!
    var toastWindowCtrl: ToastWindowController!

    @IBOutlet weak var window: NSWindow!
    @IBOutlet weak var statusMenu: NSMenu!
    
    @IBOutlet weak var runningStatusMenuItem: NSMenuItem!
    @IBOutlet weak var toggleRunningMenuItem: NSMenuItem!
    @IBOutlet weak var autoModeMenuItem: NSMenuItem!
    @IBOutlet weak var globalModeMenuItem: NSMenuItem!
    @IBOutlet weak var manualModeMenuItem: NSMenuItem!
    
    @IBOutlet weak var serversMenuItem: NSMenuItem!
    @IBOutlet var showQRCodeMenuItem: NSMenuItem!
    @IBOutlet var scanQRCodeMenuItem: NSMenuItem!
    @IBOutlet var showBunchJsonExampleFileItem: NSMenuItem!
    @IBOutlet var importBunchJsonFileItem: NSMenuItem!
    @IBOutlet var exportAllServerProfileItem: NSMenuItem!
    @IBOutlet var serversPreferencesMenuItem: NSMenuItem!
    
    @IBOutlet weak var copyHttpProxyExportCmdLineMenuItem: NSMenuItem!
    
    @IBOutlet weak var lanchAtLoginMenuItem: NSMenuItem!

    @IBOutlet weak var hudWindow: NSPanel!
    @IBOutlet weak var panelView: NSView!
    @IBOutlet weak var isNameTextField: NSTextField!

    let kProfileMenuItemIndexBase = 100

    var statusItem: NSStatusItem!
    static let StatusItemIconWidth:CGFloat = 20
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        
        _ = LaunchAtLoginController()// Ensure set when launch
        
        NSUserNotificationCenter.default.delegate = self
        
        // Prepare ss-local
        InstallSSLocal()
        InstallKcptunClient()
        InstallPrivoxy()
        // Prepare defaults
        let defaults = UserDefaults.standard
        defaults.register(defaults: [
            "ShadowsocksOn": true,
            "ShadowsocksRunningMode": "auto",
            "LocalSocks5.ListenPort": NSNumber(value: 1086 as UInt16),
            "LocalSocks5.ListenAddress": "127.0.0.1",
            "PacServer.ListenPort":NSNumber(value: 1089 as UInt16),
            "LocalSocks5.Timeout": NSNumber(value: 60 as UInt),
            "LocalSocks5.EnableUDPRelay": NSNumber(value: false as Bool),
            "LocalSocks5.EnableVerboseMode": NSNumber(value: false as Bool),
            "GFWListURL": "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt",
            "AutoConfigureNetworkServices": NSNumber(value: true as Bool),
            "LocalHTTP.ListenAddress": "127.0.0.1",
            "LocalHTTP.ListenPort": NSNumber(value: 1087 as UInt16),
            "LocalHTTPOn": true,
            "LocalHTTP.FollowGlobal": true,
            "Kcptun.LocalHost": "127.0.0.1",
            "Kcptun.LocalPort": NSNumber(value: 8388),
            "Kcptun.Conn": NSNumber(value: 1),
            ])
        
        statusItem = NSStatusBar.system().statusItem(withLength: AppDelegate.StatusItemIconWidth)
        let image : NSImage = NSImage(named: "menu_icon")!
        image.isTemplate = true
        statusItem.image = image
        statusItem.menu = statusMenu
        
        
        let notifyCenter = NotificationCenter.default
        
        _ = notifyCenter.rx.notification(NOTIFY_CONF_CHANGED)
            .subscribe(onNext: { noti in
                SyncSSLocal()
                self.applyConfig()
                self.updateCopyHttpProxyExportMenu()
            })
        
        notifyCenter.addObserver(forName: NOTIFY_SERVER_PROFILES_CHANGED, object: nil, queue: nil
            , using: {
                (note) in
                let profileMgr = ServerProfileManager.instance
                if profileMgr.activeProfileId == nil &&
                    profileMgr.profiles.count > 0{
                    if profileMgr.profiles[0].isValid(){
                        profileMgr.setActiveProfiledId(profileMgr.profiles[0].uuid)
                    }
                }
                self.updateServersMenu()
                self.updateRunningModeMenu()
                SyncSSLocal()
            }
        )
        _ = notifyCenter.rx.notification(NOTIFY_TOGGLE_RUNNING_SHORTCUT)
            .subscribe(onNext: { noti in
                self.doToggleRunning(showToast: true)
            })
        _ = notifyCenter.rx.notification(NOTIFY_SWITCH_PROXY_MODE_SHORTCUT)
            .subscribe(onNext: { noti in
                let mode = defaults.string(forKey: "ShadowsocksRunningMode")!
                
                var toastMessage: String!;
                switch mode {
                case "auto":
                    defaults.setValue("global", forKey: "ShadowsocksRunningMode")
                    toastMessage = "Global Mode".localized
                case "global":
                    defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
                    toastMessage = "Auto Mode By PAC".localized
                default:
                    defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
                    toastMessage = "Auto Mode By PAC".localized
                }
                
                self.updateRunningModeMenu()
                self.applyConfig()
                
                self.makeToast(toastMessage)
            })
        
        _ = notifyCenter.rx.notification(NOTIFY_FOUND_SS_URL)
            .subscribe(onNext: { noti in
                self.handleFoundSSURL(noti)
            })
        
        // Handle ss url scheme
        NSAppleEventManager.shared().setEventHandler(self
            , andSelector: #selector(self.handleURLEvent)
            , forEventClass: AEEventClass(kInternetEventClass), andEventID: AEEventID(kAEGetURL))
        
        updateMainMenu()
        updateCopyHttpProxyExportMenu()
        updateServersMenu()
        updateRunningModeMenu()
        
        ProxyConfHelper.install()
        ProxyConfHelper.startMonitorPAC()
        applyConfig()

        // Register global hotkey
        ShortcutsController.bindShortcuts()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
        StopSSLocal()
        StopKcptun()
        StopPrivoxy()
        ProxyConfHelper.disableProxy()
    }

    func applyConfig() {
        SyncSSLocal()
        
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        if isOn {
            if mode == "auto" {
                ProxyConfHelper.enablePACProxy()
            } else if mode == "global" {
                ProxyConfHelper.enableGlobalProxy()
            } else if mode == "manual" {
                ProxyConfHelper.disableProxy()
            }
        } else {
            ProxyConfHelper.disableProxy()
        }
    }

    // MARK: - UI Methods
    @IBAction func toggleRunning(_ sender: NSMenuItem) {
        self.doToggleRunning(showToast: false)
    }
    
    func doToggleRunning(showToast: Bool) {
        let defaults = UserDefaults.standard
        var isOn = UserDefaults.standard.bool(forKey: "ShadowsocksOn")
        isOn = !isOn
        defaults.set(isOn, forKey: "ShadowsocksOn")
        
        self.updateMainMenu()
        self.applyConfig()
        
        if showToast {
            if isOn {
                self.makeToast("Shadowsocks: On".localized)
            }
            else {
                self.makeToast("Shadowsocks: Off".localized)
            }
        }
    }
    
    @IBAction func updateGFWList(_ sender: NSMenuItem) {
        UpdatePACFromGFWList()
    }
    
    @IBAction func editUserRulesForPAC(_ sender: NSMenuItem) {
        if editUserRulesWinCtrl != nil {
            editUserRulesWinCtrl.close()
        }
        let ctrl = UserRulesController(windowNibName: "UserRulesController")
        editUserRulesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func showQRCodeForCurrentServer(_ sender: NSMenuItem) {
        var errMsg: String?
        if let profile = ServerProfileManager.instance.getActiveProfile() {
            if profile.isValid() {
                // Show window
                if qrcodeWinCtrl != nil{
                    qrcodeWinCtrl.close()
                }
                qrcodeWinCtrl = SWBQRCodeWindowController(windowNibName: "SWBQRCodeWindowController")
                qrcodeWinCtrl.qrCode = profile.URL()!.absoluteString
                qrcodeWinCtrl.title = profile.title()
                qrcodeWinCtrl.showWindow(self)
                NSApp.activate(ignoringOtherApps: true)
                qrcodeWinCtrl.window?.makeKeyAndOrderFront(nil)
                
                return
            } else {
                errMsg = "Current server profile is not valid.".localized
            }
        } else {
            errMsg = "No current server profile.".localized
        }
        if let msg = errMsg {
            self.makeToast(msg)
        }
    }
    
    @IBAction func scanQRCodeFromScreen(_ sender: NSMenuItem) {
        ScanQRCodeOnScreen()
    }
    
    @IBAction func showBunchJsonExampleFile(sender: NSMenuItem) {
        ServerProfileManager.showExampleConfigFile()
    }
    
    @IBAction func importBunchJsonFile(sender: NSMenuItem) {
        ServerProfileManager.instance.importConfigFile()
        //updateServersMenu()//not working
    }
    
    @IBAction func exportAllServerProfile(sender: NSMenuItem) {
        ServerProfileManager.instance.exportConfigFile()
    }

    @IBAction func selectPACMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("auto", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectGlobalMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("global", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func selectManualMode(_ sender: NSMenuItem) {
        let defaults = UserDefaults.standard
        defaults.setValue("manual", forKey: "ShadowsocksRunningMode")
        updateRunningModeMenu()
        applyConfig()
    }
    
    @IBAction func editServerPreferences(_ sender: NSMenuItem) {
        if preferencesWinCtrl != nil {
            preferencesWinCtrl.close()
        }
        let ctrl = PreferencesWindowController(windowNibName: "PreferencesWindowController")
        preferencesWinCtrl = ctrl
        
        ctrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        ctrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func showAllInOnePreferences(_ sender: NSMenuItem) {
        if allInOnePreferencesWinCtrl != nil {
            allInOnePreferencesWinCtrl.close()
        }
        
        allInOnePreferencesWinCtrl = PreferencesWinController(windowNibName: "PreferencesWinController")
        
        allInOnePreferencesWinCtrl.showWindow(self)
        NSApp.activate(ignoringOtherApps: true)
        allInOnePreferencesWinCtrl.window?.makeKeyAndOrderFront(self)
    }
    
    @IBAction func selectServer(_ sender: NSMenuItem) {
        let index = sender.tag - kProfileMenuItemIndexBase
        let spMgr = ServerProfileManager.instance
        let newProfile = spMgr.profiles[index]
        if newProfile.uuid != spMgr.activeProfileId {
            spMgr.setActiveProfiledId(newProfile.uuid)
            updateServersMenu()
            SyncSSLocal()
            applyConfig()
        }
        updateRunningModeMenu()
    }
    
    @IBAction func copyExportCommand(_ sender: NSMenuItem) {
        // Get the Http proxy config.
        let defaults = UserDefaults.standard
        let address = defaults.string(forKey: "LocalHTTP.ListenAddress")!
        let port = defaults.integer(forKey: "LocalHTTP.ListenPort")
        
        // Format an export string.
        let command = "export http_proxy=http://\(address):\(port);export https_proxy=http://\(address):\(port);"
        
        // Copy to paste board.
        NSPasteboard.general().clearContents()
        NSPasteboard.general().setString(command, forType: NSStringPboardType)
        
        // Show a toast notification.
        self.makeToast("Export Command Copied.".localized)
    }
    
    @IBAction func showLogs(_ sender: NSMenuItem) {
        let ws = NSWorkspace.shared()
        if let appUrl = ws.urlForApplication(withBundleIdentifier: "com.apple.Console") {
            try! ws.launchApplication(at: appUrl
                ,options: .default
                ,configuration: [NSWorkspaceLaunchConfigurationArguments: "~/Library/Logs/ss-local.log"])
        }
    }
    
    @IBAction func feedback(_ sender: NSMenuItem) {
        NSWorkspace.shared().open(URL(string: "https://github.com/qiuyuzhou/ShadowsocksX-NG/issues")!)
    }
    
    @IBAction func showAbout(_ sender: NSMenuItem) {
        NSApp.orderFrontStandardAboutPanel(sender);
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func updateRunningModeMenu() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        
        var serverMenuText = "Servers".localized

        let mgr = ServerProfileManager.instance
        for p in mgr.profiles {
            if mgr.activeProfileId == p.uuid {
                var profileName :String
                if !p.remark.isEmpty {
                    profileName = p.remark
                } else {
                    profileName = p.serverHost
                }
                serverMenuText = "\(serverMenuText) - \(profileName)"
            }
        }
        serversMenuItem.title = serverMenuText
        
        if mode == "auto" {
            autoModeMenuItem.state = 1
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 0
        } else if mode == "global" {
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 1
            manualModeMenuItem.state = 0
        } else if mode == "manual" {
            autoModeMenuItem.state = 0
            globalModeMenuItem.state = 0
            manualModeMenuItem.state = 1
        }
        updateStatusMenuImage()
    }
    
    func updateStatusMenuImage() {
        let defaults = UserDefaults.standard
        let mode = defaults.string(forKey: "ShadowsocksRunningMode")
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        if isOn {
            if let m = mode {
                switch m {
                    case "auto":
                        statusItem.image = NSImage(named: "menu_p_icon")
                    case "global":
                        statusItem.image = NSImage(named: "menu_g_icon")
                    case "manual":
                        statusItem.image = NSImage(named: "menu_m_icon")
                default: break
                }
                statusItem.image?.isTemplate = true
            }
        } else {
            statusItem.image = NSImage(named: "menu_icon_disabled")
            statusItem.image?.isTemplate = true
        }
    }
    
    func updateMainMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "ShadowsocksOn")
        if isOn {
            runningStatusMenuItem.title = "Shadowsocks: On".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks Off".localized
            let image = NSImage(named: "menu_icon")
            statusItem.image = image
        } else {
            runningStatusMenuItem.title = "Shadowsocks: Off".localized
            toggleRunningMenuItem.title = "Turn Shadowsocks On".localized
            let image = NSImage(named: "menu_icon_disabled")
            statusItem.image = image
        }
        statusItem.image?.isTemplate = true
        
        updateStatusMenuImage()
    }
    
    func updateCopyHttpProxyExportMenu() {
        let defaults = UserDefaults.standard
        let isOn = defaults.bool(forKey: "LocalHTTPOn")
        copyHttpProxyExportCmdLineMenuItem.isHidden = !isOn
    }
    
    func updateServersMenu() {
        let mgr = ServerProfileManager.instance
        serversMenuItem.submenu?.removeAllItems()
        let preferencesItem = serversPreferencesMenuItem
        let showBunch = showBunchJsonExampleFileItem
        let importBuntch = importBunchJsonFileItem
        let exportAllServer = exportAllServerProfileItem
        
        serversMenuItem.submenu?.addItem(preferencesItem!)
        serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        
        var i = 0
        for p in mgr.profiles {
            let item = NSMenuItem()
            item.tag = i + kProfileMenuItemIndexBase
            item.title = p.title()
            if mgr.activeProfileId == p.uuid {
                item.state = 1
            }
            if !p.isValid() {
                item.isEnabled = false
            }
            item.action = #selector(AppDelegate.selectServer)
            
            serversMenuItem.submenu?.addItem(item)
            i += 1
        }
        if !mgr.profiles.isEmpty {
            serversMenuItem.submenu?.addItem(NSMenuItem.separator())
        }
        
        serversMenuItem.submenu?.addItem(showBunch!)
        serversMenuItem.submenu?.addItem(importBuntch!)
        serversMenuItem.submenu?.addItem(exportAllServer!)
    }
    
    func handleURLEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        if let urlString = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue {
            if let url = URL(string: urlString) {
                NotificationCenter.default.post(
                    name: Notification.Name(rawValue: "NOTIFY_FOUND_SS_URL"), object: nil
                    , userInfo: [
                        "urls": [url],
                        "source": "url",
                        ])
            }
        }
    }
    
    func handleFoundSSURL(_ note: Notification) {
        let sendNotify = {
            (title: String, subtitle: String, infoText: String) in
            
            let userNote = NSUserNotification()
            userNote.title = title
            userNote.subtitle = subtitle
            userNote.informativeText = infoText
            userNote.soundName = NSUserNotificationDefaultSoundName
            
            NSUserNotificationCenter.default
                .deliver(userNote);
        }
        
        if let userInfo = (note as NSNotification).userInfo {
            let urls: [URL] = userInfo["urls"] as! [URL]
            
            let mgr = ServerProfileManager.instance
            var isChanged = false
            
            for url in urls {
                if let profile = ServerProfile(url: url) {
                    mgr.profiles.append(profile)
                    isChanged = true
                    
                    var subtitle: String = ""
                    if userInfo["source"] as! String == "qrcode" {
                        subtitle = "By scan QR Code".localized
                    } else if userInfo["source"] as! String == "url" {
                        subtitle = "By Handle SS URL".localized
                    }
                    
                    sendNotify("Add Shadowsocks Server Profile".localized, subtitle, "Host: \(profile.serverHost)")
                }
            }
            
            if isChanged {
                mgr.save()
                self.updateServersMenu()
            } else {
                sendNotify("Not found valid qrcode of shadowsocks profile.", "", "")
            }
        }
    }
    
    //------------------------------------------------------------
    // NSUserNotificationCenterDelegate
    
    func userNotificationCenter(_ center: NSUserNotificationCenter
        , shouldPresent notification: NSUserNotification) -> Bool {
        return true
    }
    
    
    func makeToast(_ message: String) {
        if toastWindowCtrl != nil {
            toastWindowCtrl.close()
        }
        toastWindowCtrl = ToastWindowController(windowNibName: "ToastWindowController")
        toastWindowCtrl.message = message
        toastWindowCtrl.showWindow(self)
        //NSApp.activate(ignoringOtherApps: true)
        //toastWindowCtrl.window?.makeKeyAndOrderFront(self)
        toastWindowCtrl.fadeInHud()
    }
}

