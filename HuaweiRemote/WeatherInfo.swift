//
//  WeatherInfo.swift
//  HuaweiRemote
//
//  Created by jia xiaodong on 7/12/20.
//  Copyright © 2020 homemade. All rights reserved.
//

import Foundation

//! the raw value must match the ones in Settings.bundle.
enum LocationID: Int
{
	case Beijing_GuoFengMeiLun			= 0
	case Beijing_ZhongGuanCun			= 1
	case ShiJiaZhuang_WorkerHospital	= 2
	case QinHuangDao_LuLong				= 3
}

protocol WeatherServiceProvider {
	var result: String { get }

	/*
	@method launchQuery(_:completionHandler:)
	@abstract send request to service provider.
	@param location is the geographical site you're interested in.
	@param completion handler (callback) is invoked when getting a response.
	If error occurs, pass a localized error string as paramter to this handler.
	*/

	func launchQuery(location:LocationID, completionHandler: ((String?)->Void)?) -> Void
	
	// convert my location ID to codename service provider can understand.
	static func StringFromId(location: LocationID) -> String
}

class AirQualityIndex: WeatherServiceProvider
{
	private var mResult = ""
	var result: String {
		get { return mResult }
	}
	
	/*
	After analyzing aqicn.org by Web Developer Tools in Firefox, I got below 2 APIs:
	1> https://api.waqi.info/api/feed/@{city_id}/obs.en.json  : super detailed info
	2> https://api.waqi.info/api/feed/@{city_id}/now.json     : concise info
	the 2nd is fairly enough to fit my needs. I only need an AQI value, not its components.
	*/
	func launchQuery(location:LocationID, completionHandler:((String?)->Void)?) {
		mResult = ""
		let positionId = AirQualityIndex.StringFromId(location)
		let url = NSURL(string: "https://api.waqi.info/api/feed/@\(positionId)/now.json")
		// FIXME: if timeout isn't what I expected, use my own session instance
		let session = NSURLSession.sharedSession()
		let timeout = session.configuration.timeoutIntervalForResource
		debugPrint(timeout)
		let task = session.dataTaskWithURL(url!) {(data, response, error) in
			var errorMessage: String? = nil
			if let error = error {
				errorMessage = error.localizedDescription
			} else if let httpResponse = response as? NSHTTPURLResponse { // "as?" trys to downcast and return nil if fails.
				if httpResponse.statusCode != 200 {
					errorMessage = NSHTTPURLResponse.localizedStringForStatusCode(httpResponse.statusCode)
				} else if let data = data {
					self.parseResponse(data)
				}
			}
			
			// user callback may refresh UI, so put it to main thread
			if let handler = completionHandler {
				dispatch_async(dispatch_get_main_queue()) {() -> Void in
					handler(errorMessage)
				}
			}
		}
		task.resume()
	}
	
	//! The nearest air observation station
	static func StringFromId(location: LocationID) -> String {
		switch (location) {
		case .Beijing_ZhongGuanCun:			// Wanliu, Haidian (北京海淀万柳)
			return "452"
		case .Beijing_GuoFengMeiLun:		// BDA, Yizhuang (北京亦庄)
			return "460"
		case .ShiJiaZhuang_WorkerHospital:	// Worker Hospital (石家庄工人医院)
			return "644"
		case .QinHuangDao_LuLong:			// Lulong County (卢龙县城)
			return "5614"
		default:
			NSLog("[AirQualityIndex] Error: unidenfied location (%d)", location.rawValue)
			return ""
		}
	}
	
