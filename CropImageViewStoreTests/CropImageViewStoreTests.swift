//
//  CropImageViewStoreTests.swift
//  CropImageViewStoreTests
//
//  Created by Yen Lin on 2026/11/22.
//

import XCTest
@testable import CropImage

final class CropImageViewStoreTests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    func testExample() throws {
        // This is an example of a functional test case.
        // Use XCTAssert and related functions to verify your tests produce the correct results.
        // Any test you write for XCTest can be annotated as throws and async.
        // Mark your test throws to produce an unexpected failure when your test encounters an uncaught error.
        // Mark your test async to allow awaiting for asynchronous code to complete. Check the results with assertions afterwards.
        // XCTest Documentation
        // https://developer.apple.com/documentation/xctest
    }

    func testPerformanceExample() throws {
        // This is an example of a performance test case.
        measure {
            // Put the code you want to measure the time of here.
        }
    }
    
    func makeStore(state: CropImageViewStore.State) -> CropImageViewStore {
        let store = CropImageViewStore(
            initialState: state,
            environment: CropImageViewStore.Environment(),
            minCropSize: CGSize(width: 80, height: 80))
        return store
    }

    /// 裁切框拖曳上下左右的任一邊角控制項，不超出原本圖片的邊界
    func test_topLeadingHandle_dragOutsideImage_clampsToImageBounds() {
        // Given
        let imageSize = CGSize(width: 300, height: 400)
        let state = CropImageViewStore.State(cropRect: CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.5))
        let store = makeStore(state: state)

        // When
        store.send(.cropHandleDragChanged(
            handle: .topLeading,
            deltaSize: CGSize(width: -999, height: -999),
            imageSize: imageSize
        ))

        // Then
        XCTAssertEqual(store.state.cropRect.origin, .zero)
    }
    
    /// 圖片放大 2 倍後，裁切框拖曳上下左右的任一邊角控制項，不超出原本圖片的邊界
    func test_afterScale_bottomTrailingHandle_dragOutsideImage_clampsToImageBounds() {
        // Given
        let imageSize = CGSize(width: 300, height: 400)
        let state = CropImageViewStore.State(cropRect: CGRect(x: 0.2, y: 0.3, width: 0.5, height: 0.5))
        let store = makeStore(state: state)
        
        // When
        store.send(.zoomScaleChanged(scale: 2))
        store.send(.cropHandleDragChanged(
            handle: .bottomTrailing,
            deltaSize: CGSize(width: 999, height: 999),
            imageSize: imageSize
        ))

        // Then
        XCTAssertEqual(store.state.cropRect.maxX, 1)
        XCTAssertEqual(store.state.cropRect.maxY, 1)
    }
    
    /// 圖片放大 2 倍與拖曳圖片，不超出原本圖片的邊界
    func test_afterScale_dragImageOutsideBounds_clampsToImageBounds() {
        // Given
        let imageSize = CGSize(width: 300, height: 400)
        let state = CropImageViewStore.State()
        let store = makeStore(state: state)
        
        // When
        store.send(.zoomScaleChanged(scale: 2))
        store.send(.imageDragChanged(
            deltaSize: CGSize(width: -999, height: -999),
            imageSize: imageSize
        ))
        store.send(.gestureRunning)

        // Then：scale 2 → extra = 0.5
        XCTAssertEqual(store.state.imageOffset, CGSize(width: -0.5, height: -0.5))
    }
}
