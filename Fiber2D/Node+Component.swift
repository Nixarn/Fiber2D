//
//  Node+Component.swift
//  Fiber2D
//
//  Created by Andrey Volodin on 10.09.16.
//  Copyright © 2016 s1ddok. All rights reserved.
//

// TODO:
// Add to scheduler only nodes with at least one component
public extension Node {
    /// @name component functions
    /**
     * Gets a component by its name.
     *
     * @param name A given tag of component.
     * @return The Component by tag.
     */
    public func getComponent(by tag: Int) -> Component? {
        return components.first { $0.tag == tag }
    }
    
    /**
     * Adds a component.
     *
     * @param component A given component.
     * @return True if added success.
     */
    @discardableResult
    public func add(component: Component) -> Bool {
        guard component.owner == nil else {
            fatalError("ERROR: Component already add. It can't be added to more than one owner")
        }
        
        guard getComponent(by: component.tag) == nil else {
            return false
        }
        
        if let system = director?.system(for: component) {
            system.add(component: component)
        } else {
            components.append(component)
            component.onAdd(to: self)
            
            if let c = component as? Updatable & Tagged {
                // TODO: Insert with priority in mind
                updatableComponents.append(c)
                
                // If it is first component
                if updatableComponents.count == 1 {
                    if let scheduler = self.scheduler {
                        scheduler.schedule(updatable: self)
                    } else {
                        queuedActions.append {
                            self.scheduler!.schedule(updatable: self)
                        }
                    }
                }
            }
            
            if let c = component as? FixedUpdatable & Tagged {
                // TODO: Insert with priority in mind
                fixedUpdatableComponentns.append(c)
                
                // If it is first component
                if fixedUpdatableComponentns.count == 1 {
                    if let scheduler = self.scheduler {
                        scheduler.schedule(updatable: self)
                    } else {
                        queuedActions.append {
                            self.scheduler!.schedule(updatable: self)
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    /**
     * Removes all components with tag.
     *
     * @param name A given tag of components.
     * @return True if removed success.
     */
    @discardableResult
    public func removeComponent(by tag: Int) -> Bool {
        let oldCount = components.count
        components = components.filter {
            if $0.tag == tag {
                $0.onRemove()
            
                // FIXME: This will not work if component will be removed when node doesn't have any scheduler
                // And we also cant remove it from queuedActions since blocks are incomparable
                // Need to find more clever solution
                if $0 is Updatable {
                    self.updatableComponents = self.updatableComponents.filter {
                        return $0.tag != tag
                    }
                    
                    if self.updatableComponents.isEmpty {
                        self.scheduler?.unschedule(updatable: self)
                    }
                }
                
                if $0 is FixedUpdatable {
                    self.fixedUpdatableComponentns = self.fixedUpdatableComponentns.filter {
                        return $0.tag != tag
                    }
                    
                    if self.fixedUpdatableComponentns.isEmpty {
                        self.scheduler?.unschedule(fixedUpdatable: self)
                    }
                }
                return false
            }
            return true
        }
        return oldCount < components.count
    }
    
    /**
     * Removes a component by its pointer.
     *
     * @param component A given component.
     * @return True if removed success.
     */
    @discardableResult
    public func remove(component: Component) -> Bool {
        return removeComponent(by: component.tag)
    }
    
    /**
     * Removes all components
     */
    public func removeAllComponents() {
        components.forEach {
            $0.onRemove()
        }
        components = []
        updatableComponents = []
        fixedUpdatableComponentns = []
        
        let scheduler = self.scheduler
        scheduler?.unschedule(updatable: self)
        scheduler?.unschedule(fixedUpdatable: self)
    }    
}

extension Node: Updatable, FixedUpdatable {
    
    public final func update(delta: Time) {
        updatableComponents.forEach { $0.update(delta: delta) }
    }
    
    public final func fixedUpdate(delta: Time) {
        fixedUpdatableComponentns.forEach { $0.fixedUpdate(delta: delta) }
    }
}
