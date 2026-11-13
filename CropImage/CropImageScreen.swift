//
//  CropImageScreen.swift
//  MyApp
//
//  Created by Yen Lin on 2026/10/18.
//

import SwiftUI
import UIKit
import Combine

struct CroppedImage: Identifiable {
    let id = UUID().uuidString
    let image: UIImage
}

/// UIKit 與 SwiftUI 共用已套用的編輯資料。三個數值都不依賴畫面 pt 尺寸。
final class CropImageViewModel: ObservableObject {
    /// 相對「固定編輯容器」的比例，並非放大後的原圖裁切比例。
    @Published var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
    @Published var zoomScale: CGFloat = 1
    /// 圖片中心相對容器中心的位移，分別除以容器寬高後儲存。
    @Published var imageOffset: CGSize = .zero
}

struct CropImageScreen: View {
    @ObservedObject private var vm: CropImageViewModel
    private let inputImage: UIImage
    private let onCropped: ((UIImage) -> Void)?
    private let minCropSize = CGSize(width: 80, height: 80)

    @State private var activeTarget: DragTarget?
    @State private var lastTranslation: CGSize?
    @State private var zoomStartScale: CGFloat?
    @State private var showCropError = false
    // GestureState 在手勢結束「或被系統取消」時，都會自動清除。
    @GestureState private var isDragging = false
    @GestureState private var isZooming = false
    @GestureState private var isResizing = false

    private enum DragTarget {
        case image, frame, handle(CropHandle)
    }

    init(vm: CropImageViewModel, inputImage: UIImage, onCropped: ((UIImage) -> Void)? = nil) {
        self.vm = vm
        self.inputImage = inputImage
        self.onCropped = onCropped
    }

    var body: some View {
        GeometryReader { geometry in
            let size = fittedSize(image: inputImage.size, available: geometry.size)
            editor(size: size)
                .frame(width: geometry.size.width, height: geometry.size.height)
                .onAppear { updateLayout(size) }
                .onChange(of: size) { updateLayout($0) }
        }
        // 先扣掉 padding，再讓 GeometryReader 量測可用區域。
        .padding(.horizontal, 40)
        .padding(.vertical, 12)
        .background(Color.black.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if onCropped != nil {
                    Button("Save") {
                        guard let image = getCroppedImage() else {
                            showCropError = true
                            return
                        }
                        onCropped?(image)
                    }
                    .disabled(isDragging || isResizing || isZooming)
                }
            }
        }
        .alert("無法裁切圖片", isPresented: $showCropError) {
            Button("確定", role: .cancel) { }
        } message: {
            Text("請重新調整選取範圍後再試一次。")
        }
        .onChange(of: isDragging || isResizing || isZooming) { active in
            guard !active else { return }
            activeTarget = nil
            lastTranslation = nil
            zoomStartScale = nil
            withAnimation(.easeOut(duration: 0.2)) {
                vm.imageOffset = correctedOffset(vm.imageOffset, scale: vm.zoomScale, crop: vm.cropRect)
            }
        }
        .onChange(of: isDragging || isResizing) { active in
            // 拖曳結束或取消時清除位移，即使捏合仍在進行也一樣。
            if !active { lastTranslation = nil }
        }
        .onChange(of: isZooming) { active in
            // 單雙指切換後重取拖曳基準；取消捏合也要清除倍率基準。
            lastTranslation = nil
            if !active { zoomStartScale = nil }
        }
    }
}

