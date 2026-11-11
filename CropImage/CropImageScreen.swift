//
//  CropImageScreen.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI
import UIKit

struct CroppedImage: Identifiable {
    let id = UUID().uuidString
    let image: UIImage
}

struct CropImageScreen: View {

    // MARK: - Image

    private let image: UIImage = UIImage(resource: .test)

    private let horizontalPadding: CGFloat = 45
    private let verticalPadding: CGFloat = 30

    // MARK: - Crop

    /// 裁切框,以「圖片寬高的比例」表示(0...1)。
    /// 因為與顯示尺寸無關,旋轉或尺寸改變時不需要另外同步。
    @State private var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)

    /// 本次拖曳(移動或縮放)開始時的裁切框快照,放手後清除。
    @State private var dragStartRect: CGRect?

    @State private var afterCropImage: CroppedImage?

    /// 裁切框最小尺寸(單位:pt)。
    private let minCropSize = CGSize(width: 80, height: 80)

    /// 裁切框寬度(單位:pt)小於此值時,隱藏上下中間的控制點。
    private let hideMiddleControlWidth: CGFloat = 100

    // MARK: - Body

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .overlay {
                // overlay 的尺寸 = 圖片實際顯示尺寸,不需要手動計算
                GeometryReader { geo in
                    cropOverlay(imageSize: geo.size)
                }
            }
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.black.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    saveButton
                }
            }
            .sheet(item: $afterCropImage) { croppedImage in
                Image(uiImage: croppedImage.image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
            }
    }
}

// MARK: - Preview
#Preview {
    NavigationView {
        CropImageScreen()
    }
}

// MARK: - Views
private extension CropImageScreen {

    func cropOverlay(imageSize: CGSize) -> some View {
        let rect = cropRect.scaled(to: imageSize)

        return ZStack(alignment: .topLeading) {
            dimmingMask(imageSize: imageSize, cropRect: rect)
            frameView(rect: rect, imageSize: imageSize)
        }
        .frame(width: imageSize.width, height: imageSize.height)
    }

    /// 裁切框外的半透明遮罩:外框 + 裁切框,以 even-odd 規則挖空中間。
    func dimmingMask(imageSize: CGSize, cropRect: CGRect) -> some View {
        Path { path in
            path.addRect(CGRect(origin: .zero, size: imageSize))
            path.addRect(cropRect)
        }
        .fill(Color.black.opacity(0.7), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)
    }

    /// 裁切框本體:可拖曳移動,並在周圍放置控制點。
    func frameView(rect: CGRect, imageSize: CGSize) -> some View {
        Color.clear
            .frame(width: rect.width, height: rect.height)
            .contentShape(Rectangle())
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
            .gesture(moveGesture(imageSize: imageSize))
            .offset(x: rect.minX, y: rect.minY)
    }

    func cornerDragView(_ type: CropHandle, imageSize: CGSize) -> some View {
        let needHide = (type == .top || type == .bottom) && shouldHideMiddleControl(imageSize: imageSize)

        return Image(type.image)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: 40, height: 40)
            .opacity(needHide ? 0 : 1)
            .padding(.leading, type.leadingPadding)
            .padding(.trailing, type.trailingPadding)
            .padding(.top, type.topPadding)
            .padding(.bottom, type.bottomPadding)
            .gesture(resizeGesture(type, imageSize: imageSize))
            // 隱藏時也要關閉 hit testing,否則看不見的控制點仍然可以拖曳
            .allowsHitTesting(!needHide)
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

// MARK: - Gestures

private extension CropImageScreen {

