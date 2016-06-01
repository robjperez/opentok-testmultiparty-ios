//
//  ViewController.swift
//  testmultiparty
//
//  Created by Roberto Perez Cubero on 27/05/16.
//  Copyright © 2016 opentok. All rights reserved.
//

import UIKit
import OpenTok

let sessionInfo : [(sid: String, token: String)] = [
    ("sessionId1","token1"),
    ("sessionId2","token2")
]

let apiKey = "apiKey"

class ViewController: UICollectionViewController {
    
    var session: OTSession!
    var publisher: OTPublisher!
    var subscribers: [OTSubscriber] = []
    var reconnect = false
    var idx = 0
    
    var publishing = false {
        didSet {
            collectionView?.reloadData()
        }
    }
    
    var participants: Int {
        return publishing ? subscribers.count + 1 : 0
    }

    @IBOutlet weak var flowLayout: UICollectionViewFlowLayout!
    
    private func connectToSession() {
        let sessInfo = sessionInfo[idx]
        idx = (idx + 1) % sessionInfo.count
        
        session = OTSession(apiKey: apiKey, sessionId: sessInfo.sid, delegate: self)
        session.connectWithToken(sessInfo.token, error: nil)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        connectToSession()
        
        let width = view.frame.size.width
        let itemWidth = (width / 2) - flowLayout.minimumInteritemSpacing
        let itemHeight = itemWidth / 1.33
        flowLayout.itemSize = CGSize(width: itemWidth, height: itemHeight)
    }
    
    override func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView {
        if kind == UICollectionElementKindSectionHeader {
            return collectionView.dequeueReusableSupplementaryViewOfKind(kind, withReuseIdentifier: "header", forIndexPath: indexPath)
        }
        assert(false, "Unexpected kind")
    }
    
    override func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return 1
    }

    override func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
     return participants
    }
    
    override func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier("videoCell", forIndexPath: indexPath)
        
        let videoView: UIView = {
            switch indexPath.row {
            case 0:
                return publisher.view
            case (let idx):
                return subscribers[idx - 1].view
            }
        }()
        
        videoView.frame = cell.bounds
        cell.addSubview(videoView)
        return cell
    }
    
    @IBAction func changeSession(sender: AnyObject) {
        reconnect = true
        subscribers.forEach { session.unsubscribe($0, error: nil) }
        session.unpublish(publisher, error: nil)
    }
}

extension ViewController: OTSessionDelegate {
    func sessionDidConnect(session: OTSession!) {
        print("Session Connected")
        
        if !audioInUseByOtherApps() {
            publisher = OTPublisher(delegate: self)
            session.publish(publisher, error: nil)
        } else {
            print("Audio device was used by another app -> Disconnect")
            reconnect = true
            session.disconnect(nil)
        }
    }
    
    func sessionDidDisconnect(session: OTSession!) {
        print("Session Disconnected")
        
        if reconnect {
            reconnect = false
            connectToSession()
        }
    }
    
    func session(session: OTSession!, didFailWithError error: OTError!) {
        print("Session Error: \(error)")
    }
    
    func session(session: OTSession!, streamCreated stream: OTStream!) {
        print("Stream created: \(stream.streamId)")
        
        if !audioInUseByOtherApps() {
            let subscriber = OTSubscriber(stream: stream, delegate: self)
            session.subscribe(subscriber, error: nil)
            subscribers.append(subscriber)
        } else {
            print("Audio device was used by another app -> Disconnect")
            reconnect = true
            session.unpublish(publisher, error: nil)
        }
    }
    
    func session(session: OTSession!, streamDestroyed stream: OTStream!) {
        print("Stream Destroyed")
        subscribers = subscribers.filter { $0.stream.streamId != stream.streamId }
        collectionView?.reloadData()
    }
}

extension ViewController: OTPublisherDelegate {
    func publisher(publisher: OTPublisherKit!, streamCreated stream: OTStream!) {
        print("Publsher created")
        publishing = true
    }
    
    func publisher(publisher: OTPublisherKit!, streamDestroyed stream: OTStream!) {
        print("Publsher destroyed")
        publishing = false
        session.disconnect(nil)
    }
    
    func publisher(publisher: OTPublisherKit!, didFailWithError error: OTError!) {
        print("Publish failed \(error)!")
    }
}

extension ViewController: OTSubscriberDelegate {
    func subscriberDidConnectToStream(subscriber: OTSubscriberKit!) {
        print("Subscriber connected")
        collectionView?.reloadData()
    }
    
    func subscriberVideoDisableWarning(subscriber: OTSubscriberKit!) {
        
    }
    
    func subscriberVideoDisableWarningLifted(subscriber: OTSubscriberKit!) {
        
    }
    
    func subscriberVideoEnabled(subscriber: OTSubscriberKit!, reason: OTSubscriberVideoEventReason) {
        
    }
    
    func subscriberVideoDisabled(subscriber: OTSubscriberKit!, reason: OTSubscriberVideoEventReason) {
        
    }
    
    func subscriber(subscriber: OTSubscriberKit!, didFailWithError error: OTError!) {
        
    }
    
    func subscriberDidDisconnectFromStream(subscriber: OTSubscriberKit!) {
        
    }
    
    func subscriberVideoDataReceived(subscriber: OTSubscriber!) {
        
    }
}

