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
        let positionId = AirQualityIndex.StringFromId(location:location)
		let url = URL(string: "https://api.waqi.info/api/feed/@\(positionId)/now.json")
		let session = URLSession.shared
        let task = session.dataTask(with:url!) {(data, response, error) in
			var errorMessage: String? = nil
			if let error = error {
				errorMessage = error.localizedDescription
			} else if let httpResponse = response as? HTTPURLResponse { // "as?" trys to downcast and return nil if fails.
				if httpResponse.statusCode != 200 {
					errorMessage = HTTPURLResponse.localizedString(forStatusCode:httpResponse.statusCode)
				} else if let data = data {
                    self.parseResponse(response:data)
				}
			}
			
			// user callback may refresh UI, so put it to main thread
			if let handler = completionHandler {
                DispatchQueue.main.async {
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
	
	private func parseResponse(response: Data) -> Void
	{
		do {
            let info = try JSONSerialization.jsonObject(with:response, options: .mutableLeaves) as! [String: Any]
            guard var dict = info["rxs"] as? [String: Any] else {
				return
			}
			guard dict["ver"] as! String == "1" else {
				return
			}
			guard dict["status"] as! String == "ok" else {
				return
			}
			let array = dict["obs"] as! NSArray
			if array.count < 1 {
				return
			}
			dict = array[0] as! [String: Any]
			guard dict["status"] as! String == "ok" else {
				return
			}
			dict = dict["msg"] as! [String: Any]
			var aqi = dict["aqi"] as! Int?
			if aqi == nil {
				aqi = Int(0)
			}
            let cityInfo = dict["city"] as? [String: Any]
			guard let site = cityInfo?["name"] else {
				return
			}
			var dominentPollution = dict["dominentpol"] as! String	// PM10? PM2.5?
			if dominentPollution.caseInsensitiveCompare("pm25") == .orderedSame {
				dominentPollution = "pm2.5"
			}
            let time = dict["time"] as! [String: Any]
			let timePoint = time["s"] as! String
			let timeZone = time["tz"] as! String
			let timeInfo = "\(timePoint), \(timeZone)"
			let strSite = NSLocalizedString("Site", comment: "geographical site")
			let strDominentPollution = NSLocalizedString("Dominent Pollution", comment: "main pollution source")
			mResult = "\(timeInfo)\n\(strSite): \(site)\nAQI: \(aqi)\n\(strDominentPollution): \(dominentPollution)\n<from aqicn.org>\n"
		}
		catch {  // TODO: what exception will JSON throws?
			NSLog("[AirQualityIndex] Error: wrong JSON data")
		}
	}
}

struct WeatherOption: OptionSet {
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
		if let date = data.object(forKey:"date") {
			self.date = date as! String
		} else {
			let now = Date()
			let formatter = DateFormatter() // default: current locale
			formatter.dateStyle = .medium
			formatter.timeStyle = .medium
			// FIXME: some parts are not working
			//formatter.setLocalizedDateFormatFromTemplate("yyyy-MM-dd HH:mm")
            self.date = formatter.string(from:now)
		}
		
		// astronomy (the periods of sun and moon)
		if let dict = data.object(forKey:"astro") as? NSDictionary {
			let sunrise = dict["sr"] as? String
			let sunset = dict["ss"] as? String
			let moonrise = dict["mr"] as? String
			let moonset = dict["ms"] as? String
			if sunrise != nil && sunset != nil && moonrise != nil && moonset != nil {
				self.astro = "日出日落: \(sunrise!) - \(sunset!)\n月出月落: \(moonrise!) - \(moonset!)"
			}
		}
		
		// sky condition: shiny, cloudy, rainy, ...
		if let dict = data.object(forKey:"cond") as? NSDictionary {
			if let value = dict["txt"] as? String {
				self.condition = value
			} else {
				let day = dict["txt_d"] as? String
				let night = dict["txt_n"] as? String
				if day != nil && night != nil {
					self.condition = "白天\(day!),夜间\(night!)"
				}
			}
		}
		
		// temperature
		if var value = data.object(forKey:"tmp") {
			if value is NSDictionary {
				let dict = value as! NSDictionary
				let min = dict["min"] as? String
				let max = dict["max"] as? String
				value = "\(min!)~\(max!)"
			}
			var desc = "温度: \(value as! String)"
			if let value = data.object(forKey:"fl") {
				desc += "; 体感温度: \(value as! String)"
			}
			self.temperature = desc
		}
		
		// humidity
		if let value = data.object(forKey:"hum") {
			self.humidity = "相对湿度: \(value as! String)%"
		}
		
		// precipitation probability
		if let value = data.object(forKey:"pop") as? Float {
			if value > 0 {
				self.probability = "降水概率: \(value)%"
			}
		}
		
		// precipitation amount
		if let value = data.object(forKey:"pcpn") as? Int {
			if value > 0 {
				self.precipitation = "降水量: \(value)mm"
			}
		}
		
		// atmospheric pressure
		if let value = data.object(forKey:"pres") {
			self.pressure = "大气压: \(value)mmHg"
		}
		
		// ultra-violet index
		if let value = data.object(forKey:"uv") {
			self.uv = "紫外线指数: \(value)"
		}
		
		// visibility
		if let value = data.object(forKey:"vis") {
			self.visibility = "能见度: \(value)km"
		}
		
		// wind
		if let dict = data.object(forKey:"wind") as? NSDictionary {
			let dir = dict["dir"]
			let lvl = dict["sc"]
			let spd = dict["spd"]
			self.wind = "\(dir as! String)\(lvl as! String)级, \(spd as! String)km/h"
		}
	}
	
	var description: String {
		var desc = "---------------------\n\(date)"
		if !condition.isEmpty {
            desc.append(contentsOf:"\n\(condition)")
		}
		if !astro.isEmpty {
			desc.append(contentsOf:"\n\(astro)")
		}
		if !temperature.isEmpty {
			desc.append(contentsOf:"\n\(temperature)")
		}
		if !humidity.isEmpty {
			desc.append(contentsOf:"\n\(humidity)")
		}
		if !probability.isEmpty {
			desc.append(contentsOf:"\n\(probability)")
		}
		if !precipitation.isEmpty {
			desc.append(contentsOf:"\n\(precipitation)")
		}
		if !pressure.isEmpty {
			desc.append(contentsOf:"\n\(pressure)")
		}
		if !uv.isEmpty {
			desc.append(contentsOf:"\n\(uv)")
		}
		if !visibility.isEmpty {
			desc.append(contentsOf:"\n\(visibility)")
		}
		if !wind.isEmpty {
			desc.append(contentsOf:"\n\(wind)")
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
	static func StringFromId(location:LocationID) -> String
	{
		switch (location) {
		case .Beijing_GuoFengMeiLun:
			return "CN101010600"	// Tongzhou, Beijing (北京通州)
		case .Beijing_ZhongGuanCun:
			return "CN101010200"	// Haidian, Beijing (北京海淀)
		case .ShiJiaZhuang_WorkerHospital:
			return "CN101090101"	// Shijiazhuang City (石家庄)
		case .QinHuangDao_LuLong:
			return "CN101091105"	// Lulong County, Qinhuangdao City (卢龙县)
		default:
			NSLog("[HeWeather] Error: unidentified location (%d)", location.rawValue)
			return "CN101010100"	// beijing (北京市)
		}
	}
	
	func launchQuery(location:LocationID, completionHandler:((String?)->Void)?) {
		mAqi = nil
		mNow = nil
		mForecast = nil
		mDetailedForecast = nil
		
        let site = HeWeather.StringFromId(location:location)
		let url = URL(string: "https://free-api.heweather.com/v5/weather?key=2dae4ca04d074a1abde0c113c3292ae1&city=\(site)")
        let task = URLSession.shared.dataTask(with:url!) {data, response, error in
			var errorMessage: String? = nil
			if let error = error {
				errorMessage = "\(error.localizedDescription)\n"
			} else if let response = response as? HTTPURLResponse { // if downcast fails, "as?" returns nil.
				if response.statusCode != 200 {
					errorMessage = "\(HTTPURLResponse.localizedString(forStatusCode:response.statusCode))\n"
				} else if let data = data {
                    self.parseResponse(response:data)
				}
			}
			
			// user callback may refresh UI, so put it to main thread
			if let handler = completionHandler {
                DispatchQueue.main.async {
                    handler(errorMessage)
                }
			}
        }
		task.resume()
	}

	func parseResponse(response:Data) {
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
            let info = try JSONSerialization.jsonObject(with:response, options: .mutableLeaves) as? [String: Any]
			guard let array = info?["HeWeather5"] as? NSArray else {
				return
			}
			guard array.count > 0 else {
				return
			}
			let node = array[0] as! NSDictionary // only 1 node available
			guard node["status"] as? String == "ok" else {
				return
			}
            if let aqi = node["aqi"] as? [String: Any]{
				if let city = aqi["city"] as? NSDictionary {
                    parseAqi(info:city)
				}
			}
			if let now = node["now"] as? NSDictionary {
                parseNowInfo(now:now)
			}
			if self.options.contains(.WEATHER_FORECAST) {
				let forecast = node["daily_forecast"] as? NSArray
				if let forecast = forecast {
                    parseDailyForecast(forecast:forecast)
				}
			}
			if self.options.contains(.WEATHER_DETAIL_FORECAST) {
				let forecast = node["hourly_forecast"] as? NSArray
				if let forecast = forecast {
                    parseDetailedForecast(forecast:forecast)
				}
			}
		} catch {
			NSLog("[HeWeather] Error: wrong JSON data")
		}
	}
	
	func parseAqi(info:NSDictionary) {
		let aqi = info.object(forKey:"aqi");
		let pm10 = info.object(forKey:"pm10");
		let pm25 = info.object(forKey:"pm25");
		let qly = info.object(forKey:"qlty");
		mAqi = "AQI:\(aqi as! String) (PM10:\(pm10 as! String), PM2.5:\(pm25 as! String)) \(qly as! String)"
	}
	
	func parseNowInfo(now:NSDictionary) {
		mNow = HeWeatherInfoNode(withJson: now)
	}
	
	func parseDailyForecast(forecast:NSArray) {
		var array = [HeWeatherInfoNode]()
		forecast.enumerateObjects() {(dict, index, stop) -> Void in
			let node = HeWeatherInfoNode(withJson: dict as! NSDictionary)
			array.insert(node, at: index)
		}
		mForecast = array
	}
	
	func parseDetailedForecast(forecast:NSArray) {
		var array = [HeWeatherInfoNode]()
		forecast.enumerateObjects() {(dict, index, stop) -> Void in
			let node = HeWeatherInfoNode(withJson: dict as! NSDictionary)
            array.insert(node, at: index)
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
        mAQI.launchQuery(location:location) {(errorMessage) -> Void in
			if let handler = AqiCompletionHandler {
                DispatchQueue.main.async {
                    handler(errorMessage == nil ? self.ItemAir.result : errorMessage!)
                }
			}
		}

        mWeatherProvider.launchQuery(location:location) {(errorMessage) -> Void in
			if let handler = WeatherCompletionHandler {
                DispatchQueue.main.async {
                    handler(errorMessage == nil ? self.ItemOther.result : errorMessage!)
                }
			}
		}
	}
}
