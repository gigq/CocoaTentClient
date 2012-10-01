//
//  CocoaTent.m
//  TentClient
//
//  Created by Dustin Rue on 9/23/12.
//  Copyright (c) 2012 Dustin Rue. All rights reserved.
//
// References:
//   HTTP Mac
//   http://tools.ietf.org/html/draft-ietf-oauth-v2-http-mac-01#section-3.1

/*
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 * THE SOFTWARE.
 */

#import "CocoaTent.h"
#import "CocoaTentApp.h"
#import "AFJSONRequestOperation.h"
#import "AFHTTPClient.h"
#import "JSONKit.h"
#import "NSData+hmac_sha_256.h"
#import "NSString+hmac_sha_256.h"
#import "NSString+ParseQueryString.h"
#import "NSString+Random.h"


@interface CocoaTent (Private)

- (void) saveResponseDataAndRedirectToAuthorizationURL:(id) data;
- (void) saveAuthorizationCodeFromAuthorizationURL:(NSURL *) callBackData;
- (void) getPermanentAccessToken;
- (void) savePermanentAccessToken:(id) JSON;

@end


@implementation CocoaTent

- (id) initWithApp:(CocoaTentApp *) cocoaTentApp {
    self = [super init];
    
    if (!self)
        return self;
    
    
    
    /*
     self.tentVersion      = @"0.1.0";
     self.tentHostProtocol = @"https";
     self.tentHost         = @"gigq.tent.is";
     self.tentHostPort     = @"443";
     self.tentRoot         = @"/tent";
     self.tentMimeType     = @"application/vnd.tent.v0+json";
     self.urlScheme        = @"cocoatentclient";
     */
    
    self.cocoaTentApp = cocoaTentApp;
    
    self.cocoaTentCommunication = [CocoaTentCommunication sharedInstance];
    
    NSURL *hostInfo = [NSURL URLWithString:self.cocoaTentApp.tentHostURL];
    
    [self.cocoaTentCommunication setTentHost:[hostInfo host]];
    [self.cocoaTentCommunication setTentHostPort:[[hostInfo port] stringValue]];
    [self.cocoaTentCommunication setTentHostProtocol:[hostInfo scheme]];
    [self.cocoaTentCommunication setMac_key:self.cocoaTentApp.mac_key];
    [self.cocoaTentCommunication setMac_key_id:self.cocoaTentApp.mac_key_id];
    
    [self.cocoaTentApp addObserver:self forKeyPath:@"name"          options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"description"   options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"url"           options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"icon"          options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"redirect_uris" options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"scopes"        options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"app_id"        options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"mac_agorithm"  options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"mac_key"       options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"mac_key_id"    options:NSKeyValueObservingOptionNew context:nil];
    [self.cocoaTentApp addObserver:self forKeyPath:@"access_token"  options:NSKeyValueObservingOptionNew context:nil];
    
    [self registerForURLScheme];
    
    return self;
}

- (void)registerForURLScheme
{
    [[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(getUrl:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

- (void)getUrl:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {
    NSURL *url = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]]; // Now you can parse the URL and perform whatever action is needed
    
    [self saveAuthorizationCodeFromAuthorizationURL:url];
}








#pragma mark -
#pragma mark OAuth2 registration steps
/*
 * STEP 1: Tell tentd that we exist and it'll respond with:
 *   an id for our app (id)
 *   the id for our key (mac_key_id)
 *   the shared key (mac_key)
 *   the algorithm used (mac_algorithm)
 */
- (void) registerWithTentServer {
    
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"POST" pathWithLeadingSlash:@"/apps" HTTPBody:[self.cocoaTentApp dictionary] sign:NO success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [self saveResponseDataAndRedirectToAuthorizationURL:JSON];
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"receiveDataFailure" object:nil];
        NSLog(@"failure, %@ \n\nwith request %@", error, [request allHTTPHeaderFields]);
    }];
    
    [operation start];
}

/*
 * STEP 2
 * Take the data from doRegister and store it then perform auth request
 */
- (void) saveResponseDataAndRedirectToAuthorizationURL:(NSDictionary *) data {
    [self.cocoaTentCommunication setMac_algorithm:[data valueForKey:@"mac_algorithm"]];
    [self.cocoaTentCommunication setMac_key:[data valueForKey:@"mac_key"]];
    [self.cocoaTentCommunication setMac_key_id:[data valueForKey:@"mac_key_id"]];
    [self.cocoaTentApp setApp_id:[data valueForKey:@"id"]];
    
    [self.cocoaTentCommunication setState:[NSString randomizedString]];
    
    NSString *params = [NSString stringWithFormat:@"client_id=%@&tent_profile_info_types=%@&tent_post_types=%@&redirect_uri=cocoatentclient://oauth&state=%@&scope=%@",
                        [self.cocoaTentApp app_id],
                        [[self.cocoaTentApp.tent_profile_info_types allKeys] componentsJoinedByString:@","],
                        [[self.cocoaTentApp.tent_post_types allKeys] componentsJoinedByString:@","],
                        self.cocoaTentCommunication.state,
                        [[self.cocoaTentApp.scopes allKeys] componentsJoinedByString:@","]];
    
    NSString *fullParams = [NSString stringWithFormat:@"%@://%@:%@%@/%@?%@", self.cocoaTentCommunication.tentHostProtocol, self.cocoaTentCommunication.tentHost, self.cocoaTentCommunication.tentHostPort, self.cocoaTentCommunication.tentRoot, @"/oauth/authorize", params];
    
    NSURL *url = [NSURL URLWithString:fullParams];
    
	[[NSWorkspace sharedWorkspace] openURL:url];
}


