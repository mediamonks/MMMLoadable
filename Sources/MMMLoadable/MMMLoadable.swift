//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation

#if SWIFT_PACKAGE
@_exported import MMMLoadableObjC
#endif

extension MMMLoadableState: CustomDebugStringConvertible {
	
	public var debugDescription: String { NSStringFromMMMLoadableState(self) }
}

extension MMMPureLoadableProtocol {
    
    /// Observe changes in this loadable. Will stop listening to changes when
    /// ``MMMLoadableObserver/remove()`` is called or the observer deallocates.
    /// 
    /// - Parameter block: Get's called every time the loadable changes.
    /// - Returns: The observer, you usually want to store this outside of the scope, e.g.
    ///            in a private property so it doesn't deallocate right away.
    public func sink(_ block: @escaping (Self) -> Void) -> MMMLoadableObserver? {
        return MMMLoadableObserver(loadable: self) { loadable in
            block(loadable as! Self)
        }
    }
}
