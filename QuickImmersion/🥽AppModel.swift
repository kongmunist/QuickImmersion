import SwiftUI
import RealityKit
import ARKit

@MainActor
class 🥽AppModel: ObservableObject {
    @Published private(set) var authorizationStatus: ARKitSession.AuthorizationStatus?
    @Published var presentPanel: 🛠️Panel? = nil
    @Published var selectedLeft: Bool = false
    @Published var selectedRight: Bool = false
    
    // Public var that maintains each hand's last handAnchor + joints
    @Published var latestHandTracking: HandsUpdates = .init(left: nil, right: nil)
    struct HandsUpdates {
        var left: HandAnchor?
        var right: HandAnchor?
    }
    
    var session = ARKitSession()
    private let handTracking = HandTrackingProvider()
//    let planeData = PlaneDetectionProvider(alignments: [.horizontal, .vertical])
    let sceneReconstruction = SceneReconstructionProvider()

    
    let rootEntity = Entity()
    
    // Take only 3 joints per finger + wrist (except thumb has two)
        // Labeled in blue
    let majorHandJoints: [HandSkeleton.JointName] = [
        .thumbIntermediateBase, .thumbTip,
        .indexFingerIntermediateBase, .indexFingerKnuckle, .indexFingerTip,
        .middleFingerIntermediateBase, .middleFingerKnuckle, .middleFingerTip,
        .ringFingerIntermediateBase, .ringFingerKnuckle, .ringFingerTip,
        .littleFingerIntermediateBase, .littleFingerKnuckle, .littleFingerTip,
        .wrist
    ]
    
    // Labeled in green
    let minorHandJoints: [HandSkeleton.JointName] = [
        .thumbKnuckle, .thumbIntermediateTip,
        .indexFingerMetacarpal, .indexFingerIntermediateTip,
        .middleFingerMetacarpal, .middleFingerIntermediateTip,
        .ringFingerMetacarpal, .ringFingerIntermediateTip,
        .littleFingerMetacarpal, .littleFingerIntermediateTip,
        .forearmArm, .forearmWrist
    ]

    // only one duplicate, the thumbIntermediateBase 
    
    let majorBalls: [Entity] = 🧩Entity.majorBalls(numBalls: 30);
    let minorBalls: [Entity] = 🧩Entity.minorBalls(numBalls: 24);

    
    func setUpChildEntities() {
        self.majorBalls.forEach { self.rootEntity.addChild($0) }
        self.minorBalls.forEach { self.rootEntity.addChild($0) }
    }
    
    // Check that we have ARKit authorization for hand and head tracking
    func observeAuthorizationStatus() {
        Task {
            self.authorizationStatus = await self.session.queryAuthorization(for: [.handTracking])[.handTracking]
            
            for await update in self.session.events {
                if case .authorizationChanged(let type, let status) = update {
                    if type == .handTracking { self.authorizationStatus = status }
                } else {
                    print("Another session event \(update).")
                }
            }
        }
    }
    
    
    private var meshEntities = [UUID: ModelEntity]()
    
    func run() {
        Task { @MainActor in
            do {
                try await self.session.run([self.handTracking])
                await self.processHandUpdates()
            } catch {
                print(error)
            }
        }
        Task {
            try await session.run([self.sceneReconstruction])
            
            for await update in self.sceneReconstruction.anchorUpdates {
                let meshAnchor = update.anchor
                guard let shape = try? await ShapeResource.generateStaticMesh(from: meshAnchor) else { continue }
                
                switch update.event {
                case .added:
                    let entity = ModelEntity()
                    entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
                    entity.collision = CollisionComponent(shapes: [shape], isStatic: true)
                    entity.components.set(InputTargetComponent())
                    
                    entity.physicsBody = PhysicsBodyComponent(mode: .static)
                    
                    meshEntities[meshAnchor.id] = entity
                    rootEntity.addChild(entity)
                case .updated:
                    print("updated, but we are ignoring it")
                    
//                    guard let entity = meshEntities[meshAnchor.id] else { continue }
//                    entity.transform = Transform(matrix: meshAnchor.originFromAnchorTransform)
//                    entity.collision?.shapes = [shape]
                case .removed:
                    meshEntities[meshAnchor.id]?.removeFromParent()
                    meshEntities.removeValue(forKey: meshAnchor.id)
                }
                
            }
        }
    }
    
