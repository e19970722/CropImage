//
//  CornerType.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI

enum CornerType {
    case topLeading
    case top
    case topTrailing
    case bottomLeading
    case bottom
    case bottomTrailing
    
    var image: ImageResource {
        switch self {
        default: .icCornerButton
        }
    }
    
    var leadingPadding: CGFloat {
        switch self {
        default: 0
        }
    }
    
    var topPadding: CGFloat {
        switch self {
        default: 0
        }
    }
    
    var trailingPadding: CGFloat {
        switch self {
        default: 0
        }
    }
    
    var bottomPadding: CGFloat {
        switch self {
        default: 0
        }
    }
}
