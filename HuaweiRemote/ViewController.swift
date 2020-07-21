//
//  ViewController.swift
//  HuaweiRemote
//
//  Created by jia xiaodong on 7/11/20.
//  Copyright © 2020 homemade. All rights reserved.
//

import UIKit
import Foundation

import AudioToolbox			// make iPhone vibrate
import SystemConfiguration	// Settings Bundle

enum NetworkStatus: Int
{
	case NETWORK_NOT_REACHABLE	= 0
	case NETWORK_THRU_WIFI		= 1
	case NETWORK_THRU_WWAN		= 2
}

//! Swift obj reference --> Unmanaged C Pointer
func bridge<T : AnyObject>(obj : T) -> UnsafePointer<Void> {
	return UnsafePointer(Unmanaged.passUnretained(obj).toOpaque())
	// return unsafeAddressOf(obj) // ***
}

//! Unmanaged C Pointer --> Swift obj reference
func bridge<T : AnyObject>(ptr : UnsafePointer<Void>) -> T {
	return Unmanaged<T>.fromOpaque(COpaquePointer(ptr)).takeUnretainedValue()
	// return unsafeBitCast(ptr, T.self) // ***
}

/*
  TODO: I copied the code from Internet and it works. But I can't understand
  below mess of slashes. What a regex syntax it's using?
  \\.    literal "." (period)
  \\d    ?
*/
func isValidIPv4Address(addr: String) -> Bool {
	let regex = "^([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
		"([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
		"([01]?\\d\\d?|2[0-4]\\d|25[0-5])\\." +
		"([01]?\\d\\d?|2[0-4]\\d|25[0-5])$"
	let predicate = NSPredicate(format:"SELF MATCHES %@", regex)
	return predicate.evaluateWithObject(addr)
}

//! callback which can receive device's event of network status changing
func ReachabilityCallback(target: SCNetworkReachability, flags: SCNetworkReachabilityFlags, info: UnsafeMutablePointer<Void>)
{
	let checker: ViewController = bridge(info);
	checker.parseReachabilityFlags(flags);
}

class ViewController: UIViewController {

	// These magic numbers are extracted from http://health.vmall.com/mediaQ/controller.jsp
	enum ActionCode: Int
	{
		case ACTION_NULL		= -1
		case ACTION_OK			= 0
		case ACTION_LEFT		= 1
		case ACTION_DOWN		= 2
		case ACTION_RIGHT		= 3
		case ACTION_UP			= 4
		case ACTION_BACK		= 5
		case ACTION_HOME		= 6
		case ACTION_MENU		= 7
		case ACTION_POWER		= 8
		case ACTION_VOL_UP		= 9
		case ACTION_VOL_DOWN	= 10
	}
	
	//! IP address of Huawei set-top box
	private var mBoxIPAddress: String
	var BoxIPAddress: String
	{
		get { return mBoxIPAddress }
		set { mBoxIPAddress = newValue }
	}
	
	//! user can pan his finger to four directions
	enum ActionDirection
	{
		case DIRECTION_INVALID
		case DIRECTION_LEFT
		case DIRECTION_DOWN
		case DIRECTION_RIGHT
		case DIRECTION_UP
		
		func toActionCode() -> ActionCode {
			switch self {
			case .DIRECTION_LEFT:
				return .ACTION_LEFT
			case .DIRECTION_RIGHT:
				return .ACTION_RIGHT
			case .DIRECTION_UP:
				return .ACTION_UP
			case .DIRECTION_DOWN:
				return .ACTION_DOWN
			default:
				return .ACTION_NULL
			}
		}
	}
	private var mCurrDirection, mPrevDirection: ActionDirection
	var CurrentDir: ActionDirection
	{
		get { return mCurrDirection }
		set { mCurrDirection = newValue }
	}
	var PreviousDir: ActionDirection
	{
		get { return mPrevDirection }
		set { mPrevDirection = newValue }
	}
	
	//! process long-press gesture when finger panning
	var mRepeatDelayer, mActionRepeater: NSTimer?
	
	//! Single-tap or Double-tap OK
	var mIsDoubleTapOK: Bool
	var mTapGesture: UITapGestureRecognizer
	
	var mAqiReady, mDetailReady: Bool
	
