//
//  AppDelegate.swift
//  Mos
//
//  Created by Caldis on 2017/1/10.
//  Copyright © 2017年 Caldis. All rights reserved.
//

import Cocoa

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private let wakeRecoveryRetryDelays: [TimeInterval] = [0.0, 0.5, 1.5, 3.0]
    private var wakeRecoveryWorkItems = [DispatchWorkItem]()

    // 运行前预处理
    func applicationWillFinishLaunching(_ notification: Notification) {
        // 禁止重复运行, 结束正在运行的实例
        Utils.preventMultiRunning(killExist: true)
        
        // DEBUG: 清空用户设置
        // UserDefaults.standard.removePersistentDomain(forName: Bundle.main.bundleIdentifier!)
        
        // 读取用户设置
        Options.shared.readOptions()
        
        // DEBUG: 直接弹出设置窗口
        #if DEBUG
        WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        #endif

        // 监听用户切换, 在切换用户 session 时停止运行
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.sessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )
        // 监听系统休眠/唤醒, 采用独立的恢复重试路径
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.systemWillSleep(_:)),
            name: NSWorkspace.willSleepNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(AppDelegate.systemDidWake(_:)),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
    }
    // 运行后启动滚动处理
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        startWithAccessibilityPermissionsChecker(nil)
        UpdateManager.shared.scheduleCheckOnAppStartIfNeeded()
    }

    // 用户双击打开应用程序
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        guard !flag else {
            return true
        }
        if Utils.isHadAccessibilityPermissions() {
            WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.preferencesWindowController)
        }
        return false
    }
    
    // 关闭前停止滚动处理
    func applicationWillTerminate(_ aNotification: Notification) {
        stopInputSubsystems(reason: "application terminate")
    }
    
    // 检查是否有访问 accessibility 权限, 如果有则启动滚动处理, 并结束计时器
    // 10.14(Mojave) 后, 若无该权限会直接在创建 eventTap 时报错 (https://developer.apple.com/videos/play/wwdc2018/702/)
    @objc func startWithAccessibilityPermissionsChecker(_ timer: Timer?) {
        if let validTimer = timer {
            // 开启辅助权限后, 关闭定时器, 开始处理
            if Utils.isHadAccessibilityPermissions() {
                validTimer.invalidate()
                NSLog("First Initialization (Accessibility Authorization Needed)")
                startInputSubsystems(reason: "first initialization after accessibility grant")
            }
        } else {
            if Utils.isHadAccessibilityPermissions() {
                NSLog("Regular Initialization")
                startInputSubsystems(reason: "regular initialization")
            } else {
                // 如果应用不在辅助权限列表内, 则弹出欢迎窗口
                WindowManager.shared.showWindow(withIdentifier: WINDOW_IDENTIFIER.introductionWindowController, withTitle: "")
                // 启动定时器检测权限, 当拥有授权时启动滚动处理
                Timer.scheduledTimer(
                    timeInterval: 2.0,
                    target: self,
                    selector: #selector(startWithAccessibilityPermissionsChecker(_:)),
                    userInfo: nil,
                    repeats: true
                )
            }
        }
    }
    
    // 在切换用户时停止滚动处理
    @objc func sessionDidBecomeActive(_ notification: Notification) {
        startInputSubsystems(reason: "session became active")
    }

    @objc func sessionDidResignActive(_ notification: Notification) {
        stopInputSubsystems(reason: "session resigned active")
    }

    @objc func systemWillSleep(_ notification: Notification) {
        stopInputSubsystems(reason: "system will sleep")
    }

    @objc func systemDidWake(_ notification: Notification) {
        NSLog("[Lifecycle] System did wake")
        scheduleWakeRecovery()
    }
}

private extension AppDelegate {
    func startInputSubsystems(reason: String) {
        guard Utils.isHadAccessibilityPermissions() else {
            NSLog("[Lifecycle] Skip starting input subsystems without accessibility permissions (\(reason))")
            return
        }
        ScrollCore.shared.enable()
        ButtonCore.shared.enable()
        LogitechHIDManager.shared.start()
        NSLog("[Lifecycle] Input start (\(reason)) -> \(inputSubsystemHealthSummary())")
    }

