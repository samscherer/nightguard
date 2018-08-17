//
//  MainViewController.swift
//  scoutwatch
//
//  Created by Dirk Hermanns on 02.01.16.
//  Copyright © 2016 private. All rights reserved.
//

import UIKit
import MediaPlayer
import WatchConnectivity
import SpriteKit

class MainViewController: UIViewController {
    
    @IBOutlet weak var bgLabel: UILabel!
    @IBOutlet weak var deltaLabel: UILabel!
    @IBOutlet weak var deltaArrowsLabel: UILabel!
    @IBOutlet weak var timeLabel: UILabel!
    @IBOutlet weak var lastUpdateLabel: UILabel!
    @IBOutlet weak var batteryLabel: UILabel!
    @IBOutlet weak var iobLabel: UILabel!
    @IBOutlet weak var snoozeButton: UIButton!
    @IBOutlet weak var screenlockSwitch: UISwitch!
    @IBOutlet weak var volumeContainerView: UIView!
    @IBOutlet weak var spriteKitView: UIView!
    @IBOutlet weak var errorPanelView: UIView!
    @IBOutlet weak var errorLabel: UILabel!
    @IBOutlet weak var rawValuesPanel: GroupedLabelsView!
    @IBOutlet weak var bgStackView: UIStackView!
    
    // the way that has already been moved during a pan gesture
    var oldXTranslation : CGFloat = 0
    
    var chartScene = ChartScene(size: CGSize(width: 320, height: 280), newCanvasWidth: 1024)
    // timer to check continuously for new bgValues
    var timer = Timer()
    // another timer to restart the timer for the case that a watchdog kills it
    // the latter can happen, when the request takes too long :-/
    var safetyResetTimer = Timer()
    
    // check every 30 Seconds whether new bgvalues should be retrieved
    let timeInterval: TimeInterval = 30.0
    // kill and restart the timer every 12 minutes
    let safetyResetTimerInterval: TimeInterval = 60.0 * 12
    
