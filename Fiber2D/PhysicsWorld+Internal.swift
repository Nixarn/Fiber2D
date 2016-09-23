//
//  PhysicsWorld+Internal.swift
//  Fiber2D
//
//  Created by Andrey Volodin on 18.09.16.
//  Copyright © 2016 s1ddok. All rights reserved.
//

internal extension Node {
    internal func beforeSimulation(parentToWorldTransform: Matrix4x4f, nodeParentScaleX: Float, nodeParentScaleY: Float, parentRotation: Angle) {
        let scaleX = nodeParentScaleX * self.scaleX
        let scaleY = nodeParentScaleY * self.scaleY
        let rotation = parentRotation + self.rotation
        
        let nodeToWorldTransform = parentToWorldTransform * self.nodeToParentMatrix
        
        physicsBody?.beforeSimulation(parentToWorldTransform: parentToWorldTransform, nodeToWorldTransform: nodeToWorldTransform, scaleX: scaleX, scaleY: scaleY, rotation: rotation)
        
        for c in children {
            c.beforeSimulation(parentToWorldTransform: nodeToWorldTransform,
                               nodeParentScaleX: scaleX, nodeParentScaleY: scaleY,
                               parentRotation: rotation)
        }
    }
    
    internal func afterSimulation(parentToWorldTransform: Matrix4x4f, parentRotation: Angle) {
        let nodeToWorldTransform = parentToWorldTransform * self.nodeToParentMatrix
        let nodeRotation = parentRotation + self.rotation
        
        physicsBody?.afterSimulation(parentToWorldTransform: parentToWorldTransform, parentRotation: parentRotation)
        
        for c in children {
            c.afterSimulation(parentToWorldTransform: nodeToWorldTransform, parentRotation: nodeRotation)
        }
    }
}

internal func collisionBeginCallbackFunc(_ arb: UnsafeMutablePointer<cpArbiter>?, _ space: UnsafeMutablePointer<cpSpace>?, _ world: cpDataPointer?) -> cpBool {
    
    var a: UnsafeMutablePointer<cpShape>? = nil
    var b: UnsafeMutablePointer<cpShape>? = nil
    cpArbiterGetShapes(arb, &a, &b)
    
    let shapeA = Unmanaged<PhysicsShape>.fromOpaque(cpShapeGetUserData(a)).takeUnretainedValue()
    let shapeB = Unmanaged<PhysicsShape>.fromOpaque(cpShapeGetUserData(b)).takeUnretainedValue()
    
    let contactPointer = UnsafeMutablePointer<PhysicsContact>.allocate(capacity: 1)
    let contact = PhysicsContact(shapeA: shapeA, shapeB: shapeB, arb: arb)
    contactPointer.initialize(to: contact)
    cpArbiterSetUserData(arb, contactPointer)
    
    let world = Unmanaged<PhysicsWorld>.fromOpaque(world!).takeUnretainedValue()
    world.contactDelegate?.didBegin(contact: contact)
    
    return 1
}

internal func collisionPreSolveCallbackFunc(_ arb: UnsafeMutablePointer<cpArbiter>?, _ space: UnsafeMutablePointer<cpSpace>?, _ world: cpDataPointer?) -> cpBool {
    return 1
}

internal func collisionPostSolveCallbackFunc(_ arb: UnsafeMutablePointer<cpArbiter>?, _ space: UnsafeMutablePointer<cpSpace>?, _ world: cpDataPointer?) -> Void {
}

internal func collisionSeparateCallbackFunc(_ arb: UnsafeMutablePointer<cpArbiter>?, _ space: UnsafeMutablePointer<cpSpace>?, _ world: cpDataPointer?) -> Void {
    let contactPointer = cpArbiterGetUserData(arb).assumingMemoryBound(to: PhysicsContact.self)
    let contact = contactPointer.pointee
    let world = Unmanaged<PhysicsWorld>.fromOpaque(world!).takeUnretainedValue()
    world.contactDelegate?.didEnd(contact: contact)
    free(contactPointer)
}

internal extension PhysicsWorld {
    
    internal func update(dt: Time, userCall: Bool = false) {
        if !delayAddBodies.isEmpty || !delayRemoveBodies.isEmpty {
            updateBodies()
        }
        
        if !delayAddJoints.isEmpty || !delayRemoveJoints.isEmpty {
            updateJoints()
        }
        
        guard dt > FLT_EPSILON else {
            return
        }
        
        let sceneToWorldTransform = scene.nodeToParentMatrix
        scene.beforeSimulation(parentToWorldTransform: sceneToWorldTransform,
                               nodeParentScaleX: 1, nodeParentScaleY: 1,
                               parentRotation: Angle.zero)
        
        if userCall {
            cpHastySpaceStep(chipmunkSpace, cpFloat(dt))
        } else {
            updateTime += dt
            
            if fixedUpdateRate > 0 {
                let step = 1.0 / Time(fixedUpdateRate)
                let dt = step * speed
                while updateTime > step {
                    updateTime -= step
                    
                    cpHastySpaceStep(chipmunkSpace, cpFloat(dt))
                }
            } else {
                updateRateCount += 1
                if Float(updateRateCount) > updateRate {
                    let dt = updateTime * speed / Time(substeps)
                    for _ in 0..<substeps {
                        cpHastySpaceStep(chipmunkSpace, cpFloat(dt))
                        
                        for b in bodies {
                            b.update(delta: dt)
                        }
                        //bodies.forEach { $0.update(delta: dt) }
                    }
                    
                    updateRateCount = 0
                    updateTime = 0
                }
                
            }
        }
        
        // debugDraw()
        
        // Update physics position, should loop as the same sequence as node tree.
        scene.afterSimulation(parentToWorldTransform: sceneToWorldTransform, parentRotation: Angle.zero)
    }

}