    /// 移動、縮放都會讓裁切框(以及掛著手勢的 view)跟著位移,
    /// 所以一律使用 .global 座標,避免 translation 因 view 移動而回饋抖動。
    func moveGesture(imageSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let startRect = captureDragStartRect().scaled(to: imageSize)
                let translation = clampedTranslation(
                    value.translation,
                    rect: startRect,
                    imageSize: imageSize
                )

                cropRect = startRect
                    .offsetBy(dx: translation.width, dy: translation.height)
                    .normalized(in: imageSize)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    func resizeGesture(_ type: CropHandle, imageSize: CGSize) -> some Gesture {
        DragGesture(coordinateSpace: .global)
            .onChanged { value in
                let startRect = captureDragStartRect().scaled(to: imageSize)

                cropRect = updateCropSize(
                    type,
                    imageSize: imageSize,
                    startRect: startRect,
                    translation: value.translation
                )
                .normalized(in: imageSize)
            }
            .onEnded { _ in
                dragStartRect = nil
            }
    }

    /// 取得本次拖曳開始時的裁切框(只會在拖曳的第一次呼叫時記錄)。
    func captureDragStartRect() -> CGRect {
        let startRect = dragStartRect ?? cropRect
        dragStartRect = startRect
        return startRect
    }

    func shouldHideMiddleControl(imageSize: CGSize) -> Bool {
        cropRect.width * imageSize.width < hideMiddleControlWidth
    }
}

// MARK: - Drag Logic

private extension CropImageScreen {

    /// 限制位移量,讓裁切框不會超出圖片範圍。
    func clampedTranslation(_ translation: CGSize, rect: CGRect, imageSize: CGSize) -> CGSize {
        CGSize(
            width: min(max(translation.width, -rect.minX), imageSize.width - rect.maxX),
            height: min(max(translation.height, -rect.minY), imageSize.height - rect.maxY)
        )
    }
}

// MARK: - Resize Logic

private extension CropImageScreen {

    /// 所有參數與回傳值皆為「圖片顯示座標」(pt)。
    func updateCropSize(_ type: CropHandle, imageSize: CGSize, startRect: CGRect, translation: CGSize) -> CGRect {

        var minX = startRect.minX
        var maxX = startRect.maxX

        var minY = startRect.minY
        var maxY = startRect.maxY

        let minWidth = min(minCropSize.width, imageSize.width)
        let minHeight = min(minCropSize.height, imageSize.height)

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
            minX = max(0,
                min(startRect.minX + translation.width, maxX - minWidth)
            )
        }

        if isRight {
            maxX = min(
                imageSize.width,
                max(startRect.maxX + translation.width, minX + minWidth)
            )
        }

        if isTop {
            minY = max(
                0,
                min(startRect.minY + translation.height, maxY - minHeight)
            )
        }

        if isBottom {
            maxY = min(
                imageSize.height,
                max(startRect.maxY + translation.height, minY + minHeight)
            )
        }

        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}

// MARK: - Image Processing

private extension CropImageScreen {

    /// 依正規化裁切框(0...1)裁切圖片,輸出 scale = 1、方向正確的圖片,
    /// 像素尺寸即為實際裁切的像素大小。
    /// 只繪製裁切區域,不需要先把整張原圖重繪一次;UIImage.draw 會自動處理 imageOrientation。
    func crop(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )

        let pixelRect = normalizedRect
            .scaled(to: pixelSize)
            .integral
            .intersection(CGRect(origin: .zero, size: pixelSize))

        guard !pixelRect.isNull, pixelRect.width > 0, pixelRect.height > 0 else {
            return nil
        }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1  // 讓 1pt = 1px,輸出尺寸即實際像素

        return UIGraphicsImageRenderer(size: pixelRect.size, format: format).image { _ in
            image.draw(in: CGRect(
                x: -pixelRect.minX,
                y: -pixelRect.minY,
                width: pixelSize.width,
                height: pixelSize.height
            ))
        }
    }

    /// 執行裁切。
    func saveCroppedImage() {
        guard let croppedImage = crop(image, normalizedRect: cropRect) else {
            print("圖片裁切失敗")
            return
        }

        afterCropImage = CroppedImage(image: croppedImage)

        // TODO: 將 croppedImage.jpegData(compressionQuality: 0.85) 傳給 API
    }
}

// MARK: - CGRect Helpers

private extension CGRect {

    /// 將「比例座標」轉成指定尺寸下的實際座標。
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width,
               y: minY * size.height,
               width: width * size.width,
               height: height * size.height)
    }

    /// 將指定尺寸下的實際座標轉成「比例座標」。
    func normalized(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return self }
        return CGRect(x: minX / size.width,
                      y: minY / size.height,
                      width: width / size.width,
                      height: height / size.height)
    }
}
