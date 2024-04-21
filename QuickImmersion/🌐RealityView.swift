import SwiftUI
import RealityKit
import ARKit


var lastGesture = 0;
var currentGesture = 0;

struct 🌐RealityView: View {
    @StateObject var model: 🥽AppModel = .init()
    
    // Heads
    @State var sceneContent: Entity?
    @State var heads: [Entity] = []
    @State var contentHolder: (any RealityViewContentProtocol)?
    
    // Exit
    @Environment(\.dismissImmersiveSpace)
    private var dismissImmersiveSpace
    @State var exitTriggered = false
    
    // Enabled start button on the menu
    @Binding var isEnabled:Bool
    @Binding var buttonText:String

    // All blocks array
    @State var currentBlock: Entity?
    @State var blocks: [Entity] = []
    var size:Float = 0.1
    // in unix time, to limit the rate of block placement
    @State var lastBlockTime: Int64 = 0
    var blockInterval:Int64 = 1000 // ms
    
    
    var body: some View {
        RealityView { content in
            content.add(self.model.rootEntity)
            self.model.setUpChildEntities()
            contentHolder = content;
            
            // Load in head model
            if let head = try? await Entity(named: "andyhead3d2") {
                head.setPosition(SIMD3(x:0, y:2.5, z:-1), relativeTo: nil)
//                head.components.set(🧑HeadTrackingComponent()) // This makes it track you
                
                self.model.rootEntity.addChild(head)
                content.add(head)
                sceneContent = head
            }
            
        } update: { (content) in
            // call a function in AppModel that recognizes custom hand gestures
            let customGestures = self.model.detectCustomTaps()
            // Assign current gesture if its not nil
            if (customGestures != nil){
                currentGesture = customGestures!
            }
            
            
            if (currentBlock != nil){
                currentBlock?.setPosition(SIMD3(x:0, y:0, z:-size*2ˆ), relativeTo: self.model.getJoint("rightMiddleTip"))
            }
            
            
            
            if (customGestures == 1){
                DispatchQueue.main.async {exitTriggered = true }
                print("exit triggered")
                print(exitTriggered)
            } 
        }
        .background {
            🛠️MenuTop()
                .environmentObject(self.model)
        }
        .task { self.model.run() }
        .task { self.model.observeAuthorizationStatus() }
        .task(id: exitTriggered){
            print("exitTriggered updated to ", exitTriggered)
            if (exitTriggered){
                await dismissImmersiveSpace()
//                self.model.$isEnabled = true
                isEnabled = true
                buttonText = "Start"
            }
        }
        .task(id:currentGesture){
            print("currentGesture updated to ", currentGesture)
            if currentGesture == 2 { // Right middle touch, show block placement but don't place it yet.
                let rightIndex = self.model.getJoint("rightMiddleTip")
                var rightIndexPos = rightIndex.position
                
                if currentBlock == nil{ // If no block is floating, make one
                    var shouldPlaceBlock = true
                    
                    // Check that last block was placed more than blockInterval ago
                    let currentTime = Date().toMilliseconds()
                    if (currentTime - lastBlockTime < blockInterval){
                        shouldPlaceBlock = false
                    }
                    // Check that we aren't intersecting another block first
                    print("Block intersect check, there are\(blocks.count) blocks")
                    blocks.forEach { block in
                        print(distance(block.position, rightIndexPos))
                        if (distance(block.position, rightIndexPos) < size){
                            shouldPlaceBlock = false
                        }
                    }
                    if (shouldPlaceBlock){
                        print("placeing plblock")
                        lastBlockTime = currentTime
                        rightIndexPos.y -= size
    //                     addBlock(pos: rightIndexPos)
                        currentBlock = makeBlock(parentEntity: rightIndex)
                    }
                } else{ // update current block location
//                    currentBlock!.setPosition(SIMD3(x:0, y:-0.2, z:0), relativeTo: rightIndex)
                    print("setting position")
                }
            }
             else if (lastGesture == 2 && currentGesture != 2 && currentBlock != nil){ // Right middle release, place block
                 print("Right middle release")
                 _ = placeBlock(cube: currentBlock!)
                 currentBlock = nil
             }
            else if (currentGesture == 4){ // delete all cubes
                blocks.forEach { block in
                    contentHolder?.remove(block)
                }
                blocks = []
            }
            lastGesture = currentGesture
        }
        .upperLimbVisibility(.hidden)
        .gesture(SpatialTapGesture().targetedToAnyEntity().onEnded { value in
            let location3D = value.convert(value.location3D, from: .global, to: .scene)
            let nowhead = addFace(pos:location3D)
            heads.append(nowhead)
            print("Tap gestures")
        })    
    }

