//
//  CropImageScreen.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI
import UIKit
import CoreImage

struct CroppedImage: Identifiable {
    let id = UUID().uuidString
    let image: UIImage
}

struct CubeCropImageScreen: View {

    // MARK: - Image

    private let image: UIImage = UIImage(resource: .test)

    private let horizontalPadding: CGFloat = 45
    private let verticalPadding: CGFloat = 30

    // MARK: - Crop

    @State private var cropRect: CGRect = .zero
    @State private var previousImageSize: CGSize = .zero
    @State private var hideMiddleControl = false
    @State private var afterCropImage: CroppedImage? = nil

    @GestureState private var dragTranslation: CGSize = .zero

    private let minCropSize = CGSize(width: 80, height: 80)

    // MARK: - Resize

    @State private var resizeStartRect: CGRect?

    // MARK: - Body

    var body: some View {
        GeometryReader { geo in
            let imageSize = getImageSize(in: geo.size)

            ZStack {
                Color.black.ignoresSafeArea()

                ZStack {
                    imageView()
                    editingView(imageSize: imageSize)
                }
                .frame(
                    width: imageSize.width,
                    height: imageSize.height
                )
                .position(
                    x: geo.size.width / 2,
                    y: geo.size.height / 2
                )
            }
            .frame(
                width: geo.size.width,
                height: geo.size.height
            )
            .onAppear {
                updateCropRect(for: imageSize)
            }
            .onChange(of: imageSize) { newSize in
                updateCropRect(for: newSize)
            }
            .sheet(item: $afterCropImage) { croppedImage in
                Image(uiImage: croppedImage.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                saveButton
            }
        }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        CubeCropImageScreen()
    }
}

// MARK: - Views
private extension CubeCropImageScreen {
    func imageView() -> some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
    }

    func editingView(imageSize: CGSize) -> some View {
        Color.black.opacity(0.7)
            .overlay {
                frameView(imageSize: imageSize)
            }
            .compositingGroup()
    }

