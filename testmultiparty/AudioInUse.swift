//
//  AudioInUse.swift
//  testmultiparty
//
//  Created by Roberto Perez Cubero on 31/05/16.
//  Copyright © 2016 opentok. All rights reserved.
//

import Foundation

func audioInUseByOtherApps() -> Bool {
    var result = false
    do {
        try AVAudioSession.sharedInstance().setCategory(AVAudioSessionCategoryPlayAndRecord)
        try AVAudioSession.sharedInstance().setActive(true)
    } catch let error as NSError  {
        print("--- Error while activating audio session: \n \(error)")
        
        //Note: we can change the error code to enum later, for better readability
        if error.code == 561017449 //AVAudioSessionErrorInsufficientPriority
        {
            result = true
            print("audio is in use by other apps")
        }
        if error.code == 1768843583 // kAudioSessionInitializationError
        {
            result = true
            print("audio session initialization error (may be bad or unsupported audio device)")
        }
    }
    
    return result
}
