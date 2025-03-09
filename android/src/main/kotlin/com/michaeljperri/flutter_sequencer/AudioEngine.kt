package com.michaeljperri.flutter_sequencer

/**
 * Manages the native audio engine for the sequencer.
 * This class follows the singleton pattern to ensure only one instance
 * of the native audio engine exists.
 */
class AudioEngine private constructor() {
    companion object {
        @Volatile
        private var instance: AudioEngine? = null

        fun getInstance(): AudioEngine =
            instance ?: synchronized(this) {
                instance ?: AudioEngine().also { instance = it }
            }
    }

    external fun play()
    external fun pause()
    external fun isPlaying(): Boolean

    init {
        System.loadLibrary("flutter_sequencer")
    }
} 