    // Add function that detects custom tap gestures
    func detectCustomTaps() -> Int?{
        // Make sure both hands are tracked rn
        guard let leftHandAnchor = latestHandTracking.left,
              let rightHandAnchor = latestHandTracking.right,
              leftHandAnchor.isTracked, rightHandAnchor.isTracked else {
            return nil
        }
        
        // Detect our exit gesture
        makeAllJointsInvisible()
        let pointerDist = jointDist("leftWrist", "rightIndexTip")
        let middleDist = jointDist("leftWrist", "rightMiddleTip")
        if (pointerDist < 0.05) && (middleDist < 0.05) {
            return 1
        } else if (pointerDist < 0.2) && (middleDist < 0.2) {
            makeJointVisible("leftWrist")
            makeJointVisible("rightIndexTip")
            makeJointVisible("rightMiddleTip")
        }
        
        // Detect our placement gesture, right thumb + middle finger touching
        // thumbmiddleDist = jointDist("rightThumbTip", "rightMiddleTip")
        if (touching("rightThumbTip", "rightMiddleTip")) {
            // makeJointColored("rightThumbTip", color: .green)
            // makeJointColored("rightMiddleTip", color: .green)
            makeJointVisible("rightThumbTip")
            makeJointVisible("rightMiddleTip")
            return 2
        } else if (touching("leftThumbTip", "leftMiddleTip")) {
            // makeJointColored("leftThumbTip", color: .green)
            // makeJointColored("leftMiddleTip", color: .green)
            makeJointVisible("leftThumbTip")
            makeJointVisible("leftMiddleTip")
            return 3
        }

        // If all fingertips are touching, return 4
        if (touching("leftThumbTip", "rightThumbTip") && 
            touching("leftIndexTip", "rightIndexTip") && 
            touching("leftMiddleTip", "rightMiddleTip") && 
            touching("leftRingTip", "rightRingTip") && 
            touching("leftPinkyTip", "rightPinkyTip")) {
            return 4
        }

        
        
        return 0
    }
    
    public var leftPosition: SIMD3<Float> {
        self.majorBalls[5].position
    }
    
    public var rightPosition: SIMD3<Float> {
        self.majorBalls[21].position
    }
    



    // Variables that determine "close" and "touching" for joints
    var closeToThresh: Float = 0.05;
    var touchingThresh: Float = 0.015;
    
    let rightHandOffset = 15;
    var jointMapping: [String: Int] = [:]
    init() {
        jointMapping = [
            "leftThumbBase": 0, "leftThumbTip": 1,
            "leftIndexBase": 2, "leftIndexKnuckle": 3, "leftIndexTip": 4,
            "leftMiddleBase": 5, "leftMiddleKnuckle": 6, "leftMiddleTip": 7,
            "leftRingBase": 8, "leftRingKnuckle": 9, "leftRingTip": 10,
            "leftPinkyBase": 11, "leftPinkyKnuckle": 12, "leftPinkyTip": 13,
            "leftWrist": 14,
            "rightThumbBase": rightHandOffset + 0, "rightThumbTip": rightHandOffset + 1,
            "rightIndexBase": rightHandOffset + 2, "rightIndexKnuckle": rightHandOffset + 3, "rightIndexTip": rightHandOffset + 4,
            "rightMiddleBase": rightHandOffset + 5, "rightMiddleKnuckle": rightHandOffset + 6, "rightMiddleTip": rightHandOffset + 7,
            "rightRingBase": rightHandOffset + 8, "rightRingKnuckle": rightHandOffset + 9, "rightRingTip": rightHandOffset + 10,
            "rightPinkyBase": rightHandOffset + 11, "rightPinkyKnuckle": rightHandOffset + 12, "rightPinkyTip": rightHandOffset + 13,
            "rightWrist": rightHandOffset + 14
        ]
    }
}