	private func parseResponse(response: NSData) -> Void
	{
		do {
			let info = try NSJSONSerialization.JSONObjectWithData(response, options: .MutableLeaves)
			guard var dict = info.objectForKey("rxs") else {
				return
			}
			guard dict.objectForKey("ver") as! String == "1" else {
				return
			}
			guard dict.objectForKey("status") as! String == "ok" else {
				return
			}
			let array = dict.objectForKey("obs") as! NSArray
			if array.count < 1 {
				return
			}
			dict = array[0] as! NSDictionary
			guard dict.objectForKey("status") as! String == "ok" else {
				return
			}
			dict = dict.objectForKey("msg") as! NSDictionary
			var aqi = dict.objectForKey("aqi") as! NSNumber?
			if aqi == nil {
				aqi = NSNumber(int: 0)
			}
			guard let site = dict.objectForKey("city")?.objectForKey("name") else {
				return
			}
			var dominentPollution = dict.objectForKey("dominentpol") as! String	// PM10? PM2.5?
			if dominentPollution.caseInsensitiveCompare("pm25") == .OrderedSame {
				dominentPollution = "pm2.5"
			}
			let time = dict.objectForKey("time") as! NSDictionary
			let timePoint = time.objectForKey("s") as! String
			let timeZone = time.objectForKey("tz") as! String
			let timeInfo = "\(timePoint), \(timeZone)"
			let strSite = NSLocalizedString("Site", comment: "geographical site")
			let strDominentPollution = NSLocalizedString("Dominent Pollution", comment: "main pollution source")
			mResult = "\(timeInfo)\n\(strSite): \(site)\nAQI: \(aqi!.intValue)\n\(strDominentPollution): \(dominentPollution)\n<from aqicn.org>\n"
		}
		catch {  // TODO: what exception will JSON throws?
			NSLog("[AirQualityIndex] Error: wrong JSON data")
		}
	}
}

struct WeatherOption: OptionSetType {
	var rawValue: UInt8
	
	static let WEATHER_NOW				= WeatherOption(rawValue: 1) // today's weather
	static let WEATHER_FORECAST			= WeatherOption(rawValue: 2) // weather forecast for several days of future
	static let WEATHER_DETAIL_FORECAST	= WeatherOption(rawValue: 4) // detailed forecast (for today only, hourly forecast)
	static let WEATHER_ALARM			= WeatherOption(rawValue: 8) // not implemented
}

protocol DetailedWeatherInfo : WeatherServiceProvider
{
	var options: WeatherOption { get set }
}

/**
Registered as a free user by an email address, you can get 3000 queries per day.
Personal key: http://console.heweather.com/my/service
Docs: http://docs.heweather.com/224291
City list: http://docs.heweather.com/224293
*/
class HeWeatherInfoNode
{
	var date: String = ""
	var astro: String = ""            // rise/set time of sun and moon
	var condition: String = ""        // sunny, cloudy, rainny, ...
	var temperature: String = ""      // Celsius degree
	var humidity: String  = ""        // relative humidity (%)
	var probability: String  = ""     // probability of precipitation
	var precipitation: String  = ""   // amount of precipitation (mm)
	var pressure: String  = ""        // atmospheric pressure (mmHg)
	var uv: String       = ""         // ultraviolet-ray radiation degree
	var visibility: String  = ""      // km
	var wind: String     = ""         // wind
	
	init(withJson data: NSDictionary) {
		//date
		if let date = data.objectForKey("date") {
			self.date = date as! String
		} else {
			let now = NSDate()
			let formatter = NSDateFormatter() // default: current locale
			formatter.dateStyle = .MediumStyle
			formatter.timeStyle = .MediumStyle
			// FIXME: some parts are not working
			//formatter.setLocalizedDateFormatFromTemplate("yyyy-MM-dd HH:mm")
			self.date = formatter.stringFromDate(now)
		}
		
		// astronomy (the periods of sun and moon)
		if let dict = data.objectForKey("astro") as? NSDictionary {
			let sunrise = dict.objectForKey("sr") as? String
			let sunset = dict.objectForKey("ss") as? String
			let moonrise = dict.objectForKey("mr") as? String
			let moonset = dict.objectForKey("ms") as? String
			if sunrise != nil && sunset != nil && moonrise != nil && moonset != nil {
				self.astro = "日出日落: \(sunrise!) - \(sunset!)\n月出月落: \(moonrise!) - \(moonset!)"
			}
		}
		
		// sky condition: shiny, cloudy, rainy, ...
		if let dict = data.objectForKey("cond") {
			if let value = dict.objectForKey("txt") {
				self.condition = value as! String
			} else {
				let day = dict.objectForKey("txt_d") as? String
				let night = dict.objectForKey("txt_n") as? String
				if day != nil && night != nil {
					self.condition = "白天\(day!),夜间\(night!)"
				}
			}
		}
		
		// temperature
		if var value = data.objectForKey("tmp") {
			if value is NSDictionary {
				let dict = value as! NSDictionary
				let min = dict.objectForKey("min") as? String
				let max = dict.objectForKey("max") as? String
				value = "\(min!)~\(max!)"
			}
			var desc = "温度: \(value as! String)"
			if let value = data.objectForKey("fl") {
				desc += "; 体感温度: \(value as! String)"
			}
			self.temperature = desc
		}
		
		// humidity
		if let value = data.objectForKey("hum") {
			self.humidity = "相对湿度: \(value as! String)%"
		}
		
		// precipitation probability
		if let value = data.objectForKey("pop") {
			let p = value.floatValue
			if p > 0 {
				self.probability = "降水概率: \(p)%"
			}
		}
		
		// precipitation amount
		if let value = data.objectForKey("pcpn") {
			let p = value.floatValue
			if p > 0 {
				self.precipitation = "降水量: \(p)mm"
			}
		}
		
		// atmospheric pressure
		if let value = data.objectForKey("pres") {
			self.pressure = "大气压: \(value)mmHg"
		}
		
		// ultra-violet index
		if let value = data.objectForKey("uv") {
			self.uv = "紫外线指数: \(value)"
		}
		
		// visibility
		if let value = data.objectForKey("vis") {
			self.visibility = "能见度: \(value)km"
		}
		
		// wind
		if let dict = data.objectForKey("wind") {
			let dir = dict.objectForKey("dir")
			let lvl = dict.objectForKey("sc")
			let spd = dict.objectForKey("spd")
			self.wind = "\(dir as! String)\(lvl as! String)级, \(spd as! String)km/h"
		}
	}
	