    func stopInputSubsystems(reason: String) {
        cancelPendingWakeRecovery(reason: "cancelled by \(reason)")
        NSLog("[Lifecycle] Stopping input subsystems (\(reason))")
        LogitechHIDManager.shared.stop()
        ScrollCore.shared.disable()
        ButtonCore.shared.disable()
    }

    func inputSubsystemsAreHealthy() -> Bool {
        return ScrollCore.shared.isHealthy && ButtonCore.shared.isHealthy && LogitechHIDManager.shared.isHealthy
    }

    func inputSubsystemHealthSummary() -> String {
        return "scroll=\(ScrollCore.shared.isHealthy) button=\(ButtonCore.shared.isHealthy) hid=\(LogitechHIDManager.shared.isHealthy)"
    }

    func scheduleWakeRecovery() {
        guard Utils.isHadAccessibilityPermissions() else {
            NSLog("[Lifecycle] Skip wake recovery scheduling without accessibility permissions")
            return
        }
        cancelPendingWakeRecovery(reason: "rescheduled by system wake")
        NSLog("[Lifecycle] Scheduling wake recovery attempts at delays \(wakeRecoveryRetryDelays)")
        for (index, delay) in wakeRecoveryRetryDelays.enumerated() {
            let workItem = DispatchWorkItem { [weak self] in
                self?.performWakeRecoveryAttempt(index: index)
            }
            wakeRecoveryWorkItems.append(workItem)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: workItem)
        }
    }

    func performWakeRecoveryAttempt(index: Int) {
        let attempt = index + 1
        let total = wakeRecoveryRetryDelays.count
        guard Utils.isHadAccessibilityPermissions() else {
            NSLog("[Lifecycle] Wake recovery aborted without accessibility permissions on attempt \(attempt)/\(total)")
            cancelPendingWakeRecovery(reason: "accessibility permissions unavailable during wake recovery")
            return
        }
        if inputSubsystemsAreHealthy() {
            NSLog("[Lifecycle] Wake recovery already healthy before attempt \(attempt)/\(total): \(inputSubsystemHealthSummary())")
            cancelPendingWakeRecovery(reason: "wake recovery finished before attempt \(attempt)")
            return
        }

        NSLog("[Lifecycle] Wake recovery attempt \(attempt)/\(total) starting: \(inputSubsystemHealthSummary())")

        if !ScrollCore.shared.isHealthy {
            ScrollCore.shared.disable()
            ScrollCore.shared.enable()
        }
        if !ButtonCore.shared.isHealthy {
            ButtonCore.shared.disable()
            ButtonCore.shared.enable()
        }
        if !LogitechHIDManager.shared.isHealthy {
            LogitechHIDManager.shared.stop()
            LogitechHIDManager.shared.start()
        }

        let summary = inputSubsystemHealthSummary()
        if inputSubsystemsAreHealthy() {
            NSLog("[Lifecycle] Wake recovery succeeded on attempt \(attempt)/\(total): \(summary)")
            cancelPendingWakeRecovery(reason: "wake recovery completed on attempt \(attempt)")
        } else if attempt == total {
            NSLog("[Lifecycle] Wake recovery exhausted after \(attempt) attempts: \(summary)")
            wakeRecoveryWorkItems.removeAll()
        } else {
            NSLog("[Lifecycle] Wake recovery attempt \(attempt)/\(total) incomplete: \(summary)")
        }
    }

    func cancelPendingWakeRecovery(reason: String) {
        guard !wakeRecoveryWorkItems.isEmpty else { return }
        for workItem in wakeRecoveryWorkItems {
            workItem.cancel()
        }
        wakeRecoveryWorkItems.removeAll()
        NSLog("[Lifecycle] Cancelled wake recovery: \(reason)")
    }
}
