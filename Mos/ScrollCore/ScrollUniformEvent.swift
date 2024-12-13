//
//  TaskQueue.swift
//  Mos
//
//  Created by 烟雀 on 2024/12/13.
//  Copyright © 2024 Caldis. All rights reserved.
//

import Cocoa

class ScrollUniformEvent{
    // 单例
    static let shared = ScrollUniformEvent()
    
    // 轴数据, 需要滚动到的目标位置, 由 ScrollEvent 设置
    var destY: Double = 0
    var destX: Double = 0
    
    init(){}
    
    func updateDest(x: Double, y: Double) -> Void{
        destY = y
        destX = x
    }
}

// 滚轮匀速滚动的封装
extension ScrollUniformEvent{
    
    func isCustomEvent(event: CGEvent?, step: Double) -> Bool{
        // 比最小步长小, 仅反转
        return step >= abs(destY)
    }
    func setCustomEvent(event: CGEvent?) -> Void{
        // event?.keyboardSetUnicodeString(stringLength: 20, unicodeString: "com.yq.mos.event")
    }
    
    func srollSmooth(
        duration: TimeInterval,
        step: Double,
        originEvent: CGEvent,
        proxy: CGEventTapProxy
    ) -> Void {
        
        // 此处滚动事件距离
        let _y = destY
        let _x = destX
        
        // 单步增量
        let deltaX = step
        let deltaY = step
        
        if (isCustomEvent(event: originEvent, step: step)){
            
            return
        }
        var accumulatedDeltaX = 0.0
        var accumulatedDeltaY = 0.0
        var idx = 0
        let xDirection: Int32 = _x > 0 ? 1:-1
        let yDirection: Int32 = _y > 0 ? 1:-1
        
        // NSLog("ScrollEvent-srollSmooth ... y: \(_y) ")
        
        while (accumulatedDeltaY < abs(_y)){
            accumulatedDeltaY += step
            accumulatedDeltaX += step
            if (accumulatedDeltaX > abs(_x)) {
                accumulatedDeltaX = abs(_x)
            }
            idx += 1
            
            DispatchQueue.main.asyncAfter(
                // deadline: .now() + 0.01 * Double(idx),
                // 120 帧, 手动模拟帧率, 因为 CvdDisplay 有毛病
                deadline: .now() + 1 / 120 * Double(idx),
                execute: {
                    NSLog("ScrollEvent-srollSmooth \(idx) with \(_y)...")
                    
                    self.doScrollWithEvent(
                        originEvent: originEvent,
                        proxy: proxy,
                        xVal: deltaX * Double(xDirection),
                        yVal: deltaY * Double(yDirection)
                    )
                    
//                    self.doScrollWithNewEvent(
//                        xVal: deltaX * Double(xDirection),
//                        yVal: deltaY * Double(yDirection)
//                    )
                    
                }
            )
            
        }
        
        // CGEventTapLocation.cgSessionEventTap
        // originEvent.tapPostEvent(.cgSessionEventTap)
        
    }
    
    func doScrollWithEvent(
        originEvent: CGEvent,
        proxy: CGEventTapProxy,
        xVal: Double,
        yVal: Double
    ) -> Void{
        if let eventClone = originEvent.copy(){
            ScrollPhase.shared.transfrom()
            // 设置滚动数据
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: yVal)
            eventClone.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: xVal)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis1, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventFixedPtDeltaAxis2, value: 0.0)
            eventClone.setDoubleValueField(.scrollWheelEventIsContinuous, value: 1.0)
            eventClone.tapPostEvent(proxy)
        }
    }
    
    func doScrollWithNewEvent(
        xVal: Double,
        yVal: Double
    ) -> Void{
        
        // 创建一个 CGEvent
        let scrollEvent = CGEvent(scrollWheelEvent2Source: nil,
                                  units: .pixel,
                                  wheelCount: 1,
                                  wheel1: -Int32(yVal),     // 垂直滚动增量
                                  wheel2: Int32(xVal),      // 水平滚动增量
                                  wheel3: 0)                // 多种滚轮的情况
        
        // 设置 CGEvent 的标志位,以避免被自己创建的 tapCreate 捕获
        // scrollEvent?.flags = .init(CGEventFlags.notEnoughUsageBits.rawValue)
        
        // 将 CGEvent 注入到事件流
        scrollEvent?.post(tap: .cghidEventTap)
        
        // scrollWheelEvent2Source 不知道为什么无效
//                     let newEvent =  CGEvent(
//                        scrollWheelEvent2Source: ScrollEvent.eventSource,
//                        units: .pixel,
//                        wheelCount: 1,
//                        // 垂直滚动增量
//                        wheel1: Int32(deltaY) * yDirection,
//                        // 水平滚动增量
//                        wheel2: Int32(deltaX) * xDirection,
//                        // 多种滚轮的情况
//                        wheel3: 0)
////                    let newEvent = CGEvent(
////                        // 使用默认来源
////                        mouseEventSource: nil,
////                        // 滚动行为
////                        mouseType: .scrollWheel,
////                        // 鼠标指针的位置，通常使用 .zero 表示位置（对于滚动事件，这个值不重要）
////                        mouseCursorPosition: .zero,
////                        // 指定鼠标按钮，通常在滚动事件中设置为 .left，但对于滚动事件并不影响行为
////                        mouseButton: .left
////                    )
//                    self.setCustomEvent(event: newEvent)
//                    // newEvent?.post(tap: .cgSessionEventTap)
//                    newEvent?.tapPostEvent(proxy)
        
        
    }
    
}



