import Darwin

// Bistatic two-source model in a vertical plane. Assumes a centered microphone,
// speakers at (+/- span/2, 0), and both echoes coming from the same point.
// This is a testable geometry hypothesis, not a measured Mac hardware layout.
public struct PlanePosition {
    public let x: Double
    public let height: Double
    public static func solve(left:Double,right:Double,span:Double) -> PlanePosition? {
        guard left.isFinite,right.isFinite,span.isFinite,left>0,right>0,span>=10 else { return nil }
        let half=span/2, l=2*left+half, r=2*right+half
        let radius=(l*l+r*r-2*half*half)/(2*(l+r))
        let x=(l*l-2*l*radius-half*half)/(2*half)
        let heightSquared=radius*radius-x*x
        guard heightSquared>0,abs(x)<=40,heightSquared<=3600 else { return nil }
        return PlanePosition(x:x,height:sqrt(heightSquared))
    }
}
