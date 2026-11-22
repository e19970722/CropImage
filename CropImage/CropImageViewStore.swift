//
//  CropImageViewStore.swift
//  CropImage
//
//  Created by Yen Lin on 2026/11/22.
//

import SwiftUI
import Combine

/// `  選擇掃描區域` Store  (狀態容器)
final class CropImageViewStore: ObservableObject {
    
    // MARK: - Variables and Properties
    
    /// 當前狀態
    @Published private(set) var state: State
    
    /// 環境依賴
    private let environment: Environment
    
    /// 裁切框最小大小
    private let minCropSize: CGSize
    
    // MARK: - Init
    
    /// 初始化
    /// - Parameters:
    ///   - state: 初始化狀態
    ///   - environment: 環境依賴
    ///   - minCropSize: 裁切框最小大小
    init(initialState state: State,
         environment: Environment,
         minCropSize: CGSize) {
        self.state = state
        self.environment = environment
        self.minCropSize = minCropSize
    }
}

// MARK: - TCA Definition

extension CropImageViewStore {
    
    /// State 狀態
    struct State {
        /// 裁切框相對「固定編輯容器」的比例 (0-1)
        var cropRect = CGRect(x: 0, y: 0, width: 1, height: 1)
        /// 圖片放大的比例
        var zoomScale: CGFloat = 1
        /// 圖片中心相對容器中心的位移
        var imageOffset: CGSize = .zero
    }
    
    /// Action (行為)：定義所有可能的使用者互動和系統事件
    /// - cropRectChanged：裁切框相對「固定編輯容器」的比例改變
    /// - zoomScaleChanged：圖片放大的比例改變
    /// - imageOffsetChanged：圖片中心相對容器中心的位移改變
    /// - doneButtonOnTapped：點擊完成按鈕
    enum Action {
        /// 裁切框相對「固定編輯容器」的比例改變
        case cropRectChanged(rect: CGRect)
        /// 圖片放大的比例改變
        case zoomScaleChanged(scale: CGFloat)
        /// 圖片中心相對容器中心的位移改變
        case imageOffsetChanged(size: CGSize)
        /// 點擊完成按鈕
        case doneButtonOnTapped(inputImage: UIImage)
        /// 手勢運行中
        case gestureRunning
        /// 更新 Layout
        case updateLayout(size: CGSize)
        /// 圖片拖曳改變
        case imageDragChanged(deltaSize: CGSize, imageSize: CGSize)
        /// 裁切框的邊角控制項拖曳改變
        case cropHandleDragChanged(handle: CropHandle, deltaSize: CGSize, imageSize: CGSize)
        /// 縮放手勢改變
        case zoomGestureChanged(scale: CGFloat)
    }
    
    /// 環境依賴
    struct Environment {
        /// 點擊完成按鈕時，外部要處理的事
        var onDoneButtonOnTapped: ((_ outputImage: UIImage?) -> Void)? = nil
    }
}

// MARK: - Internal Method

extension CropImageViewStore {
    
    /// 發送 Action 以更新狀態
    /// - Parameter action: 要執行的行為
    func send(_ action: Action) {
        reduce(action)
    }
}

// MARK: - Private Method

private extension CropImageViewStore {
    
