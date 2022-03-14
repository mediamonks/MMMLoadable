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