	var description: String {
		var desc = "---------------------\n\(date)"
		if !condition.isEmpty {
			desc.appendContentsOf("\n\(condition)")
		}
		if !astro.isEmpty {
			desc.appendContentsOf("\n\(astro)")
		}
		if !temperature.isEmpty {
			desc.appendContentsOf("\n\(temperature)")
		}
		if !humidity.isEmpty {
			desc.appendContentsOf("\n\(humidity)")
		}
		if !probability.isEmpty {
			desc.appendContentsOf("\n\(probability)")
		}
		if !precipitation.isEmpty {
			desc.appendContentsOf("\n\(precipitation)")
		}
		if !pressure.isEmpty {
			desc.appendContentsOf("\n\(pressure)")
		}
		if !uv.isEmpty {
			desc.appendContentsOf("\n\(uv)")
		}
		if !visibility.isEmpty {
			desc.appendContentsOf("\n\(visibility)")
		}
		if !wind.isEmpty {
			desc.appendContentsOf("\n\(wind)")
		}
		return desc
	}
}

class HeWeather: DetailedWeatherInfo
{
	var mAqi: String?
	var mNow: HeWeatherInfoNode?
	var mForecast: [HeWeatherInfoNode]?
	var mDetailedForecast: [HeWeatherInfoNode]?
	
	private var mOptions: WeatherOption = WeatherOption(rawValue: 0)
	var options: WeatherOption {
		get { return mOptions }
		set { mOptions = newValue}
	}
	
	var result: String {
		var result = ""
		if let now = mNow {
			result += "\(now.description)\n"
		}
		if let aqi = mAqi {
			result += "\(aqi)\n"
		}
		mForecast?.forEach() {(node) -> Void in
			result += "\(node.description)\n"
		}
		mDetailedForecast?.forEach() {(node) in
			result += "\(node.description)\n"
		}
		return result;
	}
	
	//! The nearest observated site
	static func StringFromId(loc:LocationID) -> String
	{
		switch (loc) {
		case .Beijing_GuoFengMeiLun:
			return "CN101010600"	// Tongzhou, Beijing (北京通州)
		case .Beijing_ZhongGuanCun:
			return "CN101010200"	// Haidian, Beijing (北京海淀)
		case .ShiJiaZhuang_WorkerHospital:
			return "CN101090101"	// Shijiazhuang City (石家庄)
		case .QinHuangDao_LuLong:
			return "CN101091105"	// Lulong County, Qinhuangdao City (卢龙县)
		default:
			NSLog("[HeWeather] Error: unidentified location (%d)", loc.rawValue)
			return "CN101010100"	// beijing (北京市)
		}
	}
	
