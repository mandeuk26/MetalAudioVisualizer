//
//  BeatDetection.swift
//  AudioVisualizer
//
//  Created by USER on 2023/03/10.
//  Copyright © 2023 alex. All rights reserved.
//

import Foundation
import Combine

class BeatDetection {
    var onBeatSubject = PassthroughSubject<Void, Never>()
    var bufferSize = 1024
    var samplingRate = 44100

    var limitBeats = false
    var limitAmount = 0
    var changeThreshold: Float = 0.1

    var bands = 12
    var maximumLag = 100
    var smoothDecay: Float = 0.997

    var framesSinceBeat = 0
    var framePeriod: Float

    var ringBufferSize = 120
    var currentRingBufferPosition = 0

    var previousSpectrum: [Float]

    var averagesPerBand: [Float]
    var onsets: [Float]
    var notations: [Float]

    var audioData: AudioData?

    var getBandWidth: Float {
        return Float(samplingRate) / Float(bufferSize)
    }

    init() {
        onsets = Array(repeating: 0, count: ringBufferSize)
        notations = Array(repeating: 0, count: ringBufferSize)
        averagesPerBand = Array(repeating: 0, count: bands)
        framePeriod = Float(bufferSize) / Float(samplingRate)
        previousSpectrum = Array(repeating: 100, count: bands)
        audioData = AudioData(delayLength: maximumLag, smoothDecay: smoothDecay, framePeriod: framePeriod, bandwidth: getBandWidth * 2)
    }

    func update(spectrums: [Float]) {
        calculateAveragePerBand(spectrums: spectrums)
        var onset: Float = 0
        for band in 0..<bands {
            var spectrumValue = max(-100, 20 * log10(averagesPerBand[band]) + 160)
            spectrumValue *= 0.025
            let dbIncrement = spectrumValue - previousSpectrum[band]
            previousSpectrum[band] = spectrumValue
            onset += dbIncrement
        }

        onsets[currentRingBufferPosition] = onset
        audioData?.updateAudioData(onset: onset)

        var maximumDelay: Float = 0
        var tempo = 0

        for i in 0..<maximumLag {
            var delayValue = sqrt(audioData?.delayAtIndex(delayIndex: i) ?? 0)
            if delayValue > maximumDelay {
                maximumDelay = delayValue
                tempo = i
            }
        }

        var maximumNotation: Float = -999999
        var maximumNotationIndex = 0

        for i in (tempo / 2)..<min(ringBufferSize, 2 * tempo) {
            var notation = onset + notations[(currentRingBufferPosition - i + ringBufferSize) % ringBufferSize] - changeThreshold * 100 * pow(log(Float(i) / Float(tempo)), 2)
            if notation > maximumNotation {
                maximumNotation = notation
                maximumNotationIndex = i
            }
        }
        notations[currentRingBufferPosition] = maximumNotation

        var minimumNotation = notations[0]
        for i in 0..<ringBufferSize {
            if notations[i] < minimumNotation {
                minimumNotation = notations[i]
            }
        }

        for i in 0..<ringBufferSize {
            notations[i] -= minimumNotation
        }

        maximumNotation = notations[0]
        maximumNotationIndex = 0
        for i in 0..<ringBufferSize {
            if notations[i] > maximumNotation {
                maximumNotation = notations[i]
                maximumNotationIndex = i
            }
        }
        framesSinceBeat += 1

        if maximumNotationIndex == currentRingBufferPosition {
            if limitBeats {
                if framesSinceBeat > tempo / limitAmount {
                    onBeatSubject.send()
                    framesSinceBeat = 0
                }
            } else {
                onBeatSubject.send()
            }
        }

        currentRingBufferPosition += 1
        if currentRingBufferPosition >= ringBufferSize {
            currentRingBufferPosition = 0
        }
    }

    func calculateAveragePerBand(spectrums: [Float]) {
        for band in 0..<bands {
            var averagePower = Float(0)
            let lowFrequencyIndex = band == 0 ? 0 : samplingRate / Int(pow(Float(2), Float(bands - band + 1)))
            let highFrequencyIndex = samplingRate / Int(pow(Float(2), Float(bands - band)))

            let lowBound = frequenceByIndex(frequencyIndex: lowFrequencyIndex)
            let highBound = frequenceByIndex(frequencyIndex: highFrequencyIndex)

            for spectrum in lowBound..<highBound {
                averagePower += spectrums[spectrum]
            }
            averagePower /= Float(highBound - lowBound)
            averagesPerBand[band] = averagePower
        }
    }

    func frequenceByIndex(frequencyIndex: Int) -> Int {
        if frequencyIndex < 0 {
            return 0
        }

        if frequencyIndex >= samplingRate / 2 {
            return bufferSize / 2
        }

        return (bufferSize * frequencyIndex) / samplingRate
    }
}

class AudioData {
    private var index: Int
    private var delayLength: Int
    private var smoothDecay: Float
    private var octaveWidth: Float
    private var framePeriod: Float

    private var delays: [Float]
    private var outputs: [Float]
    private var bpms: [Float]
    private var weights: [Float]

    init(delayLength: Int, smoothDecay: Float, framePeriod: Float, bandwidth: Float) {
        index = 0
        octaveWidth = bandwidth
        self.smoothDecay = smoothDecay
        self.delayLength = delayLength
        self.framePeriod = framePeriod

        delays = Array(repeating: 0, count: delayLength)
        outputs = Array(repeating: 0, count: delayLength)
        bpms = Array(repeating: 0, count: delayLength)
        weights = Array(repeating: 0, count: delayLength)

        applyWeights()
    }

    func applyWeights() {
        for i in 0..<delayLength {
            bpms[i] = 60 / (framePeriod * Float(i));
            weights[i] = exp(-0.5 * pow(log(bpms[i] / 120) / log(2) / octaveWidth, 2))
        }
    }

    func updateAudioData(onset: Float) {
        delays[index] = onset;

        for i in 0..<delayLength {
            var delayIndex = (index - i + delayLength) % delayLength
            outputs[i] += (1 - smoothDecay) * (delays[index] * delays[delayIndex] - outputs[i])
        }

        index += 1
        if index >= delayLength {
            index = 0
        }
    }

    func delayAtIndex(delayIndex: Int) -> Float {
        return weights[delayIndex] * outputs[delayIndex]
    }
}

