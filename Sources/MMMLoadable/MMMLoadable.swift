//
// MMMLoadable. Part of MMMTemple.
// Copyright (C) 2016-2020 MediaMonks. All rights reserved.
//

import Foundation
import MMMCommonCore

#if SWIFT_PACKAGE
@_exported import MMMLoadableObjC
#endif

extension MMMLoadableState: CustomStringConvertible {
	public var description: String { NSStringFromMMMLoadableState(self) }
}

extension MMMPureLoadableProtocol {
    
    /// Observe changes in this loadable. Will stop listening to changes when
    /// ``MMMLoadableObserver/remove()`` is called or the observer deallocates.
    /// 
    /// - Parameter block: Get's called every time the loadable changes.
    /// - Returns: The observer, you usually want to store this outside of the scope, e.g.
    ///            in a private property so it doesn't deallocate right away.
    public func sink(_ block: @escaping (Self) -> Void) -> MMMLoadableObserver? {
        return MMMLoadableObserver(loadable: self) { [weak self] _ in
            guard let self = self else {
                assertionFailure("\(MMMTypeName(Self.self)) was lost inside the observer callback?")
                return
            }
            block(self)
        }
    }
}