    func frameView(imageSize: CGSize) -> some View {
        Rectangle()
            .frame(width: cropRect.width, height: cropRect.height)
            .blendMode(.destinationOut)
            .overlay(alignment: .topLeading) {
                cornerDragView(.topLeading, imageSize: imageSize)
            }
            .overlay(alignment: .top) {
                cornerDragView(.top, imageSize: imageSize)
            }
            .overlay(alignment: .topTrailing) {
                cornerDragView(.topTrailing, imageSize: imageSize)
            }
            .overlay(alignment: .bottomLeading) {
                cornerDragView(.bottomLeading, imageSize: imageSize)
            }
            .overlay(alignment: .bottom) {
                cornerDragView(.bottom, imageSize: imageSize)
            }
            .overlay(alignment: .bottomTrailing) {
                cornerDragView(.bottomTrailing, imageSize: imageSize)
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
                            imageSize: imageSize
                        )
                    }
                    .onEnded { value in
                        let translation = clampedTranslation(
                            value.translation,
                            cropRect: cropRect,
                            imageSize: imageSize
                        )

                        cropRect.origin.x += translation.width
                        cropRect.origin.y += translation.height
                    }
            )
    }

    func cornerDragView(_ type: CornerType, imageSize: CGSize) -> some View {
        let needHide = (type == .top || type == .bottom) && hideMiddleControl
        return Image(type.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .opacity(needHide ? 0 : 1)
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
                            imageSize: imageSize,
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

    var saveButton: some View {
        Button {
            saveCroppedImage()
            
        } label: {
            Text("Save")
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

// MARK: - Layout

private extension CubeCropImageScreen {

    func getImageSize(in containerSize: CGSize) -> CGSize {

        let availableWidth = max(0, containerSize.width - horizontalPadding * 2)
        let availableHeight = max(0, containerSize.height - verticalPadding * 2)

        guard image.size.width > 0, image.size.height > 0 else {
            return .zero
        }

        let scale = min(
            availableWidth / image.size.width,
            availableHeight / image.size.height
        )

        return CGSize(
            width: image.size.width * scale,
            height: image.size.height * scale
        )
    }

    /// 初始化裁切框，或在圖片顯示尺寸改變時保留原本的裁切比例。
    func updateCropRect(for imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return
        }

        guard previousImageSize != imageSize else {
            return
        }

        defer {
            previousImageSize = imageSize
        }

        guard previousImageSize.width > 0,
              previousImageSize.height > 0 else {

            cropRect = CGRect(
                origin: .zero,
                size: imageSize
            )

            return
        }

        let scaleX = imageSize.width / previousImageSize.width
        let scaleY = imageSize.height / previousImageSize.height

        cropRect = CGRect(
            x: cropRect.minX * scaleX,
            y: cropRect.minY * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        )

        // 尺寸改變後，重新限制裁切框的位置與大小。
        cropRect = cropRect.intersection(
            CGRect(origin: .zero, size: imageSize)
        )

        hideMiddleControl = cropRect.width < 100
    }
}

// MARK: - Drag Logic

private extension CubeCropImageScreen {

    func clampedTranslation(_ translation: CGSize, cropRect: CGRect, imageSize: CGSize) -> CGSize {

        let minX: CGFloat = 0
        let maxX = max(0, imageSize.width - cropRect.width)

        let minY: CGFloat = 0
        let maxY = max(0, imageSize.height - cropRect.height)

        let newX = min(
            max(cropRect.minX + translation.width, minX),
            maxX
        )

        let newY = min(
            max(cropRect.minY + translation.height, minY),
            maxY
        )

        return CGSize(
            width: newX - cropRect.minX,
            height: newY - cropRect.minY
        )
    }
}

// MARK: - Resize Logic

private extension CubeCropImageScreen {

    func updateCropSize(_ type: CornerType, imageSize: CGSize, startRect: CGRect, translation: CGSize) -> CGRect {

        var minX = startRect.minX
        var maxX = startRect.maxX

        var minY = startRect.minY
        var maxY = startRect.maxY

        let minWidth = min(
            minCropSize.width,
            imageSize.width
        )

        let minHeight = min(
            minCropSize.height,
            imageSize.height
        )

        let isTop =
            type == .top ||
            type == .topLeading ||
            type == .topTrailing

        let isBottom =
            type == .bottom ||
            type == .bottomLeading ||
            type == .bottomTrailing

        let isLeft =
            type == .topLeading ||
            type == .bottomLeading

        let isRight =
            type == .topTrailing ||
            type == .bottomTrailing

        if isLeft {
            minX = max(
                0,
                min(
                    startRect.minX + translation.width,
                    maxX - minWidth
                )
            )
        }

        if isRight {
            maxX = min(
                imageSize.width,
                max(
                    startRect.maxX + translation.width,
                    minX + minWidth
                )
            )
        }

        if isTop {
            minY = max(
                0,
                min(
                    startRect.minY + translation.height,
                    maxY - minHeight
                )
            )
        }

        if isBottom {
            maxY = min(
                imageSize.height,
                max(
                    startRect.maxY + translation.height,
                    minY + minHeight
                )
            )
        }

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

// MARK: - Image Processing

private extension CubeCropImageScreen {

    /// 將 UIImage 渲染成方向正確的 CGImage。
    func getCGImage(from image: UIImage) -> CGImage? {

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1

        let renderer = UIGraphicsImageRenderer(
            size: image.size,
            format: format
        )

        let normalizedImage = renderer.image { _ in
            image.draw(
                in: CGRect(
                    origin: .zero,
                    size: image.size
                )
            )
        }

        return normalizedImage.cgImage
    }

    /// 將圖片內部座標轉換為 Pixel 座標。
    func getPixelCropRect(
        cropRect: CGRect,
        imageSize: CGSize,
        cgImage: CGImage
    ) -> CGRect? {

        guard imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        let scaleX = CGFloat(cgImage.width) / imageSize.width
        let scaleY = CGFloat(cgImage.height) / imageSize.height

        let pixelRect = CGRect(
            x: cropRect.minX * scaleX,
            y: cropRect.minY * scaleY,
            width: cropRect.width * scaleX,
            height: cropRect.height * scaleY
        ).integral

        let imageBounds = CGRect(
            x: 0,
            y: 0,
            width: cgImage.width,
            height: cgImage.height
        )

        let validRect = pixelRect.intersection(imageBounds)

        guard !validRect.isNull,
              !validRect.isEmpty else {
            return nil
        }

        return validRect
    }

    /// 根據 Pixel 座標裁切圖片。
    func cropImage(_ cgImage: CGImage, rect: CGRect) -> UIImage? {
        guard let croppedCGImage = cgImage.cropping(to: rect) else {
            return nil
        }
        return UIImage(cgImage: croppedCGImage)
    }

    /// 執行裁切，並取得可供 API 上傳的 JPEG Data。
    func saveCroppedImage() {
        guard let cgImage = getCGImage(from: image) else {
            print("無法取得 CGImage")
            return
        }

        guard previousImageSize.width > 0,
              previousImageSize.height > 0 else {
            print("圖片顯示尺寸無效")
            return
        }

        guard let pixelCropRect = getPixelCropRect(
            cropRect: cropRect,
            imageSize: previousImageSize,
            cgImage: cgImage
        ) else {
            print("裁切範圍無效")
            return
        }

        guard let croppedImage = cropImage(cgImage, rect: pixelCropRect) else {
            print("圖片裁切失敗")
            return
        }
        
        afterCropImage = CroppedImage(image: croppedImage)
        
        // TODO: 將 imageData 傳給 API

//        guard let imageData = croppedImage.jpegData(compressionQuality: 0.85) else {
//            print("JPEG 轉換失敗")
//            return nil
//        }
//
//        print("裁切完成")
//        print("Pixel Rect:", pixelCropRect)
//        print("Image Size:", croppedImage.size)
//        print("JPEG Data:", imageData.count, "bytes")

    }
}