private extension CropImageScreen {
    func editor(size: CGSize) -> some View {
        let rect = vm.cropRect.scaled(to: size)
        return ZStack(alignment: .topLeading) {
            // 第 1 層：只有圖片接受變形。先縮放，再移動中心。
            Image(uiImage: inputImage)
                .resizable()
                .frame(width: size.width, height: size.height)
                .scaleEffect(vm.zoomScale)
                .offset(x: vm.imageOffset.width * size.width,
                        y: vm.imageOffset.height * size.height)
                .allowsHitTesting(false)

            // 第 2 層：even-odd 填色，兩個矩形重疊處挖空。
            Path { path in
                path.addRect(CGRect(origin: .zero, size: size))
                path.addRect(rect)
            }
            .fill(Color.black.opacity(0.6), style: FillStyle(eoFill: true))
            .allowsHitTesting(false)

            // 固定區域接移圖／移框手勢，控制點則在上層自行接 resize。
            Color.clear
                .contentShape(Rectangle())
                .gesture(dragGesture(size: size))

            // 第 3 層：用 alignment 排列控制點，不再手算位置與命中矩形。
            frameView(rect: rect, imageSize: size)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .simultaneousGesture(zoomGesture)
    }

    func frameView(rect: CGRect, imageSize: CGSize) -> some View {
        Rectangle()
            .strokeBorder(Color.white, lineWidth: 1)
            .frame(width: rect.width, height: rect.height)
            // 框線本身不攔截觸控，內部與邊線交給底下固定區域處理。
            .allowsHitTesting(false)
            .overlay(alignment: .topLeading) {
                cropHandleView(.topLeading, rect: rect, imageSize: imageSize)
            }
            .overlay(alignment: .top) {
                cropHandleView(.top, rect: rect, imageSize: imageSize)
            }
            .overlay(alignment: .topTrailing) {
                cropHandleView(.topTrailing, rect: rect, imageSize: imageSize)
            }
            .overlay(alignment: .bottomLeading) {
                cropHandleView(.bottomLeading, rect: rect, imageSize: imageSize)
            }
            .overlay(alignment: .bottom) {
                cropHandleView(.bottom, rect: rect, imageSize: imageSize)
            }
            .overlay(alignment: .bottomTrailing) {
                cropHandleView(.bottomTrailing, rect: rect, imageSize: imageSize)
            }
            .offset(x: rect.minX, y: rect.minY)
    }

    func cropHandleView(_ handle: CropHandle, rect: CGRect, imageSize: CGSize) -> some View {
        let hidden = shouldHideMiddleControl(handle, rect: rect)
        // 小框縮小控制點，保留框邊移框與中央移圖的空間。
        let size = min(44, min(rect.width / 4, rect.height / 3))
        return Image(handle.image)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundColor(.white)
            .frame(width: size, height: size)
            .contentShape(Rectangle())
            .opacity(hidden ? 0 : 1)
            .gesture(resizeGesture(handle, imageSize: imageSize))
            .allowsHitTesting(!hidden)
    }

    func shouldHideMiddleControl(_ handle: CropHandle, rect: CGRect) -> Bool {
        (handle == .top || handle == .bottom) && rect.width < 100
    }

    /// 控制點由自身 View 接手勢；這裡只區分框邊與圖片。
    private func dragTarget(at point: CGPoint, rect: CGRect) -> DragTarget {
        // 窄框同步縮小邊線觸控區，保留中央區域供移圖。
        let edgeWidth = min(24, min(rect.width, rect.height) / 6)
        if rect.contains(point) && !rect.insetBy(dx: edgeWidth, dy: edgeWidth).contains(point) {
            return .frame
        }
        return .image
    }

    func dragGesture(size: CGSize) -> some Gesture {
        // 固定區域用 .local 判斷手指起點是在框邊或框內。
        DragGesture(coordinateSpace: .local)
            .updating($isDragging) { _, active, _ in active = true }
            .onChanged { value in
                let target = dragTarget(at: value.startLocation, rect: vm.cropRect.scaled(to: size))
                updateDrag(value.translation, target: target, imageSize: size)
            }
    }

    func resizeGesture(_ handle: CropHandle, imageSize: CGSize) -> some Gesture {
        // 控制點會跟著框移動，因此用 .global 的位移，避免局部原點跟著改變。
        DragGesture(coordinateSpace: .global)
            .updating($isResizing) { _, active, _ in active = true }
            .onChanged { value in
                updateDrag(value.translation, target: .handle(handle), imageSize: imageSize)
            }
    }

    /// 兩種拖曳共用增量計算；操作目標只在起點決定，捏合後改為移圖。
    private func updateDrag(_ translation: CGSize, target: DragTarget, imageSize: CGSize) {
        guard imageSize.width > 0, imageSize.height > 0 else { return }
        if activeTarget == nil {
            activeTarget = isZooming ? .image : target
            lastTranslation = .zero
        }
        // 單雙指切換後先記錄新基準，不套用觸點中心改變造成的位移。
        let previous = lastTranslation ?? translation
        let delta = CGSize(width: translation.width - previous.width,
                           height: translation.height - previous.height)
        lastTranslation = translation
        let rect = vm.cropRect.scaled(to: imageSize)
        switch activeTarget {
        case .image:
            vm.imageOffset.width += delta.width / imageSize.width
            vm.imageOffset.height += delta.height / imageSize.height
        case .frame:
            vm.cropRect = movedRect(rect, by: delta, in: imageSize).normalized(in: imageSize)
        case .handle(let handle):
            vm.cropRect = resizedRect(rect, handle: handle, by: delta, in: imageSize).normalized(in: imageSize)
        case nil: break
        }
    }

    var zoomGesture: some Gesture {
        MagnificationGesture()
            .updating($isZooming) { _, active, _ in active = true }
            .onChanged { magnification in
                if zoomStartScale == nil {
                    zoomStartScale = vm.zoomScale
                    // 到整輪觸控結束前，剩下一指也繼續移圖，不切回移框。
                    activeTarget = .image
                    lastTranslation = nil
                }
                vm.zoomScale = clamp((zoomStartScale ?? 1) * magnification, 1, 3)
            }
    }

    func updateLayout(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        lastTranslation = nil
        vm.zoomScale = clamp(vm.zoomScale, 1, 3)
        vm.cropRect = constrainedRect(vm.cropRect.scaled(to: size), in: size).normalized(in: size)
        vm.imageOffset = correctedOffset(vm.imageOffset, scale: vm.zoomScale, crop: vm.cropRect)
    }
}

extension CropImageScreen {
    /// 使用修正後的快照輸出，不依賴畫面修正動畫是否已播放完成。
    func getCroppedImage() -> UIImage? {
        let scale = clamp(vm.zoomScale, 1, 3)
        let offset = correctedOffset(vm.imageOffset, scale: scale, crop: vm.cropRect)
        let sourceRect = sourceRect(crop: vm.cropRect, scale: scale, offset: offset)
        return crop(inputImage, normalizedRect: sourceRect)
    }

