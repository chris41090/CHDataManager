//
//  CHDataManager.swift
//  CHDataManager
//
//  Created by Christos Hadjikyriacos on 25/10/16.
//  Copyright © 2016 Christos Hadjikyriacos. All rights reserved.

import UIKit
import CoreData

typealias NetworkResponse = ((_ success:Bool,_ message:String,_ results:[NSDictionary],_ statuscCode:Int?,_ errorCode:String?)->Void)?
typealias CompletionHandler = ((_ success:Bool, _ message:String,_ statuscCode:Int?,_ errorCode:String?)->Void)?
typealias CompletionHandlerWithPaging = ((_ success:Bool, _ message:String,_ statuscCode:Int?,_ errorCode:String?,_ isLastPage:Bool)->Void)?
enum HTTPMethod:String {
    case POST = "POST"
    case GET = "GET"
    case PUT = "PUT"
    case PATCH = "PATCH"
    case DELETE = "DELETE"
}


class ErrorMessage {
    
    static let UKNOWNERROR = "Unknown error occurred"
    static let SUCCESSFUL = "Successful"
    
}


class CCPrint {
    
    class func printError(_ error:Error) {
        print(error)
    }
    
    class func printRequest(_ feed:String,statusCode:Int?) {
        print("Feed:" + feed + " Status Code:" + (statusCode?.description ?? "nil"))
    }
}


class DataManager {
    static let shared = DataManager()
    
    var requests = [URLSessionDataTask]()
    var requesting = false {
        didSet {
            UIApplication.shared.isNetworkActivityIndicatorVisible = requesting
        }
    }

    
    lazy internal var session:URLSession = {
        let configuration = URLSessionConfiguration.default
        configuration.requestCachePolicy = URLRequest.CachePolicy.reloadIgnoringLocalAndRemoteCacheData
        let session = URLSession(configuration: configuration)
        return session
    }()
    
    
    lazy var errorFlags = [String]() //Insert here your error flags.
    
    private func errorMessageFromDictionary(dictionary:NSDictionary?) -> String {
        guard  let dictionary = dictionary else {
            return ErrorMessage.UKNOWNERROR
        }
        
        
        
        for errorFlag in errorFlags {
            if let error = dictionary.value(forKey: errorFlag) as? String{
                
                return error
            }
            else if let error = (dictionary.value(forKey: errorFlag) as? [String])?.first{
                
                return error
            }
        }
        
        
        return ErrorMessage.UKNOWNERROR
        
    }
    
    fileprivate func manageResposnse(_ data:Data?, response:URLResponse?, error:Error?, completion:NetworkResponse) {
        
        var statusCode:Int? = nil
        var success = false
        let options = JSONSerialization.ReadingOptions(rawValue: 0)
        var results = [NSDictionary]()
        var errorMessage:String = ErrorMessage.UKNOWNERROR
        var errorCode:String?
        
        defer {
            
            requesting = false
            completion?(success,errorMessage ,results,statusCode,errorCode)
        }
        
        guard let data = data else {return}
        
        
        do {
            statusCode = (response as! HTTPURLResponse?)?.statusCode
            
            if statusCode == 500 || statusCode == 400 {
                print("----------------------------------------------------------")
                print(String(data: data, encoding: String.Encoding.utf8)!)
                print("----------------------------------------------------------")
            }
            
            
            if error != nil || (statusCode != 200 && statusCode != 201 && statusCode != 202 && statusCode != 204 && statusCode != 304){
                let dictionary = try JSONSerialization.jsonObject(with: data, options: options) as? NSDictionary
                
                errorMessage = errorMessageFromDictionary(dictionary: dictionary)
                
                if errorMessage == ErrorMessage.UKNOWNERROR {
                    //print(dictionary)
                }
                
                errorCode = dictionary?["error_code"] as? String
                
                
                success = false
            }
            else {
                
                if let array = try JSONSerialization.jsonObject(with: data, options: options) as? [NSDictionary]{
                    success = true
                    results = array
                    errorMessage = ErrorMessage.SUCCESSFUL
                    
                }
                else if let dictionary = try JSONSerialization.jsonObject(with: data, options: options) as? NSDictionary{
                    success = true
                    results.append(dictionary)
                    errorMessage = ErrorMessage.SUCCESSFUL
                }
                
            }
        }catch {
            
            CCPrint.printError(error)
            success = false
            return
            
        }
        
        
        
        
    }
    
    internal func fetchData(_ feed:String,token:String? = nil,parameters:[String:Any]? = nil,method:HTTPMethod = .GET, completion:NetworkResponse = nil){
        
        do {
            var statusCode:Int? = nil
            guard let url = URL(string: feed) else {
                completion?(false,"Couldn't connect to the server", [],statusCode,nil)
                return
            }
            
            var request = URLRequest(url: url)
            if let tk = token {
                let authValue = "Token \(tk)"
                request.setValue(authValue, forHTTPHeaderField: "Authorization")
            }
            if let parameters = parameters,
                let data = try JSONSerialization.data(withJSONObject: parameters, options:JSONSerialization.WritingOptions(rawValue: 0)) as Data? {
                request.httpBody = data
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.setValue("\(data.count)", forHTTPHeaderField: "Content-Length")
            }
            
            request.httpMethod = method.rawValue
            
            let task = session.dataTask(with: request, completionHandler: { (data, response, error) -> Void in
                statusCode = (response as? HTTPURLResponse)?.statusCode
                //CCPrint.printRequest(feed, statusCode: statusCode)
                self.manageResposnse(data, response: response, error: error, completion: completion)
                
            })
            
            requests.append(task)
            requesting = true
            task.resume()
            return
            
        }catch {
            CCPrint.printError(error)
            return
            
        }
    }
    
    internal func getPage(feed:String,token:String,firstTime:(()->Void)? = nil,parse:@escaping (([NSDictionary],Bool) -> Void),completion:CompletionHandlerWithPaging) {
        
        fetchData(feed, token: token, method: .GET) { (success, errorMessage, results, statusCode, errorCode) in
            var isLastPage = true
            
            if results.first?.value(forKey: "previous") as? String == nil,success {
                firstTime?()
                
            }
            
            
            
            parse((results.first?.value(forKey: "results") as? [NSDictionary]) ?? [],isLastPage)
            
            
            if let next = results.first?.value(forKey: "next") as? String {
                isLastPage = false
                self.getPage(feed: next, token: token,firstTime: firstTime,parse:parse, completion: completion)
            }
            
            
            completion?(success,errorMessage,statusCode,errorCode,isLastPage)

        }
        
    }
    
    
    
    
}