// We're gonna write the natural language hand query type stuff here. Optional threshold param
extension 🥽AppModel {
        

    func getJoint(_ jointname: String) -> Entity {
        return self.majorBalls[jointMapping[jointname]!]
    }
    
    func positionOfJoint(_ jointName: String) -> simd_float3? {
        // return self.majorBalls[jointMapping[jointName]!].position
        // if jointName starts with _, it's on right so add len majorballs/2
//        var rightAdd = jointName.starts(with: "_") ? majorBalls.count / 2 : 0
        return self.majorBalls[jointMapping[jointName]!].position
    }

    func jointDist(_ joint1: String, _ joint2: String) -> Float {
        let pos1 = self.positionOfJoint(joint1)!
        let pos2 = self.positionOfJoint(joint2)!
        return distance(pos1, pos2)
    }

    func closeTo(_ joint1: String, _ joint2: String, thresh: Float = -1) -> Bool {
        let thresh = thresh < 0 ? closeToThresh : thresh
        return jointDist(joint1, joint2) < thresh
    }

    func closeTo(_ joints: [String], thresh: Float = -1) -> Bool {
        let positions = joints.compactMap { positionOfJoint($0) }
        let dists = zip(positions, positions[1...]).map { distance($0, $1) }
        return dists.allSatisfy { $0 < thresh }
    }

    func touching(_ joint1: String, _ joint2: String, thresh: Float = -1) -> Bool {
        let thresh = thresh < 0 ? touchingThresh : thresh
        return jointDist(joint1, joint2) < thresh
    }

    func touching(_ joints: [String], thresh: Float = -1) -> Bool { // Not proper, but works kinda
        let thresh = thresh < 0 ? touchingThresh : thresh
        let positions = joints.compactMap { positionOfJoint($0) }
         let dists = zip(positions, positions[1...]).map { distance($0, $1) }
        return dists.reduce(0, +) / Float(dists.count) < thresh
    }

    func makeAllJointsInvisible() {
        for ball in self.majorBalls {
            ball.components.set(OpacityComponent(opacity:0))
        }
        for ball in self.minorBalls {
            ball.components.set(OpacityComponent(opacity:0))
        }
    }

    func makeJointVisible(_ jointName: String) {
        self.majorBalls[jointMapping[jointName]!].components.set(OpacityComponent(opacity:1))
        
    }


    // func makeJointColored(_ jointName: String, color: UIColor) { // Doesn't work
    //     let yes = self.majorBalls[jointMapping[jointName]!].children[0] as! ModelEntity;
    //     yes.model?.materials = [SimpleMaterial(color: color, isMetallic: false)]
    // }
    

    
}

private extension 🥽AppModel {
    private func processHandUpdates() async {
        for await update in self.handTracking.anchorUpdates {
            let handAnchor = update.anchor
            guard handAnchor.isTracked else { continue }
            
            // Update published hand pose
            if handAnchor.chirality == .left {
                latestHandTracking.left = handAnchor
            } else if handAnchor.chirality == .right { // Update right hand info.
                latestHandTracking.right = handAnchor
            }

            // Update ball positions for each joint. If it's the left hand, start at 0, if it's the right hand, start at 16.
            var start = handAnchor.chirality == .left ? 0 : majorHandJoints.count
            for i in 0..<(majorHandJoints.count) {
                let pos = handAnchor.handSkeleton?.joint(majorHandJoints[i])
                let worldPos = handAnchor.originFromAnchorTransform * pos!.anchorFromJointTransform
                self.majorBalls[i + start].setTransformMatrix(worldPos, relativeTo:nil)
            }
            // Minor joints now
            start = handAnchor.chirality == .left ? 0 : minorHandJoints.count
            for i in 0..<(minorHandJoints.count) {
                let pos = handAnchor.handSkeleton?.joint(minorHandJoints[i])
                let worldPos = handAnchor.originFromAnchorTransform * pos!.anchorFromJointTransform
                self.minorBalls[i + start].setTransformMatrix(worldPos, relativeTo:nil)
            }
        }
    }
}