	//! User Settings
	let DEFAULT_IP_ADDRESS	= "192.168.1.102";	// for Huawei set-top box
	let KEY_BOX_IP_ADDRESS	= "box_ip_address"
	let KEY_DOUBLE_TAP_OK	= "double_tap_ok";
	let KEY_FORECAST_INFO	= "forecast_info";
	let KEY_TODAY_DETAILS	= "detailed_forecast";
	let KEY_ALARM_INFO		= "alarm_info";		// reserved
	let KEY_LOCATION		= "location_setting";
	let KEY_DISABLE_ERR_MSG	= "disable_error_message"
	var mConfigNeedReload	= false
	var ConfigNeedReload: Bool {
		get { return mConfigNeedReload }
		set { mConfigNeedReload = newValue }
	}
	
	//! detect Wifi network status
	var mNetworkStatus: NetworkStatus
	private var mReachabilityPtr: SCNetworkReachability?
	var mURLSession: NSURLSession!  // FIXME: what a "!" is used for?
	private var mIgnoreNetError: Bool = false
	
	//! gesture area
	private var mGestureRectTop: CGFloat	// Y-coordinate
	
	//! UI
	@IBOutlet weak var mWeatherButton: UIButton!
	var mLblWeatherInfo: UILabel?	// all info is placed here
	var mScrollView: UIScrollView?	// text's too long, so need a scroll-effect
	
	var mWeatherSource: WeatherFullReport?
	
	// FIXME: why is it required? What is NSCoder?
	required init?(coder aDecoder: NSCoder) {
		mBoxIPAddress = DEFAULT_IP_ADDRESS
		mCurrDirection = ActionDirection.DIRECTION_INVALID
		mPrevDirection = mCurrDirection
		mRepeatDelayer = nil
		mActionRepeater = nil
		mIsDoubleTapOK = false
		mTapGesture = UITapGestureRecognizer()
		mNetworkStatus = NetworkStatus.NETWORK_THRU_WIFI
		mAqiReady = false
		mDetailReady = false
		mGestureRectTop = CGFloat(0)
		
		let config = NSURLSessionConfiguration.defaultSessionConfiguration()
		config.timeoutIntervalForRequest = 1.0
		mURLSession = NSURLSession(configuration: config,
		                           delegate: nil,		// we don't need delegate to monitor task status,
		                           delegateQueue: nil)	// so ignore this queue, too.
		
		//! FIXME: must be placed at bottom.
		//! If placed topmost, compiler won't happy. Why?
		super.init(coder: aDecoder)
	}

	override func viewDidLoad() {
		super.viewDidLoad()
		
		// Localized button title
		let strTitle = NSLocalizedString("View Weather", comment: "request weather info")
		mWeatherButton.setTitle(strTitle, forState: .Normal)
		
		loadUserConfig()
		
		detectGestureArea()
		setupGestures()
		
		// Do any additional setup after loading the view, typically from a nib.
		getCurrentNetworkPath()
		startMonitorNetwork()
	}

	override func didReceiveMemoryWarning() {
		super.didReceiveMemoryWarning()
		// Dispose of any resources that can be recreated.
	}