/*
 * Store the code and state
 */
- (void) saveAuthorizationCodeFromAuthorizationURL:(NSURL *) callBackData
{
    NSDictionary *data = [[callBackData query] explodeToDictionaryInnerGlue:@"=" outterGlue:@"&"];
    
    self.cocoaTentCommunication.code = [data valueForKey:@"code"];
    if ([self.cocoaTentCommunication.state isEqualToString:[data valueForKey:@"state"]])
        [self getPermanentAccessToken];
    
    // we just don't do anything if the state values aren't the same
}

/**
 * STEP 3: get our permanent access token using the code we just got
 * Builds the URL/request to exchange a code for an access token
 */
- (void) getPermanentAccessToken
{
    
    NSDictionary *httpBody = [NSDictionary dictionaryWithObjectsAndKeys:self.cocoaTentCommunication.code, @"code", @"mac", @"token_type", nil];
    
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"POST" pathWithLeadingSlash:[NSString stringWithFormat:@"/apps/%@/authorizations", [self.cocoaTentApp app_id]] HTTPBody:httpBody sign:YES success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [self savePermanentAccessToken:JSON];
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"receiveDataFailure" object:nil];
        NSLog(@"failure, %@ \n\nwith request %@", error, [request allHTTPHeaderFields]);
    }];
    
    [operation start];
}

- (void) savePermanentAccessToken:(id) JSON
{
    [self.cocoaTentCommunication setAccess_token:[JSON valueForKey:@"access_token"]];
    [self.cocoaTentCommunication setMac_key:[JSON valueForKey:@"mac_key"]];
}

#pragma mark -
#pragma mark other things
- (void) getUserProfile {
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"GET" pathWithLeadingSlash:@"/profile" HTTPBody:nil sign:NO success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"didReceiveProfileData" object:nil userInfo:JSON];
        ;
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"receiveDataFailure" object:nil];
        NSLog(@"failure, %@", error);
    }];
    
    [operation start];
}

- (void) discover {
    
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"HEAD" pathWithLeadingSlash:@"/" HTTPBody:nil sign:NO success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSLog(@"got %@", [[response allHeaderFields] valueForKey:@"Link"]);
        [self registerWithTentServer];
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"receiveDataFailure" object:nil];
        NSLog(@"failure, %@", error);
    }];
    
    [operation start];
}


- (void) getFollowings
{
    
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"GET" pathWithLeadingSlash:@"/followings" HTTPBody:nil sign:YES success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSLog(@"got followings %@", JSON);
        
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        [[NSNotificationCenter defaultCenter] postNotificationName:@"receiveDataFailure" object:nil];
        NSLog(@"failure, %@ \n\nwith request %@", error, [request allHTTPHeaderFields]);
    }];
    
    [operation start];
}

- (void) pushProfileInfo
{
    /*
     "name": "The Tentity",
     "avatar_url": "http://example.org/avatar.jpg",
     "birthdate": "2012-08-23",
     "location": "The Internet",
     "gender": "Unknown",
     "bio": "Dignissimos autem pariatur deserunt voluptatem sed incidunt occaecati."
     */
    
    NSMutableDictionary *profileInfo = [NSMutableDictionary dictionaryWithCapacity:0];
    
    [profileInfo setValue:@"Justin Sanders" forKey:@"name"];
    [profileInfo setValue:@"http://example.org/avatar.jpg" forKey:@"avatar_url"];
    [profileInfo setValue:@"2012-08-23" forKey:@"birthdate"];
    [profileInfo setValue:@"The Internet" forKey:@"location"];
    [profileInfo setValue:@"male" forKey:@"gender"];
    [profileInfo setValue:@"this is my bio" forKey:@"bio"];

    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"PUT" pathWithLeadingSlash:@"/profile/https%3A%2F%2Ftent.io%2Ftypes%2Finfo%2Fbasic%2Fv0.1.0" HTTPBody:profileInfo sign:YES success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSLog(@"worked");
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"failed \nrequest: %@\nresponse: %@\n\nJSON: %@\n\n error: %@", request, [response allHeaderFields], JSON, error);
    }];
    
    [operation start];
}

- (void) newFollowing
{
    NSMutableDictionary *followingInfo = [NSMutableDictionary dictionaryWithCapacity:0];
    
    [followingInfo setValue:@"http://google.com" forKey:@"entity"];
    
    AFJSONRequestOperation *operation = [self.cocoaTentCommunication newJSONRequestOperationWithMethod:@"POST" pathWithLeadingSlash:@"/followings" HTTPBody:followingInfo sign:YES success:^(NSURLRequest *request, NSHTTPURLResponse *response, id JSON) {
        NSLog(@"worked %@", JSON);
    } failure:^(NSURLRequest *request, NSHTTPURLResponse *response, NSError *error, id JSON) {
        NSLog(@"failed \nrequest: %@\n%@\n\nresponse: %@\n\nJSON: %@\n\n error: %@", [request allHTTPHeaderFields], [request HTTPBody], [response allHeaderFields], JSON, error);
    }];
    
    [operation start];
}

- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
    NSLog(@"got updated data for %@, key: %@; value: %@", [object class], keyPath, change);
}
@end