	func launchQuery(location:LocationID, completionHandler:((String?)->Void)?) {
		mAqi = nil
		mNow = nil
		mForecast = nil
		mDetailedForecast = nil
		
		let site = HeWeather.StringFromId(location)
		let url = NSURL(string: "https://free-api.heweather.com/v5/weather?key=2dae4ca04d074a1abde0c113c3292ae1&city=\(site)")
		let task = NSURLSession.sharedSession().dataTaskWithURL(url!) {(data, response, error) in
			var errorMessage: String? = nil
			if let error = error {
				errorMessage = "\(error.localizedDescription)\n"
			} else if let response = response as? NSHTTPURLResponse { // if downcast fails, "as?" returns nil.
				if response.statusCode != 200 {
					errorMessage = "\(NSHTTPURLResponse.localizedStringForStatusCode(response.statusCode))\n"
				} else if let data = data {
					self.parseResponse(data)
				}
			}
			
			// user callback may refresh UI, so put it to main thread
			if let handler = completionHandler {
				dispatch_async(dispatch_get_main_queue()) {() -> Void in
					handler(errorMessage)
				}
			}
		}
		task.resume()
	}

	func parseResponse(response:NSData) {
		do {
			// [debug] can't see full values of a JSON object in Xcode debugger.
			/*
			if let jsonStr = NSString(bytes: response.bytes,
			                      length: response.length,
			                      encoding: NSUTF8StringEncoding)
			{
				debugPrint(jsonStr)
			}
			*/
			
			let info = try NSJSONSerialization.JSONObjectWithData(response, options: .MutableLeaves)
			guard let array = info.objectForKey("HeWeather5") else {
				return
			}
			guard array.count > 0 else {
				return
			}
			let node = array[0] as! NSDictionary // only 1 node available
			guard node["status"] as? String == "ok" else {
				return
			}
			if let aqi = node["aqi"] {
				if let city = aqi["city"] {
					parseAqi(city as! NSDictionary)
				}
			}
			if let now = node["now"] {
				parseNowInfo(now as! NSDictionary)
			}
			if self.options.contains(.WEATHER_FORECAST) {
				let forecast = node["daily_forecast"] as? NSArray
				if let forecast = forecast {
					parseDailyForecast(forecast)
				}
			}
			if self.options.contains(.WEATHER_DETAIL_FORECAST) {
				let forecast = node["hourly_forecast"] as? NSArray
				if let forecast = forecast {
					parseDetailedForecast(forecast)
				}
			}
		} catch {
			NSLog("[HeWeather] Error: wrong JSON data")
		}
	}
	
	func parseAqi(info:NSDictionary) {
		let aqi = info.objectForKey("aqi");
		let pm10 = info.objectForKey("pm10");
		let pm25 = info.objectForKey("pm25");
		let qly = info.objectForKey("qlty");
		mAqi = "AQI:\(aqi as! String) (PM10:\(pm10 as! String), PM2.5:\(pm25 as! String)) \(qly as! String)"
	}
	
	func parseNowInfo(now:NSDictionary) {
		mNow = HeWeatherInfoNode(withJson: now)
	}
	
	func parseDailyForecast(forecast:NSArray) {
		var array = [HeWeatherInfoNode]()
		forecast.enumerateObjectsUsingBlock() {(dict, index, stop) -> Void in
			let node = HeWeatherInfoNode(withJson: dict as! NSDictionary)
			array.insert(node, atIndex: index)
		}
		mForecast = array
	}
	
	func parseDetailedForecast(forecast:NSArray) {
		var array = [HeWeatherInfoNode]()
		forecast.enumerateObjectsUsingBlock() {(dict, index, stop) -> Void in
			let node = HeWeatherInfoNode(withJson: dict as! NSDictionary)
			array.insert(node, atIndex: index)
		}
		mDetailedForecast = array
	}
}

class WeatherFullReport {
	var mAQI: AirQualityIndex = AirQualityIndex()
	var mWeatherProvider: DetailedWeatherInfo = HeWeather()
	
	var ItemAir: AirQualityIndex {
		return mAQI
	}
	var ItemOther: DetailedWeatherInfo {
		get { return mWeatherProvider }
		set { mWeatherProvider = newValue }
	}
	
	func query(location:LocationID, AqiCompletionHandler:((String)->Void)?, WeatherCompletionHandler:((String)->Void)?) {
		mAQI.launchQuery(location) {(errorMessage) -> Void in
			if let handler = AqiCompletionHandler {
				dispatch_async(dispatch_get_main_queue()) {()->Void in
					handler(errorMessage == nil ? self.ItemAir.result : errorMessage!)
				}
			}
		}

		mWeatherProvider.launchQuery(location) {(errorMessage) -> Void in
			if let handler = WeatherCompletionHandler {
				dispatch_async(dispatch_get_main_queue()) {()->Void in
					handler(errorMessage == nil ? self.ItemOther.result : errorMessage!)
				}
			}
		}
	}
}