//
//  AppDelegate.swift
//  HuaweiRemote
//
//  Created by jia xiaodong on 7/11/20.
//  Copyright © 2020 homemade. All rights reserved.
//

import UIKit

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

	var window: UIWindow?

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey : Any]? = nil) -> Bool {
        return true
    }
    
    func applicationWillResignActive(_ application: UIApplication) {
        scheduleReloadUserConfig()
    }
    
    func applicationDidEnterBackground(_ application: UIApplication) {
        // empty
    }
    
    func applicationWillEnterForeground(_ application: UIApplication) {
        // empty
    }
    
    func applicationDidBecomeActive(_ application: UIApplication) {
        checkReloadUserConfig()
    }
    
    func applicationWillTerminate(_ application: UIApplication) {
        releaseResourcesMannually()
    }

	private func scheduleReloadUserConfig() {
		guard let viewController = self.window?.rootViewController else {
			return
		}
		guard let myViewController = viewController as? ViewController else {
			return
		}
		myViewController.ConfigNeedReload = true
	}
	
	private func checkReloadUserConfig() {
		guard let viewController = self.window?.rootViewController else {
			return
		}
		guard let myViewController = viewController as? ViewController else {
			return
		}
		if myViewController.ConfigNeedReload {
			myViewController.loadUserConfig()
		}
	}
	
	private func releaseResourcesMannually() {
		
		guard let viewController = self.window?.rootViewController else {
			return
		}
		guard let myViewController = viewController as? ViewController else {
			return
		}
		myViewController.releaseBeforeExit()
	}
}

