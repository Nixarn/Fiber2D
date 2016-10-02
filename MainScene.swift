//
//  MainScene.swift
//
//  Created by Andrey Volodin on 06.07.16.
//  Copyright © 2016. All rights reserved.
//

import SwiftMath

class MainScene: Scene {
    
    var colorNode: ColorNode!
    var sprite: Sprite!
    
    var physicsSquares = [ColorNode]()
    
    let ground = ColorNode()
    
    var physicsSystem: PhysicsSystem!
    
    var staticBody: ColorNode!
    
    override init() {
        super.init()
        
        let world = PhysicsWorld(rootNode: self)
        physicsSystem = PhysicsSystem(world: world)
    
        world.contactDelegate = self
        
        sprite = Sprite(imageNamed: "image.jpeg")
        sprite.scale = 6.0
        sprite.position = p2d(0.5, 0.5)
        sprite.positionType = .normalized
        let action = ActionSkewTo(skewX: 15°, skewY: 45°).continously(duration: 15.0)
        sprite.run(action: action)
        add(child: sprite)
        
        colorNode = ColorNode()
        colorNode.contentSize = Size(width: 64.0, height: 64.0)
        colorNode.position = p2d(0.5, 0.5)
        colorNode.positionType = .normalized
        var startPosition = p2d(0.1, 0.0)
        var colorNodes = [ColorNode]()
        for _ in 0..<13 {
            let colorNode = ColorNode()
            colorNode.contentSize = Size(width: 56.0, height: 56.0)
            colorNode.anchorPoint = p2d(0.5, 0.5)
            startPosition = startPosition + p2d(0.0, 0.1)
            colorNode.position = startPosition
            colorNode.positionType = .normalized
            colorNodes.append(colorNode)
            self.add(child: colorNode)
        }
        
        let rotate = ActionRotateTo(angle: 45°).continously(duration: 2.0)
        let skew   = ActionSkewTo(skewX: 30°, skewY: 30°).continously(duration: 1.0)
        let rotate2 = ActionRotateTo(angle: 0°).continously(duration: 2.0)
        let skew2   = ActionSkewTo(skewX: 15°, skewY: 10°).instantly
        
        let rotateBy = ActionRotateBy(angle: 15°).continously(duration: 1.0)
        
        let rotate3 = ActionRotateBy(angle: 90°)
        let move = ActionMoveBy(vec2(0.1, 0))
        let rotateAndMove = rotate3.and(move).continously(duration: 2.0)
        
        colorNodes[0].run(action: rotate)
        colorNodes[1].run(action: rotate.then(skew))
        colorNodes[2].run(action: rotate.then(skew).speed(0.50))
        colorNodes[3].run(action: rotate.then(skew).speed(0.50).ease(EaseSine.in))
        colorNodes[4].run(action: rotate.then(skew2).then(rotate2))
        colorNodes[5].run(action: rotate.and(skew))
        colorNodes[6].run(action: rotate.then(skew.and(rotate2)))
        colorNodes[7].run(action: rotateBy.repeatForever)
        //colorNodes[8].run(action: rotateBy.repeat(times: 6)
        //    .then(ActionCallBlock { print(colorNodes[8].position) }.instantly.repeat(times: 7)))
        colorNodes[8].run(action: rotateAndMove.then(ActionCallBlock { print(colorNodes[8].position) }.instantly))
        colorNodes[8].run(action: ActionMoveBy(vec2(0.0, -0.1)).continously(duration: 1.0))
        self.userInteractionEnabled = true
        print(Date())
        let _ = scheduleBlock({ (t:Timer) in
            print(Date())
            print(colorNodes[8].rotation)
            }, delay: 10.0)
        
        let mask: UInt32 = 1
        
        staticBody = ColorNode()
        staticBody.position = p2d(256.0, 128.0)
        staticBody.contentSize = Size(98.0, 98.0)
        
        let material = PhysicsMaterial.default
        let physicsCircle = PhysicsBody.circle(radius: 49.0, material: material)
        physicsCircle.collisionBitmask = mask
        physicsCircle.isDynamic = false
        staticBody.add(component: physicsCircle)
        add(child: staticBody)
        
        for j in 0..<10 {
            let physicsSquare = ColorNode()
            physicsSquares.append(physicsSquare)
            physicsSquare.contentSize = Size(24.0, 24.0)
            let physicsBody = PhysicsBody.box(size: vec2(24.0, 24.0), material: material)
            physicsBody.isDynamic = true
            physicsSquare.add(component: physicsBody)
            physicsSquare.position = p2d(64.0 * Float(j), 256.0)
            
            if j % 2 == 0 {
                physicsSquare.add(component: UpdateComponent())
            } else {
                physicsSquare.add(component: FixedUpdateComponent())
            }
            
            add(child: physicsSquare)
        }
        
        
        ground.contentSize = Size(1.0, 0.1)
        ground.contentSizeType = SizeType.normalized
        
        add(child: ground)
        
        let boxBody = PhysicsBody.box(size: ground.contentSizeInPoints, material: material)
        boxBody.isDynamic = false
        ground.add(component: boxBody)
    }
    
    override func onEnter() {
        director!.register(system: physicsSystem)
        
        super.onEnter()
        
        let rt = RenderTexture(width: 64, height: 64)
        let _ = rt.begin()
        colorNode.visit()
        rt.end()
        
        //colorNode.runAction(repeatForever!)
        add(child: colorNode)
        rt.sprite.positionType = PositionType.normalized
        rt.sprite.position = p2d(0.5, 0.5)
        rt.sprite.opacity = 0.5
        add(child: rt.sprite)
        
        print(sprite.active)
    }
    
    override func mouseDown(_ theEvent: NSEvent, button: MouseButton) {
        //colorNode.positionInPoints = theEvent.location(in: self)
        //print(theEvent.location(in: self))
        
        for j in 0..<physicsSquares.count {
            //print(physicsSquares[j].physicsBody!.mass)
            //physicsSquares[j].physicsBody?.apply(force: vec2(0.0, Float(j) * 25.0))
            //physicsSquares[j].physicsBody!.isDynamic = !physicsSquares[j].physicsBody!.isDynamic
        }
        
        let physicsCircle = Sprite(imageNamed: "circle.png")
        let physicsBody = PhysicsBody.circle(radius: 6.0)
        physicsBody.isDynamic = true
        physicsBody.isGravityEnabled = true
        physicsCircle.position = theEvent.location(in: self)
        
        add(child: physicsCircle)
        physicsCircle.add(component: physicsBody)
        
        if button == .right {
            if staticBody.parent == nil {
                self.add(child: staticBody)
            } else {
                staticBody.removeFromParent()
            }
        }
    }
    
    override func scrollWheel(_ theEvent: NSEvent) {
        print("scroll")
    }
    
    override func mouseDragged(_ theEvent: NSEvent, button: MouseButton) {
        print("drag")
    }
    
    /*override func update(delta: Time) {
        colorNode.rotation += 1°
    }*/
}

extension Scene: PhysicsContactDelegate {
    public func didEnd(contact: PhysicsContact) {
        print("did end")
        
    }
    
    public func didBegin(contact: PhysicsContact) {
        print("did begin")
    }
}
