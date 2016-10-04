//
//  TypeContainer.swift
//  Fiber2D
//
//  Created by Andrey Volodin on 04.10.16.
//  Copyright © 2016 s1ddok. All rights reserved.
//

internal class TypeContainer: Hashable {
    internal init<ImplObj>(_ implType: ImplObj.Type)  {
        self.type = implType
        self.address = String(describing: Unmanaged.passUnretained(self).toOpaque())
    }
    
    internal let type: Any
    internal var hashValue: Int { return uniqueKey.hashValue }
    internal var uniqueKey: String { return String(describing: type) + address }
    
    private var address: String!
}

internal func == (lhs: TypeContainer, rhs: TypeContainer) -> Bool {
    return lhs.uniqueKey == rhs.uniqueKey
}
