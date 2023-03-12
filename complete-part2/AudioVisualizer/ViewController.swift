//
//  ViewController.swift
//  AudioVisualizer
//
//  Created by Alex Barbulescu on 2019-04-06.
//  Copyright © 2019 alex. All rights reserved.
//

import Cocoa
import AVFoundation
import Accelerate
import Combine

class ViewController: NSViewController {
    var engine : AVAudioEngine!
    var audioVisualizer : AudioVisualizer!
    var beatDetection: BeatDetection!
    var cancellable: AnyCancellable?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        audioVisualizer = AudioVisualizer()
        beatDetection = BeatDetection()
        view.addSubview(audioVisualizer)
        
        //constraining to window
        audioVisualizer.topAnchor.constraint(equalTo: view.topAnchor).isActive = true
        audioVisualizer.leadingAnchor.constraint(equalTo: view.leadingAnchor).isActive = true
        audioVisualizer.trailingAnchor.constraint(equalTo: view.trailingAnchor).isActive = true
        audioVisualizer.bottomAnchor.constraint(equalTo: view.bottomAnchor).isActive = true
        
        setupAudio()

        cancellable = beatDetection.onBeatSubject.sink { [weak self] in
            let red = Double((0...255).randomElement() ?? 0) / 256
            let green = Double((0...255).randomElement() ?? 0) / 256
            let blue = Double((0...255).randomElement() ?? 0) / 256
            self?.audioVisualizer.color = [red, green, blue, 1]
        }
    }
    
    func setupAudio(){
        /* Setup & Start Engine */
        
        //initialize it
        engine = AVAudioEngine()
        
        //initialzing the mainMixerNode singleton which will connect to the default output node
        _ = engine.mainMixerNode
        
        //prepare and start
        engine.prepare()
        do {
            try engine.start()
        } catch {
            print(error)
        }
        
        /* Add a player node (our music!) to the engine */
        
        //first we need the resource url for our file
        guard let url = Bundle.main.url(forResource: "music", withExtension: "mp3") else {
            print("mp3 not found")
            return
        }
        
        //now we need to create our player node
        let player = AVAudioPlayerNode()
        
        do {
            //player nodes have a few ways to play-back music, the easiest way is from an AVAudioFile
            let audioFile = try AVAudioFile(forReading: url)
            
            //audio always has a format, lets keep track of what the format is as an AVAudioFormat
            let format = audioFile.processingFormat
            print(format)
            
            //we now need to connect add the node to our engine. This part is a little weird but we first need
            //to attach it to the engine itself before connecting it to the mainMixerNode. Recall that the
            //mainMixerNode connects to the default outputNode, so now we'll have a complete playback path from
            //our file to the outputNode!
            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: format)
            
            //let's play the file!
            //note: player must be attached first before scheduling a file to play
            player.scheduleFile(audioFile, at: nil, completionHandler: nil)
        } catch let error {
            print(error.localizedDescription)
        }
        
        //tap it to get the buffer data at playtime
        
        engine.mainMixerNode.installTap(onBus: 0, bufferSize: 1024, format: nil) { [weak self] buffer, time in
            DispatchQueue.global().async {
                self?.processAudioData(buffer: buffer)
            }
        }
        
        //start playing the music!
        player.play()
        
    }
    
    var prevRMSValue : Float = 0.3
    
    //fft setup object for 1024 values going forward (time domain -> frequency domain)
    let fftSetup = vDSP_DFT_zop_CreateSetup(nil, 1024, vDSP_DFT_Direction.FORWARD)

    func processAudioData(buffer: AVAudioPCMBuffer){
        guard let channelData = buffer.floatChannelData?[0] else {return}
        let frames = buffer.frameLength
        
        //rms
        let rmsValue = SignalProcessing.rms(data: channelData, frameLength: UInt(frames))
        let interpolatedResults = SignalProcessing.interpolate(current: rmsValue, previous: prevRMSValue)
        prevRMSValue = rmsValue
        
        //pass values to the audiovisualizer for the rendering
        for rms in interpolatedResults {
            audioVisualizer.loudnessMagnitude = rms
        }
        
        //fft
        let fftMagnitudes =  SignalProcessing.fft(data: channelData, setup: fftSetup!)
        beatDetection.update(spectrums: fftMagnitudes)
        audioVisualizer.frequencyVertices = fftMagnitudes
    }
}