    func makeBlock(parentEntity: Entity) -> Entity{
        let cube = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0), materials: [SimpleMaterial(color: .cyan,
                                                                                                           roughness:0.8,
                                                                                                           isMetallic: false)])
        // blocks.append(cube)
//        parentEntity.addChild(cube)
        cube.setPosition(SIMD3(x:0, y:-size, z:0), relativeTo: parentEntity)
        contentHolder?.add(cube)
        return cube
    }

    func placeBlock(cube: Entity) -> Entity{
//        cube.removeFromParent()
        cube.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: size))]))
        cube.components.set(PhysicsBodyComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: size))],
                                                mass: 1.0,
                                                material: PhysicsMaterialResource.generate(friction: 1.0, restitution: 0.0),
                                                mode: .dynamic))
        blocks.append(cube)
        return cube
    }

     func addBlock(pos: SIMD3<Float>){
         // let size:Float = 0.1
         let cube = ModelEntity(mesh: .generateBox(size: size, cornerRadius: 0), materials: [SimpleMaterial(color: .cyan, 
                                                                                                            roughness:0.8,
                                                                                                            isMetallic: false)])
         cube.setPosition(pos, relativeTo: nil)
         cube.components.set(CollisionComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: size))]))
         cube.components.set(PhysicsBodyComponent(shapes: [ShapeResource.generateBox(size: SIMD3(repeating: size))],
                                                 mass: 1.0,
                                                 material: PhysicsMaterialResource.generate(friction: 1.0, restitution: 0.0),
                                                 mode: .dynamic))
         blocks.append(cube)
         contentHolder?.add(cube)
     }
    
    
    // Adds a copy of the author's head model at the given position
    func addFace(pos: SIMD3<Float>) -> Entity{
        let headclone = (sceneContent?.clone(recursive: true))!
        headclone.setPosition(pos, relativeTo: nil)
//        let modelEntity: ModelEntity? = headclone as? ModelEntity ?? findModelEntity(in: headclone)
        
        // Assuming `modelEntity` is your ModelEntity instance
        if let modelEntity = findModelEntity(in: headclone) {
            print("found modelEntity")
            
            modelEntity.components[CollisionComponent.self] = CollisionComponent(
                shapes: [ShapeResource.generateConvex(from: modelEntity.model!.mesh)] // Adjust the size to match your entity's size
            )
            
            let material = PhysicsMaterialResource.generate(friction: 0.8, restitution: 0)
            // Add a PhysicsBodyComponent to make it participate in physics simulation
            modelEntity.components.set(PhysicsBodyComponent(
                shapes: modelEntity.collision!.shapes,
                mass: 1.0,
                material: material,
                mode: .dynamic
            ))
        }
        contentHolder?.add(headclone)
        return headclone
    }
}


// Helper function to recursively search for a ModelEntity within an entity
func findModelEntity(in entity: Entity) -> ModelEntity? {
    if let modelEntity = entity as? ModelEntity {
        return modelEntity
    } else {
        for child in entity.children {
            if let found = findModelEntity(in: child) {
                return found
            }
        }
    }
    return nil
}


extension Date {
    func toMilliseconds() -> Int64 {
        Int64(self.timeIntervalSince1970 * 1000)
    }

    init(milliseconds:Int) {
        self = Date().advanced(by: TimeInterval(integerLiteral: Int64(milliseconds / 1000)))
    }
}