	@IBAction func powerClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_POWER)
	}
	
	@IBAction func homeClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_HOME)
	}
	
	@IBAction func menuClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_MENU)
	}
	
	@IBAction func volDownClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_VOL_DOWN)
	}
	
	@IBAction func volUpClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_VOL_UP)
	}
	
	@IBAction func backClicked(sender: UIButton) {
		performAction(ActionCode.ACTION_BACK)
	}
	
	@IBAction func weatherClicked(sender: UIButton) {
		if mWeatherSource == nil {
			// UI
			let title = NSLocalizedString("Close", comment: "stop request")
			mWeatherButton.setTitle(title, forState: .Normal)
			createScrollLable()
			
			// create a new weather service provider everytime of querying.
			mWeatherSource = WeatherFullReport()
			
			// check weather settings
			mWeatherSource?.ItemOther.options = []  // clear all bits
			mWeatherSource?.ItemOther.options.insert(WeatherOption.WEATHER_NOW)
			let config = NSUserDefaults.standardUserDefaults()
			let showForecastInfo = config.boolForKey(KEY_FORECAST_INFO)
			if showForecastInfo {
				mWeatherSource?.ItemOther.options.insert(WeatherOption.WEATHER_FORECAST)
			}
			let showTodayDetails = config.boolForKey(KEY_TODAY_DETAILS)
			if showTodayDetails {
				mWeatherSource?.ItemOther.options.insert(WeatherOption.WEATHER_DETAIL_FORECAST)
			}
			let locationNumber = config.integerForKey(KEY_LOCATION)
			let locationID = LocationID(rawValue: locationNumber)!
			
			let setLabelText: (String)->Void = {(text) in
				if let label = self.mLblWeatherInfo {
					label.text = text
					label.sizeToFit()					// resize UILabel to fit content (height)
					if let parent = self.mScrollView {	// make whole area scrollable
						parent.contentSize = label.frame.size
					}
				}
			}
			
			mWeatherSource?.query(locationID,
				AqiCompletionHandler: {(aqi) in
					var report = ""
					if let weather = self.mLblWeatherInfo?.text {
						report = weather
					}
					setLabelText("\(aqi)\(report)")
				},
				WeatherCompletionHandler: {(forecast) in
					var report = ""
					if let aqi = self.mLblWeatherInfo?.text {
						report = aqi
					}
					setLabelText("\(report)\(forecast)")
				}
			) // end query
		} else {
			mScrollView?.resignFirstResponder()
			mScrollView?.removeFromSuperview()
			mLblWeatherInfo?.removeFromSuperview()
			mScrollView = nil
			mLblWeatherInfo = nil
			mWeatherSource = nil
			let title = NSLocalizedString("View Weather", comment: "request weather info")
			mWeatherButton.setTitle(title, forState: .Normal)
		}
	}
	
	//! all commands of Huawei remote control are executed (sent) here!
	func performAction(code: ActionCode)
	{
		// remote control must work under same local Wifi network to the Huawei set-top box.
		if mNetworkStatus != .NETWORK_THRU_WIFI {
			return
		}

		/* dispatch command to main queue so as to avoid UI blocking.
		*
		* App Transport Security blocks cleartext HTTP request by default iOS Device Policy.
		* In order to send Huawei HTTP command, below setting must be present in Info.plist file:
		*   {
		*      "App Transport Security Settings": {
		*         "Allow Arbitrary Loads": YES
		*      }
		*   }
		*/
		let url = NSURL(string: "http://\(mBoxIPAddress):7766/remote?key=\(code.rawValue)")
		let task = mURLSession.dataTaskWithURL(url!) {(data, response, error) in
			if error == nil {
				return
			}
			
			if self.mIgnoreNetError {
				return
			}
			
			/*
				Display localized message-box to user in main thread (Thread 1).
				If not in main thread, it will damage the Auto Layout engine and may crash.
				Note: completion handler runs in sub-thread!
				So we need dispatch Alert Message Box to main thread.
			*/
			dispatch_async(dispatch_get_main_queue(), {[weak self]() -> Void in
				let strTitle = NSLocalizedString("Set-top Box Remote", comment: "app full name")
				let alert = UIAlertController(title: strTitle,
					message: error!.localizedDescription,
					preferredStyle:.Alert)
				let strOk = NSLocalizedString("OK", comment: "OK")
				alert.addAction(UIAlertAction(title: strOk, style: .Default, handler: nil))
				self!.presentViewController(alert, animated: true, completion:nil)
				
				// in the meantime make the iPhone vibrate
				AudioServicesPlayAlertSound(kSystemSoundID_Vibrate)
			})
		}
		task.resume()
	}
	
	//! monitor device's network traffic path
	func startMonitorNetwork() {
		if mReachabilityPtr != nil {
			let voidPtr = UnsafeMutablePointer<Void>(bridge(self))
			var context = SCNetworkReachabilityContext(version: 0,			// fixed value
			                                           info: voidPtr,	// user-specified data
			                                           retain: nil,			// These 3 callbacks
			                                           release: nil,		// aren't necessary
			                                           copyDescription: nil)// for me.
			if SCNetworkReachabilitySetCallback(mReachabilityPtr!,
			                                    ReachabilityCallback,	// callback when reachability changes
			                                    &context)
			{
				SCNetworkReachabilityScheduleWithRunLoop(mReachabilityPtr!,
				                                         CFRunLoopGetCurrent(),
				                                         kCFRunLoopDefaultMode);
			}
		}
	}
	
	//! never get a chance to be invoked. Just place here as a reference.
	func stopMonitorNetwork() {
		if mReachabilityPtr != nil {
			SCNetworkReachabilityUnscheduleFromRunLoop(mReachabilityPtr!,
			                                           CFRunLoopGetCurrent(),
			                                           kCFRunLoopDefaultMode);
		}
	}
	
	func parseReachabilityFlags(flags: SCNetworkReachabilityFlags) {
		if flags.contains(.Reachable) {
			mNetworkStatus = flags.contains(.IsWWAN) ? .NETWORK_THRU_WWAN : .NETWORK_THRU_WIFI
		} else {
			mNetworkStatus = .NETWORK_NOT_REACHABLE;
		}
	}
	
	//! synchronous check network status
	func getCurrentNetworkPath() {
		var zeroAddr = sockaddr()
		zeroAddr.sa_len = __uint8_t(sizeof(sockaddr))
		zeroAddr.sa_family = sa_family_t(AF_INET)
		
		if mReachabilityPtr == nil {
			mReachabilityPtr =  SCNetworkReachabilityCreateWithAddress(nil, &zeroAddr);
		}
		
		var flags = SCNetworkReachabilityFlags();
		SCNetworkReachabilityGetFlags(mReachabilityPtr!, &flags);
		parseReachabilityFlags(flags)
	}
	
	//! User Settings in "iPhone Settings" page
	//
	// === Important Points about Settings Bundle and Its Debug ===
	//
	// As long as you add a Settings.bundle to your project, it would show off
	// in iPhone Settings page definitely. If you open iPhone Settings page but
	// find nothing except a blank page, the reason might be:
	// 1. Root.plist has wrong-format setting, remove them one by one to check
	//    which one is wrong. If any one of them is of wrong format, the whole
	//    page becomes blank.
	// 2. If you want new Root.plist to take effect, you should relaunch iPhone
	//    Settings app to force it to read settings again.
	//
	// Once your settings can display completely in iPhone Settings page, it's
	// time to read them programmatically. If you cannot read any setting value
	// from NSUserDefaults, it's because your settings don't exist in UserDefault.
	// To make it created there, you should go to iPhone Settings page and make
	// some change.
	//
	func loadUserConfig() {
		let config = NSUserDefaults.standardUserDefaults()
		
		//! [1] Box IP address
		let ipAddr = config.stringForKey(KEY_BOX_IP_ADDRESS)
		if ipAddr != nil {
			if isValidIPv4Address(ipAddr!) && ipAddr != BoxIPAddress {
				BoxIPAddress = ipAddr!
			}
		}
		
		//! [2] Is double-tap / single-tap effective
		let isDoubleTap = config.boolForKey(KEY_DOUBLE_TAP_OK)
		let owned = self.view.gestureRecognizers
		let installed = (owned == nil ? false : owned!.contains(mTapGesture))
		if isDoubleTap != mIsDoubleTapOK || !installed {
			mIsDoubleTapOK = isDoubleTap
			mTapGesture.removeTarget(self, action: #selector(handleTap(_:)))
			mTapGesture.addTarget(self, action: #selector(handleTap(_:)))
			mTapGesture.numberOfTapsRequired = (isDoubleTap ? 2 : 1)
		}
		if !installed {
			self.view.addGestureRecognizer(mTapGesture)
		}
		
		//! You can suppress all network error message if you have faith in your Wifi.
		mIgnoreNetError = config.boolForKey(KEY_DISABLE_ERR_MSG)
	}
	
	func handleTap(gesture: UITapGestureRecognizer) {
		// disble tap when viewing weather info
		guard mScrollView == nil else {
			return
		}
		
		let pt = gesture.locationInView(self.view)
		if (pt.y > mGestureRectTop)
		{
			performAction(.ACTION_OK);
		}
	}
	
	//! tap and pan gesture recognizers cover whole area of UIView page. But upper
	//! screen is full of buttons. So we mannually ignore the UIButton area. You
	//! can find bypass code in func handleTap(_:).
	func detectGestureArea() {
		var positions = [CGFloat]()
		for i in self.view.subviews where i is UIButton {
			if i.tag == 0 {
				positions.append(i.frame.maxY)
			}
		}
		mGestureRectTop = positions.maxElement()!
	}
	
	func setupGestures() {
		// pinch open: volume up; pinch close: volume down
		let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
		self.view.addGestureRecognizer(pinch)
		
		// pan to up, down, left and right direction
		let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
		self.view.addGestureRecognizer(pan)
	}
	
	//! control volume
	// FIXME: how to debug this "pinch" behavior in simulator?
	func handlePinch(gesture: UIPinchGestureRecognizer) {
		// disble pinch when viewing weather info
		if mScrollView != nil {
			return
		}
		
		if gesture.state == .Ended {
			performAction(gesture.scale > 1.0 ? .ACTION_VOL_UP : .ACTION_VOL_DOWN)
		}
	}
	
	//! process pan gestures of UP, DOWN, LEFT and RIGHT.
	func handlePan(gesture: UIPanGestureRecognizer) {
		// disble pan when viewing weather info
		guard mScrollView == nil else {
			return
		}
		
		if gesture.state == .Began {
			mCurrDirection = .DIRECTION_INVALID
			mPrevDirection = .DIRECTION_INVALID
		} else if gesture.state == .Changed {
			let pt = gesture.translationInView(self.view)
			let xabs = abs(pt.x);
			let yabs = abs(pt.y);
			if (xabs > yabs)
			{
				mCurrDirection = pt.x > 0 ? .DIRECTION_RIGHT : .DIRECTION_LEFT
			}
			else if (xabs < yabs)
			{
				mCurrDirection = pt.y > 0 ? .DIRECTION_DOWN : .DIRECTION_UP;
			}
		
			if (mPrevDirection != mCurrDirection)
			{
				//! Firstly, respond to user's input
				performAction(mCurrDirection.toActionCode())
			
				/*
				Secondly, begin to monitor user's long press.
				If user keeps initial direction for more than 0.5 second, accelerate that input.
				If user releases finger within 0.5 second, below resetPanTimer will invalidate timer.
				*/
				resetPanTimer()
				mRepeatDelayer = NSTimer.scheduledTimerWithTimeInterval(0.5,
																		target: self,
																		selector: #selector(startRepeater),
																		userInfo: nil,
																		repeats: false) // no repeat: run-loop won't keep reference
				mPrevDirection = mCurrDirection;
			}
		} else if gesture.state == .Ended {
			mCurrDirection = .DIRECTION_INVALID
			mPrevDirection = .DIRECTION_INVALID
			resetPanTimer()
		}
	}
	
	//! release NSTimer resources, because they don't support re-schedule operation. So we have to
	//! make new ones when we need them again.
	func resetPanTimer() {
		mRepeatDelayer?.invalidate()
		mRepeatDelayer = nil
		mActionRepeater?.invalidate();
		mActionRepeater = nil
	}
	
	//! long-press will generate continuous Direction commands.
	func startRepeater() {
		mRepeatDelayer = nil;	// no repeat: run-loop won't keep reference. so no need to invalidate it
		mActionRepeater = NSTimer.scheduledTimerWithTimeInterval(0.2,
		                                                         target:self,
		                                                         selector:#selector(handleLongPress(_:)),
		                                                         userInfo:nil,
		                                                         repeats:true)
	}
	
	func handleLongPress(timer: NSTimer) {
		let code = mCurrDirection.toActionCode()
		if code != .ACTION_NULL {
			performAction(code)
		}
	}
	
	//! FIXME: below func actually has no chance to be called.
	func releaseBeforeExit() {
		mURLSession.invalidateAndCancel()
		stopMonitorNetwork()

		/*
		//! Document says: programmer is responsible for releasing it when no longer need it.
		//! Compiler says: Core Foundation object is memory-managed automatically.
		if mReachabilityPtr != nil {
			CFRelease(mReachabilityPtr)
		}
		*/
	}
	
	func createScrollLable()
	{
		let rect = self.view.frame  // .frame vs. .bounds (global vs. local)
		let padding: CGFloat = 5
		let x: CGFloat = padding, y: CGFloat = padding + mGestureRectTop
		let w = rect.width - 2 * padding
		let h = rect.height - y - mWeatherButton.frame.height - padding
		mScrollView = UIScrollView(frame: CGRect(x: x, y: y, width: w, height: h))
		//mScrollView?.backgroundColor = UIColor.blueColor() // debug
		//let font = UIFont.systemFontOfSize(14)
		mLblWeatherInfo = UILabel(frame: CGRect(x: 0, y: 0, width: w, height: h))
		//mLblWeatherInfo?.font = font
		mLblWeatherInfo?.textAlignment = .Left
		mLblWeatherInfo?.lineBreakMode = .ByWordWrapping
		mLblWeatherInfo?.numberOfLines = 0
		//mLblWeatherInfo?.backgroundColor = UIColor.blueColor() // debug
		//mScrollView?.contentSize = (mLblWeatherInfo?.frame.size)!
		mScrollView?.addSubview(mLblWeatherInfo!)
		self.view.addSubview(mScrollView!)
	}
}