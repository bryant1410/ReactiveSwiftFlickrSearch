//
//  FlickrSearchImpl.swift
//  ReactiveSwiftFlickrSearch
//
//  Created by Colin Eberhardt on 14/07/2014.
//  Copyright (c) 2014 Colin Eberhardt. All rights reserved.
//

import Foundation

class FlickrSearchImpl : NSObject, FlickrSearch, OFFlickrAPIRequestDelegate {
  
  //MARK: Properties
  
  private let requests: NSMutableSet
  private let flickrContext: OFFlickrAPIContext
  private var flickrRequest: OFFlickrAPIRequest?
  
  //MARK: Public API
  
  init() {
    let flickrAPIKey = "9d1bdbde083bc30ebe168a64aac50be5";
    let flickrAPISharedSecret = "5fbfa610234c6c23";
    flickrContext = OFFlickrAPIContext(APIKey: flickrAPIKey, sharedSecret:flickrAPISharedSecret)
    
    requests = NSMutableSet()
    
    flickrRequest = nil
  }
  
  func flickrSearchSignal(searchString: String) -> RACSignal {
    
    func photosFromDictionary (response: NSDictionary) -> FlickrSearchResults {
      let photoArray = response.valueForKeyPath("photos.photo") as [[String: String]]
      let photos = photoArray.map {
        (photoDict: [String:String]) -> FlickrPhoto in
        let url = self.flickrContext.photoSourceURLFromDictionary(photoDict, size: OFFlickrSmallSize)
        return FlickrPhoto(title: photoDict["title"]!, url: url, identifier: photoDict["id"]!)
      }
      let total = response.valueForKeyPath("photos.total").integerValue
      return FlickrSearchResults(searchString: searchString, totalResults: total, photos: photos)
    }
    
    return signalFromAPIMethod("flickr.photos.search",
      arguments: ["text" : searchString, "sort": "interestingness-desc"],
      transform: photosFromDictionary);
  }
  
  func flickrImageMetadata(photoId: String) -> RACSignal {
    
    let favouritesSignal = signalFromAPIMethod("flickr.photos.getFavorites",
      arguments: ["photo_id": photoId]) {
        // String is not AnyObject?
        (response: NSDictionary) -> NSString in
        return response.valueForKeyPath("photo.total") as NSString
      }
  
    let commentsSignal = signalFromAPIMethod("flickr.photos.getInfo",
      arguments: ["photo_id": photoId]) {
        (response: NSDictionary) -> NSString in
        return response.valueForKeyPath("photo.comments._text") as NSString
    }
    
    return RACSignalEx.combineLatestAs([favouritesSignal, commentsSignal]) {
      (favourites:NSString, comments:NSString) -> FlickrPhotoMetadata in
      return FlickrPhotoMetadata(favourites: favourites.integerValue, comments: comments.integerValue)
    }
  }
  
  //MARK: Private
  
  private func signalFromAPIMethod<T: AnyObject>(method: String, arguments: [String:String],
    transform: (NSDictionary) -> T) -> RACSignal {
      
      return RACSignal.createSignal({
        (subscriber: RACSubscriber!) -> RACDisposable! in
        
        let flickrRequest = OFFlickrAPIRequest(APIContext: self.flickrContext);
        flickrRequest.delegate = self;
        self.requests.addObject(flickrRequest)
        
        let sucessSignal = self.rac_signalForSelector(Selector("flickrAPIRequest:didCompleteWithResponse:"),
          fromProtocol: OFFlickrAPIRequestDelegate.self)
        
        sucessSignal.filterAs { (tuple: RACTuple) -> Bool in tuple.first as NSObject == flickrRequest }
          .mapAs { (tuple: RACTuple) -> AnyObject in tuple.second }
          .mapAs(transform)
          .subscribeNext {
            (next: AnyObject!) -> () in
            subscriber.sendNext(next)
            subscriber.sendCompleted()
        }
        
        
        let failSignal = self.rac_signalForSelector(Selector("flickrAPIRequest:didFailWithError:"),
          fromProtocol: OFFlickrAPIRequestDelegate.self)
        
        failSignal.mapAs { (tuple: RACTuple) -> AnyObject in tuple.second }
          .subscribeNextAs {
            (error: NSError) -> () in
            println("error: \(error)")
            subscriber.sendError(error)
        }
        
        flickrRequest.callAPIMethodWithGET(method, arguments: arguments)
        
        return RACDisposable(block: {
          self.requests.removeObject(flickrRequest)
          })
        })
      
  }



}