    override var supportedInterfaceOrientations : UIInterfaceOrientationMask {
        return UIInterfaceOrientationMask.portrait
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Embed the Volume Slider View
        // This way the system volume can be
        // controlled by the user
        let volumeView = MPVolumeView(frame: volumeContainerView.bounds)
        volumeView.backgroundColor = UIColor.black
        volumeView.tintColor = UIColor.gray
        volumeContainerView.addSubview(volumeView)
        // add an observer to resize the MPVolumeView when displayed on e.g. 4.7" iPhone
        volumeContainerView.addObserver(self, forKeyPath: "bounds", options: [], context: nil)
        
        restoreGuiState()
        paintScreenLockSwitch()
        
        // Start the timer to retrieve new bgValues
        startTimer()
        safetyResetTimer = Timer.scheduledTimer(timeInterval: safetyResetTimerInterval,
                                     target: self,
                                     selector: #selector(MainViewController.safetyResetTimerDidEnd(_:)),
                                     userInfo: nil,
                                     repeats: true)
        
        // Initialize the ChartScene
        chartScene = ChartScene(size: CGSize(width: spriteKitView.bounds.width, height: spriteKitView.bounds.height),
                                newCanvasWidth: self.maximumDeviceTextureWidth())
        let skView = spriteKitView as! SKView
        skView.presentScene(chartScene)
        
        // Register Gesture Recognizer so that the user can scroll
        // through the charts
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(MainViewController.panGesture(_:)))
        let pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(MainViewController.pinchGesture(_:)))
        
        skView.addGestureRecognizer(panGesture)
        skView.addGestureRecognizer(pinchGesture)
        
        errorPanelView.isHidden = true
        
        // decide where to present the raw bg panel, depending on the device screen size: for small screens (under 4.7 inches) the raw bg panel is stacked under the bg label; for larger screens, the raw bg panel is near (right side of) the bg label
        let screenSize = UIScreen.main.bounds.size
        let height = max(screenSize.width, screenSize.height)
        let isLargeEnoughScreen = height >= 667 // 4.7 inches or larger (iPhone 6, etc.)
        rawValuesPanel.axis = isLargeEnoughScreen ? .vertical : .horizontal
        bgStackView.axis = isLargeEnoughScreen ? .horizontal : .vertical
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        showHideRawBGPanel()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        
        // Start immediately so that the current time gets displayed at once
        // And the alarm can play if needed
        timerDidEnd(timer)
        
        UIDevice.current.setValue(UIInterfaceOrientation.landscapeRight.rawValue, forKey: "orientation")
        UIDevice.current.setValue(UIInterfaceOrientation.portrait.rawValue, forKey: "orientation")
        
        chartScene.size = CGSize(width: spriteKitView.bounds.width, height: spriteKitView.bounds.height)
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
 
        chartScene.stopSwipeAction()
    }
    
    @objc func panGesture(_ recognizer : UIPanGestureRecognizer) {
        
        if recognizer.state == UIGestureRecognizerState.began {
            oldXTranslation = 0

            // The user just touched the display
            // So we use this to stop eventually running actions
            chartScene.stopSwipeAction()
        }
        let translation = recognizer.translation(in: spriteKitView)

        chartScene.draggedByATouch(translation.x - oldXTranslation)
        oldXTranslation = translation.x
        
        if (recognizer.state == UIGestureRecognizerState.ended) {
            let velocity = recognizer.velocity(in: spriteKitView)
            
            if (velocity.x < -100) {
                // Left Swipe detected
                chartScene.swipeChart(velocity.x)
            } else if (velocity.x > 100) {
                // Right Swipe detected
                chartScene.swipeChart(velocity.x)
            }
        }
    }
    
    // This gesture is used to zoom in and out by changing the maximum
    // Blood Glucose value that is displayed in the chart.
    @objc func pinchGesture(_ recognizer : UIPinchGestureRecognizer) {
        
        if recognizer.state == UIGestureRecognizerState.ended {
            chartScene.scale(recognizer.scale, keepScale: true, infoLabelText: "")
        } else {
            chartScene.scale(recognizer.scale, keepScale: false, infoLabelText: "")
        }
    }
    
    // Resize the MPVolumeView when the parent view changes
    // This is needed on an e.g. 4,7" iPhone. Otherwise the MPVolumeView would be too small
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {

        let volumeView = MPVolumeView(frame: volumeContainerView.bounds)
        volumeView.backgroundColor = UIColor.black
        volumeView.tintColor = UIColor.gray

        for view in volumeContainerView.subviews {
            view.removeFromSuperview()
        }
        volumeContainerView.addSubview(volumeView)
    }
    
    fileprivate func restoreGuiState() {
        
        screenlockSwitch.isOn = GuiStateRepository.singleton.loadScreenlockSwitchState()
        doScreenlockAction(self)
    }
    
    override var preferredStatusBarStyle : UIStatusBarStyle {
        return UIStatusBarStyle.lightContent
    }
    
    func startTimer() {
        timer = Timer.scheduledTimer(timeInterval: timeInterval,
                                     target: self,
                                     selector: #selector(MainViewController.timerDidEnd(_:)),
                                     userInfo: nil,
                                     repeats: true)
    }
    
    @objc func safetyResetTimerDidEnd(_ timer: Timer) {
        timer.invalidate()
        startTimer()
    }
    
    // check whether new Values should be retrieved
    @objc func timerDidEnd(_ timer:Timer) {
        
        if AlarmRule.isAlarmActivated(NightscoutCacheService.singleton.getCurrentNightscoutData(), bloodValues: NightscoutCacheService.singleton.getTodaysBgData()) {
            
            // Play the sound only if foreground => otherwise this won't work at all
            // and the sound will only play right when opening the application :-/
            let state = UIApplication.shared.applicationState
            if state == UIApplicationState.active {
                AlarmSound.play()
            }
        } else {
            AlarmSound.stop()
        }
        updateSnoozeButtonText()
        
        paintCurrentTime()
        // paint here is need if the server doesn't respond
        // => in that case the user has to know that the values are old!
        loadAndPaintCurrentBgData()
        loadAndPaintChartData(forceRepaint: false)
    }
    
    fileprivate func paintScreenLockSwitch() {
        screenlockSwitch.isOn = UIApplication.shared.isIdleTimerDisabled
    }
    
    @IBAction func doSnoozeAction(_ sender: AnyObject) {
        
        if AlarmRule.isSnoozed() {
            AlarmRule.disableSnooze()
            snoozeButton.setTitle("Snooze", for: UIControlState())
        } else {
            // stop the alarm immediatly here not to disturb others
            AlarmSound.muteVolume()
            showSnoozePopup()
            // For safety reasons: Unmute sound after 1 minute
            // This prevents an unlimited snooze if the snooze button was touched accidentally.
            DispatchQueue.main.asyncAfter(deadline: .now() + 30.0, execute: {
                AlarmSound.unmuteVolume()
            })
        }
    }
    
    fileprivate func showSnoozePopup() {
        
        // create the snooze popup view
        if let snoozeAlarmViewController = self.storyboard?.instantiateViewController(
            withIdentifier: "snoozeAlarmViewController") as? SnoozeAlarmViewController {
            
            self.present(snoozeAlarmViewController, animated: true, completion: nil)
        }
    }
    
    public func updateSnoozeButtonText() {
        
        if AlarmRule.isSnoozed() {
            snoozeButton.setTitle("Snoozed for " + String(AlarmRule.getRemainingSnoozeMinutes()) + "min", for: UIControlState())
        } else {
            snoozeButton.setTitle("Snooze", for: UIControlState())
        }
    }
    
    @IBAction func doScreenlockAction(_ sender: AnyObject) {
        if screenlockSwitch.isOn {
            UIApplication.shared.isIdleTimerDisabled = true
            GuiStateRepository.singleton.storeScreenlockSwitchState(true)
            
            displayScreenlockInfoMessageOnlyOnce()
        } else {
            UIApplication.shared.isIdleTimerDisabled = false
            GuiStateRepository.singleton.storeScreenlockSwitchState(false)
        }
    }
    
    fileprivate func displayScreenlockInfoMessageOnlyOnce() {
        let screenlockMessageShowed = UserDefaults.standard.bool(forKey: "screenlockMessageShowed")
        
        if !screenlockMessageShowed {
            
            let alertController = UIAlertController(title: "Keep the screen active", message: "Turn this switch to disable the screenlock and prevent the app to get stopped!", preferredStyle: .alert)
            let actionOk = UIAlertAction(title: "OK", style: .default, handler: nil)
            alertController.addAction(actionOk)
            present(alertController, animated: true, completion: nil)
            
            UserDefaults.standard.set(true, forKey: "screenlockMessageShowed")
        }
    }
    
    fileprivate func paintCurrentTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        self.timeLabel.text = formatter.string(from: Date())
    }
    
    fileprivate func loadAndPaintCurrentBgData() {
        
        let currentNightscoutData = NightscoutCacheService.singleton.loadCurrentNightscoutData({(newNightscoutData, error) -> Void in
            
            if let error = error {
                self.errorLabel.text = "❌ \(error.localizedDescription)"
                self.errorLabel.textColor = .red
                self.errorPanelView.isHidden = false
            } else if let newNightscoutData = newNightscoutData {
                self.errorPanelView.isHidden = true
                self.paintCurrentBgData(currentNightscoutData: newNightscoutData)
                
                WatchService.singleton.sendToWatchCurrentNightwatchData()
            }
        })
        
        paintCurrentBgData(currentNightscoutData: currentNightscoutData)
    }
    
    fileprivate func paintCurrentBgData(currentNightscoutData : NightscoutData) {
        
        DispatchQueue.main.async(execute: {
            if currentNightscoutData.sgv == "---" {
                self.bgLabel.text = "---"
            } else {
                self.bgLabel.text = currentNightscoutData.sgv
            }
            self.bgLabel.textColor = UIColorChanger.getBgColor(currentNightscoutData.sgv)
            
            self.deltaLabel.text = currentNightscoutData.bgdeltaString.cleanFloatValue
            self.deltaArrowsLabel.text = currentNightscoutData.bgdeltaArrow
            self.deltaLabel.textColor = UIColorChanger.getDeltaLabelColor(NSNumber(value: currentNightscoutData.bgdelta))
            self.deltaArrowsLabel.textColor = UIColorChanger.getDeltaLabelColor(NSNumber(value: currentNightscoutData.bgdelta))
            
            self.lastUpdateLabel.text = currentNightscoutData.timeString
            self.lastUpdateLabel.textColor = UIColorChanger.getTimeLabelColor(currentNightscoutData.time)
            
            self.batteryLabel.text = currentNightscoutData.battery
            self.iobLabel.text = currentNightscoutData.iob
            
            self.showHideRawBGPanel(currentNightscoutData)
            self.rawValuesPanel.label.text = currentNightscoutData.noise
            self.rawValuesPanel.highlightedLabel.text = currentNightscoutData.rawbg
        })
    }
    
    fileprivate func loadAndPaintChartData(forceRepaint : Bool) {
        
        let newCachedTodaysBgValues = NightscoutCacheService.singleton.loadTodaysData({(newTodaysData) -> Void in
            
            let cachedYesterdaysData = NightscoutCacheService.singleton.getYesterdaysBgData()
            self.paintChartData(todaysData: newTodaysData, yesterdaysData: cachedYesterdaysData)
        })
        let newCachedYesterdaysBgValues = NightscoutCacheService.singleton.loadYesterdaysData({(newYesterdaysData) -> Void in
            
            let cachedTodaysBgData = NightscoutCacheService.singleton.getTodaysBgData()
            self.paintChartData(todaysData: cachedTodaysBgData, yesterdaysData: newYesterdaysData)
        })
        
        // this does a fast paint of eventually cached data
        if forceRepaint ||
            NightscoutCacheService.singleton.valuesChanged() {
            
            paintChartData(todaysData: newCachedTodaysBgValues, yesterdaysData: newCachedYesterdaysBgValues)
        }
    }
    
    fileprivate func paintChartData(todaysData : [BloodSugar], yesterdaysData : [BloodSugar]) {
        
        self.chartScene.paintChart(
            [todaysData, yesterdaysData],
            newCanvasWidth: self.maximumDeviceTextureWidth(),
            maxYDisplayValue: CGFloat(UserDefaultsRepository.readMaximumBloodGlucoseDisplayed()),
            moveToLatestValue: true)
    }
    
    fileprivate func showHideRawBGPanel(_ nightscoutData: NightscoutData? = nil) {
        
        let currentNightscoutData = nightscoutData ?? NightscoutCacheService.singleton.getCurrentNightscoutData()
        let isValidRawBGValue = UnitsConverter.toMgdl(currentNightscoutData.rawbg) > 0

        // show raw values panel ONLY if configured so and we have a valid rawbg value!
        self.rawValuesPanel.isHidden = !UserDefaultsRepository.readShowRawBG() || !isValidRawBGValue
    }
}
