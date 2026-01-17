//
//  ElectronCrawlerFrameTests.swift
//  PortalTests
//
//  Created by Claude Code on 2026/01/18.
//

import Testing
@testable import Portal

struct ElectronCrawlerFrameTests {
    @Test
    func testFramesOverlapSignificantlyWhenSimilarAndOverlapping() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 10, y: 10, width: 100, height: 100)
        #expect(ElectronCrawler.framesOverlapSignificantly(a, b))
    }

    @Test
    func testFramesOverlapSignificantlyIgnoresDifferentSizes() {
        let large = CGRect(x: 0, y: 0, width: 100, height: 100)
        let small = CGRect(x: 0, y: 0, width: 30, height: 30)
        #expect(!ElectronCrawler.framesOverlapSignificantly(large, small))
    }

    @Test
    func testFramesOverlapSignificantlyRequiresOverlapRatio() {
        let a = CGRect(x: 0, y: 0, width: 100, height: 100)
        let b = CGRect(x: 70, y: 0, width: 100, height: 100)
        #expect(!ElectronCrawler.framesOverlapSignificantly(a, b))
    }

    @Test
    func testEstimatedFallbackFrameUsesParentSizeAndIndex() {
        let parent = CGRect(x: 0, y: 0, width: 100, height: 100)
        let estimated = ElectronCrawler.estimatedFallbackFrame(parentFrame: parent, childIndex: 1)
        #expect(estimated.width == 30)
        #expect(estimated.height == 30)
        #expect(estimated.minX == 18)
        #expect(estimated.minY == 0)
    }

    @Test
    func testResolveFramePrefersAXFrame() {
        let axFrame = CGRect(x: 5, y: 6, width: 7, height: 8)
        let result = ElectronCrawler.resolveFrame(
            axFrame: axFrame,
            position: CGPoint(x: 1, y: 2),
            size: CGSize(width: 3, height: 4)
        )
        #expect(result.0 == axFrame)
        #expect(result.1 == .axFrame)
    }

    @Test
    func testResolveFrameFallsBackToPositionSize() {
        let result = ElectronCrawler.resolveFrame(
            axFrame: nil,
            position: CGPoint(x: 1, y: 2),
            size: CGSize(width: 3, height: 4)
        )
        #expect(result.0 == CGRect(x: 1, y: 2, width: 3, height: 4))
        #expect(result.1 == .positionSize)
    }

    @Test
    func testResolveFrameReturnsNoneWhenIncomplete() {
        let result = ElectronCrawler.resolveFrame(
            axFrame: nil,
            position: nil,
            size: CGSize(width: 3, height: 4)
        )
        #expect(result.0 == nil)
        #expect(result.1 == .none)
    }
}