    /// Reducer (狀態處理器)，根據 Action 更新狀態
    /// - Parameter action: 要處理的行為
    func reduce(_ action: Action) {
        switch action {
        case let .cropRectChanged(rect):
            updateState {
                $0.cropRect = rect
            }
            
        case let .zoomScaleChanged(scale):
            updateState {
                $0.zoomScale = scale
            }
            
        case let .imageOffsetChanged(size):
            updateState {
                $0.imageOffset = size
            }
            
        case let .doneButtonOnTapped(image):
            environment.onDoneButtonOnTapped?(getCroppedImage(inputImage: image))
            
        case .gestureRunning:
            updateState {
                $0.imageOffset = correctedOffset(state.imageOffset, scale: state.zoomScale)
            }
            
        case let .updateLayout(size):
            updateState {
                $0.zoomScale = clamp(state.zoomScale, 1, 3)
                $0.cropRect = constrainedCropRect(state.cropRect.scaled(to: size), in: size, minSize: minCropSize).normalized(in: size)
                $0.imageOffset = correctedOffset(state.imageOffset, scale: state.zoomScale)
            }
            
        case let .imageDragChanged(deltaSize, imageSize):
            updateState {
                $0.imageOffset.width += deltaSize.width / imageSize.width
                $0.imageOffset.height += deltaSize.height / imageSize.height
            }
            
        case let .cropHandleDragChanged(handle, deltaSize, imageSize):
            updateState {
                let rect = state.cropRect.scaled(to: imageSize)
                $0.cropRect = resizedRect(rect, handle: handle, by: deltaSize, in: imageSize, minSize: minCropSize).normalized(in: imageSize)
            }
            
        case let .zoomGestureChanged(scale):
            updateState {
                $0.zoomScale = clamp(scale, 1, 3)
            }
        }
    }
    
    /// 統一更新狀態
    /// - Parameter update: 更新 state 的 closure
    func updateState(_ update: (inout State) -> Void) {
        var newState = state
        update(&newState)
        state = newState
    }
    
    /// 取得裁切後的圖片
    /// - Parameter inputImage: 要裁切的圖片
    /// - Returns: 裁切後的圖片
    func getCroppedImage(inputImage: UIImage) -> UIImage? {
        let scale = clamp(state.zoomScale, 1, 3)
        let offset = correctedOffset(state.imageOffset, scale: scale)
        let sourceRect = sourceRect(crop: state.cropRect, scale: scale, offset: offset)
        return crop(inputImage, normalizedRect: sourceRect)
    }
        
    /// 把裁切框限制在容器內：尺寸不小於最小值、不大於容器，位置不超出邊界。
    /// 尺寸需要調整時，以原本的中心點為基準再往容器內夾住。
    /// - Parameters:
    ///   - rect: 目前的裁切框位置與大小
    ///   - size: 編輯區域的大小
    ///   - minSize: 最小大小
    /// - Returns: 校正後的裁切框，保證不小於最小尺寸，且完整落在容器內。
    func constrainedCropRect(_ rect: CGRect, in size: CGSize, minSize: CGSize) -> CGRect {
        let width = clamp(rect.width, minSize.width, size.width)
        let height = clamp(rect.height, minSize.height, size.height)
        return CGRect(x: clamp(rect.midX - width / 2, 0, size.width - width),
                      y: clamp(rect.midY - height / 2, 0, size.height - height),
                      width: width,
                      height: height)
    }
    
    /// 縮放後的裁切框位置與大小
    /// - Parameters:
    ///   - rect: 目前的裁切框位置與大小
    ///   - handle: 使用哪一個邊角控制項
    ///   - translation: 拖曳的位移量
    ///   - size: 編輯區域的大小
    ///   - minSize: 最小大小
    /// - Returns: 縮放後的裁切框位置與大小
    func resizedRect(_ rect: CGRect, handle: CropHandle, by translation: CGSize, in size: CGSize, minSize: CGSize) -> CGRect {
        var left = rect.minX
        var right = rect.maxX
        var top = rect.minY
        var bottom = rect.maxY
        let minWidth = min(minSize.width, size.width)
        let minHeight = min(minSize.height, size.height)
        
        switch handle {
        case .topLeading, .bottomLeading:
            left = clamp(left + translation.width, 0, right - minWidth)
            
        case .topTrailing, .bottomTrailing:
            right = clamp(right + translation.width, left + minWidth, size.width)
            
        default:
            break
        }
        
        switch handle {
        case .topLeading, .top, .topTrailing:
            top = clamp(top + translation.height, 0, bottom - minHeight)
            
        case .bottomLeading, .bottom, .bottomTrailing:
            bottom = clamp(bottom + translation.height, top + minHeight, size.height)
        }
        
        return CGRect(x: left, y: top, width: right - left, height: bottom - top)
    }

