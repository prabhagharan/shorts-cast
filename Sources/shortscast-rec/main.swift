// Sources/shortscast-rec/main.swift
import Foundation
import ShortsCastCapture

// Fleshed out in Task 11. Stub keeps the executable target compiling.
FileHandle.standardError.write(Data("shortscast-rec \(ShortsCastCapture.version)\n".utf8))
