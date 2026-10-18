//
//  CropImageScreen.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI
import UIKit

struct CubeCropImageScreen: View {
    // MARK: - 圖片
    private let image: UIImage = UIImage(resource: .test)
    private let horizontalPadding = 45.0
    private let verticalPadding = 30.0
    
    // MARK: - 裁切框
    @State private var cropRect: CGRect = .zero
    @State private var hideMiddleControl: Bool = false
    @GestureState private var dragTranslation: CGSize = .zero
    
    private let minCropSize: CGSize = CGSize(width: 80, height: 80)
    
    // MARK: - 裁切框四角
    @State private var resizeStartRect: CGRect? = nil
        
    // MARK: - Body
    var body: some View {
        GeometryReader { geo in
            let availableSize = CGSize(
                width: geo.size.width - horizontalPadding * 2,
                height: geo.size.height - verticalPadding * 2
            )

            let imageRect = getImageRect(in: availableSize)
            let displayedImageRect = imageRect.offsetBy(dx: horizontalPadding, dy: verticalPadding)

            ZStack {
                Color.black
                imageView(rect: displayedImageRect)
                editingView(rect: displayedImageRect)
            }
            .frame(
                width: geo.size.width,
                height: geo.size.height
            )
            .overlay(alignment: .top) {
                Text("\(image.size.width), \(image.size.height)")
                    .font(.headline)
                    .foregroundStyle(.white)
            }
        }
        .ignoresSafeArea()
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
        }
    }
}

#Preview {
    NavigationStack {
        CubeCropImageScreen()
    }
}

// MARK: - View
extension CubeCropImageScreen {
    private func imageView(rect: CGRect) -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: rect.width, height: rect.height)
    }
    
    private func editingView(rect: CGRect) -> some View {
        Color.black.opacity(0.7)
            .overlay {
                frameView(rect: rect)
            }
            .compositingGroup()
    }
    
    private func frameView(rect: CGRect) -> some View {
        Rectangle()
            .frame(width: cropRect.width, height: cropRect.height)
            .blendMode(.destinationOut)
            .overlay(alignment: .topLeading) { cornerDragView(.topLeading, rect: rect) }
            .overlay(alignment: .top) { cornerDragView(.top, rect: rect) }
            .overlay(alignment: .topTrailing) { cornerDragView(.topTrailing, rect: rect) }
            .overlay(alignment: .bottomLeading) { cornerDragView(.bottomLeading, rect: rect) }
            .overlay(alignment: .bottom) { cornerDragView(.bottom, rect: rect) }
            .overlay(alignment: .bottomTrailing) { cornerDragView(.bottomTrailing, rect: rect) }
            .onAppear {
                guard cropRect == .zero else { return }
                cropRect = rect
            }
            .position(
                x: cropRect.midX,
                y: cropRect.midY
            )
            .offset(dragTranslation)
            .gesture(
                DragGesture()
                    .updating($dragTranslation) { value, state, _ in
                        state = clampedTranslation(
                            value.translation,
                            cropRect: cropRect,
                            imageRect: rect
                        )
                    }
                    .onEnded { value in
                        let translation = clampedTranslation(
                            value.translation,
                            cropRect: cropRect,
                            imageRect: rect
                        )
                        
                        cropRect.origin.x += translation.width
                        cropRect.origin.y += translation.height
                    }
            )
    }
    
    private func cornerDragView(_ type: CornerType, rect: CGRect) -> some View {
        let needHide = (type == .top || type == .bottom) && hideMiddleControl
        return Image(type.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .opacity(needHide ? 0.0 : 1.0)
            .disabled(needHide)
            .padding(.leading, type.leadingPadding)
            .padding(.trailing, type.trailingPadding)
            .padding(.top, type.topPadding)
            .padding(.bottom, type.bottomPadding)
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        if resizeStartRect == nil {
                            resizeStartRect = cropRect
                        }
                        
                        guard let startRect = resizeStartRect else { return }
                        cropRect = updateCropSize(
                            type,
                            rect: rect,
                            startRect: startRect,
                            translation: value.translation
                        )
                        
                        hideMiddleControl = cropRect.width < 100
                    }
                    .onEnded { _ in
                        resizeStartRect = nil
                    }
            )
    }
    
    private var saveButton: some View {
        Button {
            
        } label: {
            Text("Save")
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Logic
extension CubeCropImageScreen {
    private func getImageRect(in containerSize: CGSize) -> CGRect {
        let scale = min(
            containerSize.width / image.size.width,
            containerSize.height / image.size.height
        )
        
        let width = image.size.width * scale
        let height = image.size.height * scale
        
        return CGRect(
            x: (containerSize.width - width) / 2,
            y: (containerSize.height - height) / 2,
            width: width,
            height: height
        )
    }
    
    private func clampedTranslation(_ translation: CGSize, cropRect: CGRect, imageRect: CGRect) -> CGSize {
        // 1. 計算裁切框允許移動的最大、最小座標
        let minX = imageRect.minX
        let maxX = imageRect.maxX - cropRect.width
        let minY = imageRect.minY
        let maxY = imageRect.maxY - cropRect.height

        // 2. 計算拖曳後的新位置，並限制在圖片範圍內
        let newX = min(max(cropRect.minX + translation.width, minX), maxX)
        let newY = min(max(cropRect.minY + translation.height, minY), maxY)

        // 3. 將絕對位置轉換成相對位移，供 .offset() 使用
        return CGSize(width: newX - cropRect.minX, height: newY - cropRect.minY)
    }
    
    private func updateCropSize(_ type: CornerType, rect: CGRect, startRect: CGRect, translation: CGSize) -> CGRect {
        var minX = startRect.minX
        var maxX = startRect.maxX
        var minY = startRect.minY
        var maxY = startRect.maxY
        
        let isTop = type == .top || type == .topLeading || type == .topTrailing
        let isBottom = type == .bottom || type == .bottomLeading || type == .bottomTrailing
        let isLeft = type == .topLeading || type == .bottomLeading
        let isRight = type == .topTrailing || type == .bottomTrailing
        
        if isLeft {
            minX = max(
                rect.minX,
                min(startRect.minX + translation.width, maxX - minCropSize.width)
            )
        }
        
        if isRight {
            maxX = min(
                rect.maxX,
                max(startRect.maxX + translation.width, minX + minCropSize.width)
            )
        }
        
        if isTop {
            minY = max(
                rect.minY,
                min(startRect.minY + translation.height, maxY - minCropSize.height)
            )
        }
        
        if isBottom {
            maxY = min(
                rect.maxY,
                max(startRect.maxY + translation.height, minY + minCropSize.height)
            )
        }
        
        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
    
    private func getCGImage(from image: UIImage) -> CGImage? {
        if let cgImage = image.cgImage {
            return cgImage
        }

        if let ciImage = image.ciImage {
            return CIContext().createCGImage(
                ciImage,
                from: ciImage.extent
            )
        }
        return nil
    }
    
    private func cropImage( _ cgImage: CGImage, rect: CGRect) -> UIImage? {
        guard let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: croppedCGImage)
    }
}