    /// 限制最大位移量，讓圖片永遠填滿整個編輯區域
    /// - Parameters:
    ///   - offset: 真實位移量
    ///   - scale: 目前圖片縮放比例
    /// - Returns: 最大位移量
    func correctedOffset(_ offset: CGSize, scale: CGFloat) -> CGSize {
        // 由於目前只支援中心放大，所以上下左右的位移量相同
        let extra = (scale - 1) / 2
        // 得知 extra 位移量後去限制上下左右的位移量
        return CGSize(width: clamp(offset.width, -extra, extra),
                      height: clamp(offset.height, -extra, extra))
    }

    /// 把畫面上的裁切框，換算成原圖上對應的比例矩形（考慮放大與位移）
    /// - Parameters:
    ///   - crop: 裁切框位置與大小
    ///   - scale: 縮放比例
    ///   - offset: 圖片的位移量
    /// - Returns: 裁切框位於圖片原圖上的位置與大小
    func sourceRect(crop: CGRect, scale: CGFloat, offset: CGSize) -> CGRect {
        let left = (1 - scale) / 2 + offset.width
        let top = (1 - scale) / 2 + offset.height
        return CGRect(x: (crop.minX - left) / scale,
                      y: (crop.minY - top) / scale,
                      width: crop.width / scale,
                      height: crop.height / scale)
    }

    /// 把 value 限制在 lower...upper 之間。
    /// 若 lower > upper，結果以 upper 為準（先取下限、最後才套用上限）。
    /// - Parameters:
    ///   - value: 要限制的數值。
    ///   - lower: 下限。
    ///   - upper: 上限。
    /// - Returns: 落在 lower...upper 內的數值。
    func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        min(max(value, lower), upper)
    }
    
    /// 執行裁切圖片
    /// - Parameters:
    ///   - image: 原本的圖片
    ///   - normalizedRect: 裁切框在原圖上的位置與大小
    /// - Returns: 裁切後的圖片
    func crop(_ image: UIImage, normalizedRect: CGRect) -> UIImage? {
        // pt × scale = 原圖實際像素尺寸
        let pixelSize = CGSize(width: image.size.width * image.scale,
                               height: image.size.height * image.scale)
        guard pixelSize.width > 0, pixelSize.height > 0,
              [normalizedRect.minX, normalizedRect.minY, normalizedRect.width, normalizedRect.height]
                .allSatisfy({ $0.isFinite }) else { return nil }
        
        // 因像素不接受小數點，integral取整數
        // intersection 進行防呆避免超出原圖範圍
        let pixelRect = normalizedRect.scaled(to: pixelSize)
            .integral
            .intersection(CGRect(origin: .zero, size: pixelSize))
        guard !pixelRect.isNull, pixelRect.width > 0, pixelRect.height > 0 else { return nil }
        
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: pixelRect.size, format: format).image { _ in
            // 小畫布只留下選取區；負號把選取區左上角移到畫布 (0, 0)。
            image.draw(in: CGRect(x: -pixelRect.minX,
                                  y: -pixelRect.minY,
                                  width: pixelSize.width,
                                  height: pixelSize.height))
        }
    }
}

// MARK: - CGRect Extensions

private extension CGRect {
    /// 把「比例」換算成實際位置與大小
    /// - Parameter size: 基準的容器尺寸
    /// - Returns: 實際位置與大小
    func scaled(to size: CGSize) -> CGRect {
        CGRect(x: minX * size.width,
               y: minY * size.height,
               width: width * size.width,
               height: height * size.height)
    }

    /// 把「實際位置與大小」換算成比例
    /// - Parameter size: 基準的容器尺寸
    /// - Returns: 位置與大小的比例
    func normalized(in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(x: minX / size.width,
                      y: minY / size.height,
                      width: width / size.width,
                      height: height / size.height)
    }
}
