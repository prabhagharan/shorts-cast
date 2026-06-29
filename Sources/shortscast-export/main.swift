import Foundation
import ShortsCastRender

// Fleshed out in Task 9. Stub keeps the executable target compiling.
FileHandle.standardError.write(Data("shortscast-export \(ShortsCastRender.version)\n".utf8))
