// Sources/ShortsCastEditor/PlaybackClock.swift
import Foundation

/// Pure playback timing: maps wall-clock elapsed time to a preview time so playback
/// runs at real speed regardless of how long each frame takes to render. Slow renders
/// skip frames instead of playing in slow motion.
public enum PlaybackClock {
    public static func tick(startWall: Double, startTime: Double,
                            nowWall: Double, duration: Double) -> (time: Double, playing: Bool) {
        let t = startTime + (nowWall - startWall)
        if t >= duration { return (duration, false) }
        return (t, true)
    }
}
