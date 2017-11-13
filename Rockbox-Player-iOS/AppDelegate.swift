//
//  AppDelegate.swift
//  Rockbox-Player-iOS
//
//  Created by Jon Reiling on 8/23/17.
//  Copyright © 2017 Reiling. All rights reserved.
//

import UIKit
import SafariServices
import PusherSwift
import Alamofire

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate,SPTAudioStreamingDelegate,SPTAudioStreamingPlaybackDelegate {

    
    var window: UIWindow?
    var auth: SPTAuth!
    var player: SPTAudioStreamingController!
    var authViewController: UIViewController!
    var timer:Timer?
    var setup = false
    var pusher:Pusher!

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplicationLaunchOptionsKey: Any]?) -> Bool {
        // Override point for customization after application launch.
        
        SPTAuth.defaultInstance().tokenSwapURL = URL(string:"https://calm-everglades-36827.herokuapp.com/swap")
        SPTAuth.defaultInstance().tokenRefreshURL = URL(string:"https://calm-everglades-36827.herokuapp.com/refresh")

        auth = SPTAuth.defaultInstance()
        auth.clientID = "ee5bcc2c221c4a98814e88612c5e289a"
        auth.redirectURL = URL(string: "rockbox-player-ios-login://callback")
        auth.sessionUserDefaultsKey = "current session"
        auth.requestedScopes = [SPTAuthStreamingScope]
        
        player = SPTAudioStreamingController.sharedInstance()
        player.delegate = self
        player.playbackDelegate = self
        
        do {
            print("try!")
            try self.player.start(withClientId: auth.clientID )
            
        } catch let error {
            print("Error!")
            print(error)
        }
        
        DispatchQueue.main.async
        {
            self.startAuthenticationFlow()
        }
        
        UIApplication.shared.isIdleTimerDisabled = true
        
        return true
    }
    
    func setupSockets() {
        setup = true
        NSLog("setupSockets")

        let options = PusherClientOptions(
            host: .cluster("us2")
        )

        pusher = Pusher(key: "1276e8d2c9675878f90d",options: options)
        let rockboxChannel = pusher.subscribe("rockbox")
        let _ = pusher.subscribe("rockbox-server")

        rockboxChannel.bind(eventName: "play-state-updated", callback: { (data: Any?) -> Void in
            
            print("play-state-updated")
            if let d = data as? [String : AnyObject] {
                if ( d["playing"] as! Bool ) {
                    print("play")
                    self.player.setIsPlaying(true, callback: nil)
                } else {
                    print("pause")
                    self.player.setIsPlaying(false, callback: nil)
                }
            }

            
        })
        
        rockboxChannel.bind(eventName: "track-updated", callback: { (data: Any?) -> Void in
            NSLog( "track-updated")
            if let d = data as? [String : AnyObject] {

                let id = d["track"]!["id"]! as! String
                NSLog( id )
                self.player.playSpotifyURI(id, startingWith: 0, startingWithPosition: 0) { (error) in
                    print("error")
                    print(error)
                }
            }
        })

        rockboxChannel.bind(eventName: "volume-updated", callback: { (data: Any?) -> Void in
            NSLog( "volume-updated")
            if let d = data as? [String : AnyObject] {
                
                if let volume = d["volume"] as? Double {
                    if ( volume >= 0 && volume <= 100 ) {
                        self.player.setVolume(volume/100, callback: nil)
                    }
                }
            }
        })

        
        pusher.connect()
    }
    
    func startAuthenticationFlow() {
        print("startAuthenticationFlow!")
        if ( self.auth.session != nil && self.auth.session.isValid() ) {
            print(auth.session.accessToken)
            player.login(withAccessToken: auth.session.accessToken)
            
        } else {
            authViewController = SFSafariViewController(url: self.auth.spotifyWebAuthenticationURL() )
            self.window?.rootViewController?.present(authViewController, animated: true, completion: nil)
        }
        
    }
    
    func application(_ app: UIApplication, open url: URL, options: [UIApplicationOpenURLOptionsKey : Any] = [:]) -> Bool {
        
        if ( auth.canHandle(url)) {
            authViewController.presentingViewController?.dismiss(animated: true, completion: nil)
            authViewController = nil
            
            auth.handleAuthCallback(withTriggeredAuthURL: url, callback: { (error, session) in
                if ( session != nil ) {
                    self.player.login(withAccessToken: self.auth.session.accessToken)
                }
                
                
            })
            
            return true
            
        }
        
        return false
    }
    
    func audioStreaming(_ audioStreaming: SPTAudioStreamingController!, didStopPlayingTrack trackUri: String!) {
        NSLog("track done!")
        Alamofire.request("http://rockbox.jonreiling.com/api/v1/skip", method: .post)
        
        
       // socket.emit("endOfTrack", with: [])
    }

    func applicationWillResignActive(_ application: UIApplication) {
        // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
        // Use this method to pause ongoing tasks, disable timers, and invalidate graphics rendering callbacks. Games should use this method to pause the game.
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later.
        // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        // Called as part of the transition from the background to the active state; here you can undo many of the changes made on entering the background.
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    }
    
    func audioStreamingDidLogin(_ audioStreaming: SPTAudioStreamingController!) {
        print("logged in!")
        
        if ( !setup ) {
            setupSockets()
        }
    }
    
    func renew() {
        NSLog("renew")
        print(auth.tokenSwapURL)
        print(auth.tokenRefreshURL)
        print(auth.session.isValid())
        auth.renewSession(auth.session) { (error, _session) in
            NSLog("session renewed")
            print(_session?.isValid())
            self.auth.session = _session
            //self.player.login(withAccessToken: self.auth.session.accessToken)
            if ( error != nil ) {
                print(error)
            } else {
                
                self.timer = Timer.scheduledTimer(withTimeInterval: self.auth.session.expirationDate.timeIntervalSinceNow, repeats: false) { (_) in
                    
                    self.renew()
                }
            }
        }

    }


}

