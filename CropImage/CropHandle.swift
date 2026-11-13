//
//  CornerType.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI

enum CropHandle {
    case topLeading
    case top
    case topTrailing
    case bottomLeading
    case bottom
    case bottomTrailing

    /// 使用圖片名稱，讓 Image(image) 也能支援 iOS 15。
    var image: String { "ic_corner_button" }
}