    private func crop(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        let pixelSize = CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0,
              [normalizedRect.minX, normalizedRect.minY, normalizedRect.width, normalizedRect.height]
                .allSatisfy({ $0.isFinite }) else { return nil }
        let pixelRect = normalizedRect.scaled(to: pixelSize).integral
            .intersection(CGRect(origin: .zero, size: pixelSize))
        guard !pixelRect.isNull, pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelRect.size, format: format).image { _ in
            // 小畫布只留下選取區；負號把選取區左上角移到畫布 (0, 0)。
            // UIImage.draw 會處理 imageOrientation，無須手動翻轉 CGImage 座標。
            image.draw(in: CGRect(x: -pixelRect.minX, y: -pixelRect.minY,
                                  width: pixelSize.width, height: pixelSize.height))
        }
    }
}

// MARK: - 座標計算

private extension CropImageScreen {
    func fittedSize(image: CGSize, available: CGSize) -> CGSize {
        guard image.width > 0, image.height > 0 else { return .zero }
        let factor = max(0, min(available.width / image.width, available.height / image.height))
        return CGSize(width: image.width * factor, height: image.height * factor)
    }

    func constrainedRect(_ rect: CGRect, in size: CGSize) -> CGRect {
        let width = min(size.width, max(min(minCropSize.width, size.width), rect.width))
        let height = min(size.height, max(min(minCropSize.height, size.height), rect.height))
        return CGRect(x: clamp(rect.midX - width / 2, 0, size.width - width),
                      y: clamp(rect.midY - height / 2, 0, size.height - height),
                      width: width, height: height)
    }

    func movedRect(_ rect: CGRect, by translation: CGSize, in size: CGSize) -> CGRect {
        CGRect(x: clamp(rect.minX + translation.width, 0, size.width - rect.width),
               y: clamp(rect.minY + translation.height, 0, size.height - rect.height),
               width: rect.width, height: rect.height)
    }

    func resizedRect(_ rect: CGRect, handle: CropHandle, by translation: CGSize, in size: CGSize) -> CGRect {
        var left = rect.minX, right = rect.maxX
        var top = rect.minY, bottom = rect.maxY
        let minWidth = min(minCropSize.width, size.width), minHeight = min(minCropSize.height, size.height)
        switch handle {
        case .topLeading, .bottomLeading:
            left = clamp(left + translation.width, 0, right - minWidth)
        case .topTrailing, .bottomTrailing:
            right = clamp(right + translation.width, left + minWidth, size.width)
        default: break
        }
        switch handle {
        case .topLeading, .top, .topTrailing:
            top = clamp(top + translation.height, 0, bottom - minHeight)
        case .bottomLeading, .bottom, .bottomTrailing:
            bottom = clamp(bottom + translation.height, top + minHeight, size.height)
        }
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// 圖片位移、裁切框都已是比例，回正不用再乘除畫面尺寸。
    func correctedOffset(_ offset: CGSize, scale: CGFloat, crop: CGRect) -> CGSize {
        let extra = (scale - 1) / 2
        return CGSize(width: clamp(offset.width, crop.maxX - 1 - extra, crop.minX + extra),
                      height: clamp(offset.height, crop.maxY - 1 - extra, crop.minY + extra))
    }

    /// 這裡全部使用比例，因此不需要知道容器目前有幾 pt。
    /// 先扣掉圖片左上角，再除以放大後的寬高，回到完整原圖的 0...1 座標。
    func sourceRect(crop: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        let left = (1 - scale) / 2 + offset.width
        let top = (1 - scale) / 2 + offset.height
        return CGRect(x: (crop.minX - left) / scale, y: (crop.minY - top) / scale,
                      width: crop.width / scale, height: crop.height / scale)
    }

    func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
}

private extension CGRect {
    /// 比例 → 指定區域內的 pt 或 px；不會自行限制邊界。
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width,
               y: minY * size.height,
               width: width * size.width,
               height: height * size.height)
    }

    /// pt 或 px → 比例；normalized 不代表自動限制在 0...1。
    func normalized(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(x: minX / size.width,
                      y: minY / size.height,
                      width: width / size.width,
                      height: height / size.height)
    }
}
#Preview {
    NavigationView {
        CropImageScreen(vm: CropImageViewModel(),
                        inputImage: UIImage(named: "test")!) { outputImage in

        }
    }
}
