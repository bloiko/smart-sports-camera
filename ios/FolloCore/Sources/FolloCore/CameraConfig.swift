import Foundation

/// CAM of src/live_sim.py. Keep the two in sync.
public struct CameraConfig {
    public var outW = 1920.0, outH = 1080.0
    public var spreadK = 1.4, focusPx = 300.0
    public var minCropW = [800.0, 1700.0], maxCropW = [1600.0, 2800.0]
    public var ballWeight = 0.7, ballHoldS = 0.6, ballFadeS = 1.0, znAvgS = 1.0, giKeep = 0.25, smoothS = 0.8, maxSpeed = 900.0, catchK = 2.5, margin = 0.08
    public var goalZone = [0.08, 0.16], goalAttackN = 5.0, goalBoxK = 0.1, goalUnc = 80.0, goalMinDataS = 30.0, goalEveryS = 10.0
    public var anticipateS = 2.0, lostZoom = 1.35, confirmS = 0.6, confirmPx = 200.0
    public var mirror = true, goalHoldS = 2.0, borderShiftMax = 150
    public var playerEvery = 4
    public var goalsPrior: [Pt]? = nil        // pitch memory: goals of an earlier match on this pitch
    public init() {}
}
