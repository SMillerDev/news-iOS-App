//
//  OCNewsHelper.m
//  iOCNews
//

/************************************************************************
 
 Copyright 2013 Peter Hedlund peter.hedlund@me.com
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions
 are met:
 
 1. Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 2. Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY THE AUTHOR "AS IS" AND ANY EXPRESS OR
 IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES
 OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR ANY DIRECT, INDIRECT,
 INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
 DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
 THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 *************************************************************************/

#import "OCNewsHelper.h"
#import "OCAPIClient.h"
#import "Feeds.h"
#import "NSDictionary+HandleNull.h"
#import <SDWebImage/SDWebImageDownloader.h>
#import <SDWebImage/UIImageView+WebCache.h>

@interface OCNewsHelper () {
    NSMutableSet *foldersToAdd;
    NSMutableSet *foldersToDelete;
    NSMutableSet *foldersToRename;
    NSMutableSet *feedsToAdd;
    NSMutableSet *feedsToDelete;
    NSMutableSet *feedsToRename;
    NSMutableSet *feedsToMove;
    NSMutableSet *itemsToMarkRead;
    NSMutableSet *itemsToMarkUnread;
    NSMutableSet *itemsToStar;
    NSMutableSet *itemsToUnstar;
    
    void (^_completionHandler)(UIBackgroundFetchResult);
    BOOL completionHandlerCalled;
}

- (int)addFolderFromDictionary:(NSDictionary*)dict;
- (int)addFeedFromDictionary:(NSDictionary*)dict;
- (void)addItemFromDictionary:(NSDictionary*)dict;
- (NSNumber*)folderLastModified:(NSNumber*)folderId;
- (NSNumber*)feedLastModified:(NSNumber*)feedId;
- (void)updateItemsFirstTime;
- (void)updateItemsWithLastModified:(NSNumber*)lastMod type:(NSNumber*)aType andId:(NSNumber*)anId;
- (void)updateFeedItemsWithLastModified:(NSNumber*)lastMod type:(NSNumber*)aType andId:(NSNumber*)anId;

@end

@implementation OCNewsHelper

@synthesize context;
@synthesize objectModel;
@synthesize coordinator;
@synthesize feedsRequest;
@synthesize folderRequest;
@synthesize feedRequest;
@synthesize itemRequest;

+ (OCNewsHelper*)sharedHelper {
    static dispatch_once_t once_token;
    static id sharedHelper;
    dispatch_once(&once_token, ^{
        sharedHelper = [[OCNewsHelper alloc] init];
    });
    return sharedHelper;
}

- (OCNewsHelper*)init {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    NSError *error = nil;
    NSArray *feeds = [self.context executeFetchRequest:self.feedsRequest error:&error];
    if (!feeds.count) {
        Feeds *newFeeds = [NSEntityDescription insertNewObjectForEntityForName:@"Feeds" inManagedObjectContext:self.context];
        newFeeds.starredCount = [NSNumber numberWithInt:0];
        newFeeds.newestItemId = [NSNumber numberWithInt:0];
    }
    
    error = nil;
    NSArray *feed = [self.context executeFetchRequest:self.feedRequest error:&error];
    
    if (!feed.count) {
        Feed *allFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
        allFeed.myId = [NSNumber numberWithInt:-2];
        allFeed.url = @"";
        allFeed.title = @"All Articles";
        allFeed.faviconLink = @"favicon";
        allFeed.added = [NSNumber numberWithInt:1];
        allFeed.folderId = [NSNumber numberWithInt:0];
        allFeed.unreadCount = [NSNumber numberWithInt:0];
        allFeed.link = @"";
        
        Feed *starredFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
        starredFeed.myId = [NSNumber numberWithInt:-1];
        starredFeed.url = @"";
        starredFeed.title = @"Starred";
        starredFeed.faviconLink = @"star_icon";
        starredFeed.added = [NSNumber numberWithInt:2];
        starredFeed.folderId = [NSNumber numberWithInt:0];
        starredFeed.unreadCount = [NSNumber numberWithInt:0];
        starredFeed.link = @"";
        starredFeed.lastModified = [NSNumber numberWithLong:[[NSUserDefaults standardUserDefaults] integerForKey:@"LastModified"]];
    }
    
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    foldersToAdd =      [NSMutableSet setWithArray:[[prefs arrayForKey:@"FoldersToAdd"] mutableCopy]];
    foldersToDelete =   [NSMutableSet setWithArray:[[prefs arrayForKey:@"FoldersToDelete"] mutableCopy]];
    foldersToRename =   [NSMutableSet setWithArray:[[prefs arrayForKey:@"FoldersToRename"] mutableCopy]];
    feedsToAdd =        [NSMutableSet setWithArray:[[prefs arrayForKey:@"FeedsToAdd"] mutableCopy]];
    feedsToDelete =     [NSMutableSet setWithArray:[[prefs arrayForKey:@"FeedsToDelete"] mutableCopy]];
    feedsToRename =     [NSMutableSet setWithArray:[[prefs arrayForKey:@"FeedsToRename"] mutableCopy]];
    feedsToMove =       [NSMutableSet setWithArray:[[prefs arrayForKey:@"FeedsToMove"] mutableCopy]];
    itemsToMarkRead =   [NSMutableSet setWithArray:[[prefs arrayForKey:@"ItemsToMarkRead"] mutableCopy]];
    itemsToMarkUnread = [NSMutableSet setWithArray:[[prefs arrayForKey:@"ItemsToMarkUnread"] mutableCopy]];
    itemsToStar =       [NSMutableSet setWithArray:[[prefs arrayForKey:@"ItemsToStar"] mutableCopy]];
    itemsToUnstar =     [NSMutableSet setWithArray:[[prefs arrayForKey:@"ItemsToUnstar"] mutableCopy]];

    [self updateStarredCount];
    [self saveContext];

    __unused BOOL reachable = [[OCAPIClient sharedClient] reachabilityManager].isReachable;
    
    return self;
}

- (NSManagedObjectModel *)objectModel {
    if (!objectModel) {
        NSURL *modelURL = [[NSBundle mainBundle] URLForResource:@"News" withExtension:@"momd"];
        objectModel = [[NSManagedObjectModel alloc] initWithContentsOfURL:modelURL];
    }
    return objectModel;
}

- (NSPersistentStoreCoordinator *)coordinator {
    if (!coordinator) {
        NSURL *storeURL = [self documentsDirectoryURL];
        storeURL = [storeURL URLByAppendingPathComponent:@"News.sqlite"];
        NSDictionary *options = @{NSMigratePersistentStoresAutomaticallyOption : @YES,
                                  NSInferMappingModelAutomaticallyOption : @YES };
        NSError *error = nil;
        coordinator = [[NSPersistentStoreCoordinator alloc] initWithManagedObjectModel:[self objectModel]];
        if (![coordinator addPersistentStoreWithType:NSSQLiteStoreType configuration:nil URL:storeURL options:options error:&error]) {
//            NSLog(@"Error %@, %@", error, [error localizedDescription]);
        }
    }
    return coordinator;
}

- (NSManagedObjectContext *)context {
    if (!context) {
        NSPersistentStoreCoordinator *myCoordinator = [self coordinator];
        if (myCoordinator != nil) {
            context = [[NSManagedObjectContext alloc] initWithConcurrencyType:NSMainQueueConcurrencyType];
            [context setPersistentStoreCoordinator:myCoordinator];
        }
    }
    return context;
}

- (void)saveContext {
    NSUserDefaults *prefs = [NSUserDefaults standardUserDefaults];
    [prefs setObject:[NSArray arrayWithArray:[foldersToAdd allObjects]] forKey:@"FoldersToAdd"];
    [prefs setObject:[NSArray arrayWithArray:[foldersToDelete allObjects]] forKey:@"FoldersToDelete"];
    [prefs setObject:[NSArray arrayWithArray:[foldersToRename allObjects]] forKey:@"FoldersToRename"];
    [prefs setObject:[NSArray arrayWithArray:[feedsToAdd allObjects]] forKey:@"FeedsToAdd"];
    [prefs setObject:[NSArray arrayWithArray:[feedsToDelete allObjects]] forKey:@"FeedsToDelete"];
    [prefs setObject:[NSArray arrayWithArray:[feedsToRename allObjects]] forKey:@"FeedsToRename"];
    [prefs setObject:[NSArray arrayWithArray:[feedsToMove allObjects]] forKey:@"FeedsToMove"];
    [prefs setObject:[NSArray arrayWithArray:[itemsToMarkRead allObjects]] forKey:@"ItemsToMarkRead"];
    [prefs setObject:[NSArray arrayWithArray:[itemsToMarkUnread allObjects]] forKey:@"ItemsToMarkUnread"];
    [prefs setObject:[NSArray arrayWithArray:[itemsToStar allObjects]] forKey:@"ItemsToStar"];
    [prefs setObject:[NSArray arrayWithArray:[itemsToUnstar allObjects]] forKey:@"ItemsToUnstar"];
    [prefs synchronize];
    
    NSError *error = nil;
    if (self.context != nil) {
        if ([self.context hasChanges] && ![self.context save:&error]) {
//            NSLog(@"Error saving data %@, %@", error, [error userInfo]);
        } else {
//            NSLog(@"Data saved");
        }
    }
}

#pragma mark - COREDATA -INSERT

- (int)addFolderFromDictionary:(NSDictionary*)dict {
    Folder *newFolder = [NSEntityDescription insertNewObjectForEntityForName:@"Folder" inManagedObjectContext:self.context];
    newFolder.myId = [dict objectForKey:@"id"];
    newFolder.name = [dict objectForKeyNotNull:@"name" fallback:@"Folder"];
    newFolder.unreadCountValue = 0;
    [self saveContext];
    return newFolder.myIdValue;
}

- (int)addFeedFromDictionary:(NSDictionary *)dict {
    Feed *newFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
    newFeed.myId = [dict objectForKey:@"id"];
    newFeed.url = [dict objectForKeyNotNull:@"url" fallback:@""];
    newFeed.title = [dict objectForKeyNotNull:@"title" fallback:@""];
    newFeed.faviconLink = [dict objectForKeyNotNull:@"faviconLink" fallback:@""];
    if (!newFeed.faviconLink.length) {
        newFeed.faviconLink = @"favicon";
    }
    newFeed.added = [dict objectForKey:@"added"];
    newFeed.folderId = [dict objectForKey:@"folderId"];
    newFeed.unreadCount = [dict objectForKey:@"unreadCount"];
    newFeed.link = [dict objectForKeyNotNull:@"link" fallback:@""];
    return newFeed.myIdValue;
}

- (void)faviconForFeedWithId:(NSNumber *)feedId imageView:(UIImageView *)imageView
{
    Feed *feed = [self feedWithId:feedId];
    if (feed && feed.myId) {
        if ([feed.faviconLink isEqualToString:@"favicon"] || [feed.faviconLink isEqualToString:@""]) {
            imageView.image = [UIImage imageNamed:@"favicon"];
        }
        else if ([feed.faviconLink isEqualToString:@"star_icon"] || [feed.faviconLink isEqualToString:@""]) {
            imageView.image = [UIImage imageNamed:@"star_icon"];
        }
        else {
            NSURL *faviconUrl = [NSURL URLWithString:feed.faviconLink];
            [imageView sd_setImageWithURL:faviconUrl placeholderImage:[UIImage imageNamed:@"favicon"]];
        }
    }
}

- (void)addItemFromDictionary:(NSDictionary *)dict {
    Item *newItem = [NSEntityDescription insertNewObjectForEntityForName:@"Item" inManagedObjectContext:self.context];
    newItem.myId = [dict objectForKey:@"id"];
    newItem.guid = [dict objectForKey:@"guid"];
    newItem.guidHash = [dict objectForKey:@"guidHash"];
    newItem.url = [dict objectForKeyNotNull:@"url" fallback:@""];
    newItem.title = [dict objectForKeyNotNull:@"title" fallback:@""];
    newItem.author = [dict objectForKeyNotNull:@"author" fallback:@""];
    newItem.pubDate = [dict objectForKeyNotNull:@"pubDate" fallback:nil];
    newItem.body = [dict objectForKeyNotNull:@"body" fallback:@""];
    newItem.enclosureMime = [dict objectForKeyNotNull:@"enclosureMime" fallback:@""];
    newItem.enclosureLink = [dict objectForKeyNotNull:@"enclosureLink" fallback:@""];
    newItem.feedId = [dict objectForKey:@"feedId"];
    newItem.unread = [dict objectForKey:@"unread"];
    newItem.starred = [dict objectForKey:@"starred"];
    newItem.lastModified = [dict objectForKey:@"lastModified"];
}

- (int)addFolder:(id)JSON {
    NSDictionary *jsonDict = (NSDictionary *) JSON;
    NSMutableArray *newFolders = [jsonDict objectForKey:@"folders"];
    int newFolderId = [self addFolderFromDictionary:[newFolders lastObject]];
    [self updateTotalUnreadCount];
    return newFolderId;
}

- (void)deleteFolder:(Folder*)folder {
    if (folder) {
        self.feedRequest.predicate = [NSPredicate predicateWithFormat:@"folderId == %@", folder.myId];
        NSMutableArray *feedsToBeDeleted = [NSMutableArray arrayWithArray:[self.context executeFetchRequest:self.feedRequest error:nil]];
        while (feedsToBeDeleted.count > 0) {
            Feed *feed = [feedsToBeDeleted lastObject];
            [self deleteFeed:feed];
        }
        [self.context deleteObject:folder];
        [self updateTotalUnreadCount];
    }
}

- (NSArray*)folders {
    self.folderRequest.predicate = nil;
    return [self.context executeFetchRequest:self.folderRequest error:nil];
}

- (int)addFeed:(id)JSON {
    NSDictionary *jsonDict = (NSDictionary *) JSON;
    NSMutableArray *newFeeds = [jsonDict objectForKey:@"feeds"];
    int newFeedId = [self addFeedFromDictionary:[newFeeds lastObject]];
    [self updateTotalUnreadCount];
    return newFeedId;
}

- (void)deleteFeed:(Feed*)feed {
    if (feed && feed.myId) {
        NSError *error = nil;
        [self.itemRequest setPredicate:[NSPredicate predicateWithFormat:@"feedId == %@", feed.myId]];
        
        NSArray *feedItems = [self.context executeFetchRequest:self.itemRequest error:&error];
        for (Item *item in feedItems) {
            [self.context deleteObject:item];
        }
        [self.context deleteObject:feed];
        [self updateTotalUnreadCount];
    }
}

- (void)sync:(void (^)(UIBackgroundFetchResult))completionHandler {
    _completionHandler = [completionHandler copy];
    completionHandlerCalled = NO;
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
        [[OCAPIClient sharedClient] GET:@"feeds" parameters:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            if (![responseObject isKindOfClass:[NSDictionary class]])
            {
                if (_completionHandler && !completionHandlerCalled) {
                    _completionHandler(UIBackgroundFetchResultFailed);
                    completionHandlerCalled = YES;
                }
                NSDictionary *userInfo = @{@"Title": @"Error Updating Feeds",
                                           @"Message": @"Unknown data returned from the server"};
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
                return;
            }

            [self updateFeeds:responseObject];
            [self updateFolders];

        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            if (_completionHandler && !completionHandlerCalled) {
                _completionHandler(UIBackgroundFetchResultFailed);
                completionHandlerCalled = YES;
            }
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            NSString *message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
            NSDictionary *userInfo = @{@"Title": @"Error Updating Feeds", @"Message": message};
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        if (_completionHandler && !completionHandlerCalled) {
            _completionHandler(UIBackgroundFetchResultFailed);
            completionHandlerCalled = YES;
        }
        NSDictionary *userInfo = @{@"Title": @"Unable to Reach Server", @"Message": @"Please check network connection and login."};
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
    }
}

- (void)updateFolders {
    [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
    [[OCAPIClient sharedClient] GET:@"folders" parameters:nil progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        //Remove previous
        //TODO: only fetch myId
        NSError *error = nil;
        [self.folderRequest setPredicate:nil];
        NSArray *oldFolders = [self.context executeFetchRequest:self.folderRequest error:&error];
        if (oldFolders) {
            NSArray *knownIds = [oldFolders valueForKey:@"myId"];
            NSDictionary *folderDict;
            
            if (responseObject && [responseObject isKindOfClass:[NSDictionary class]])
            {
                folderDict = (NSDictionary*)responseObject;
            }
            else
            {
                //            NSString *responseString = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
                //            NSLog(@"Response: %@", responseString);
                id json = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    folderDict = (NSDictionary*)json;
                } else {
                    folderDict = @{@"folders": @""};
                }
            }

            NSArray *newFolders = [NSArray arrayWithArray:folderDict[@"folders"]];
            
            NSArray *newIds = [newFolders valueForKey:@"id"];
            
            //Update folder names to those on server.
            NSDictionary *nameDict = [NSDictionary dictionaryWithObjects:[newFolders valueForKey:@"name"] forKeys:newIds];
            //NSLog(@"Titles: %@", titleDict);
            [oldFolders enumerateObjectsUsingBlock:^(Folder *folder, NSUInteger idx, BOOL *stop) {
                NSString *newName = nameDict[folder.myId];
                if (newName) {
                    folder.name = newName;
                }
            }];
            
            NSMutableArray *newOnServer = [NSMutableArray arrayWithArray:newIds];
            [newOnServer removeObjectsInArray:knownIds];
            [newOnServer enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
                NSPredicate * predicate = [NSPredicate predicateWithFormat:@"id == %@", obj];
                NSArray * matches = [newFolders filteredArrayUsingPredicate:predicate];
                if (matches.count > 0) {
                    [self addFolderFromDictionary:[matches lastObject]];
                }
            }];
            
            NSMutableArray *deletedOnServer = [NSMutableArray arrayWithArray:knownIds];
            [deletedOnServer removeObjectsInArray:newIds];
            [deletedOnServer filterUsingPredicate:[NSPredicate predicateWithFormat:@"self >= 0"]];
            while (deletedOnServer.count > 0) {
                Folder *folderToRemove = [self folderWithId:[deletedOnServer lastObject]];
                [self.context deleteObject:folderToRemove];
                [deletedOnServer removeLastObject];
            }
            
            for (NSNumber *folderId in foldersToDelete) {
                Folder *folder = [self folderWithId:folderId];
                [self deleteFolderOffline:folder]; //the feed will have been readded as new on server
            }
            [foldersToDelete removeAllObjects];
            
            for (NSString *name in foldersToAdd) {
                [self addFolderOffline:name];
            }
//            [foldersToAdd removeAllObjects];
            
            //@{@"folderId": anId, @"name": newName}
            for (NSDictionary *dict in foldersToRename) {
                [self renameFolderOfflineWithId:[dict objectForKey:@"folderId"] To:[dict objectForKey:@"name"]];
            }
            [foldersToRename removeAllObjects];
            NSNumber *lastMod = [NSNumber numberWithLong:[[NSUserDefaults standardUserDefaults] integerForKey:@"LastModified"]];
            if ([self itemCount] > 0) {
                [self updateItemsWithLastModified:lastMod type:[NSNumber numberWithInt:OCUpdateTypeAll] andId:[NSNumber numberWithInt:0]];
            } else {
                [self updateItemsFirstTime];
                [self updateItemsWithLastModified:lastMod type:[NSNumber numberWithInt:OCUpdateTypeStarred] andId:[NSNumber numberWithInt:0]];
            }
        }
        [self updateTotalUnreadCount];
    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        if (_completionHandler && !completionHandlerCalled) {
            _completionHandler(UIBackgroundFetchResultFailed);
            completionHandlerCalled = YES;
        }
        NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
        NSString *message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
        NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Feeds", @"Title", message, @"Message", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];

    }];
}

- (void)updateFeeds:(id)JSON {
    //Remove previous
    //TODO: only fetch myId
    NSError *error = nil;
    [self.feedRequest setPredicate:nil];
    NSArray *oldFeeds = [self.context executeFetchRequest:self.feedRequest error:&error];
    NSArray *knownIds = [oldFeeds valueForKey:@"myId"];
    
    error = nil;
    NSArray *feeds = [self.context executeFetchRequest:self.feedsRequest error:&error];
    
    //Add the new feeds
    NSDictionary *jsonDict = (NSDictionary *) JSON;
    Feeds *theFeeds = [feeds objectAtIndex:0];
    theFeeds.starredCount = [jsonDict objectForKey:@"starredCount"];
    theFeeds.newestItemId = [jsonDict objectForKey:@"newestItemId"];
    
    NSArray *newFeeds = [NSArray arrayWithArray:[jsonDict objectForKey:@"feeds"]];
    
    NSArray *newIds = [newFeeds valueForKey:@"id"];
    //NSLog(@"Known: %@; New: %@", knownIds, newIds);
    
    //Update feed titles to those on server.
    NSDictionary *titleDict = [NSDictionary dictionaryWithObjects:[newFeeds valueForKey:@"title"] forKeys:newIds];
    //NSLog(@"Titles: %@", titleDict);
    [oldFeeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
        NSString *newTitle = [titleDict objectForKey:feed.myId];
        if (newTitle) {
            feed.title = newTitle;
        }
    }];
    [self saveContext];
    NSMutableArray *newOnServer = [NSMutableArray arrayWithArray:newIds];
    [newOnServer removeObjectsInArray:knownIds];
    [newOnServer enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        NSPredicate * predicate = [NSPredicate predicateWithFormat:@"id == %@", obj];
        NSArray * matches = [newFeeds filteredArrayUsingPredicate:predicate];
        if (matches.count > 0) {
            [self addFeedFromDictionary:[matches lastObject]];
        }
    }];
    
    NSMutableArray *deletedOnServer = [NSMutableArray arrayWithArray:knownIds];
    [deletedOnServer removeObjectsInArray:newIds];
    [deletedOnServer filterUsingPredicate:[NSPredicate predicateWithFormat:@"self >= 0"]];
    while (deletedOnServer.count > 0) {
        Feed *feedToRemove = [self feedWithId:[deletedOnServer lastObject]];
        [self.context deleteObject:feedToRemove];
        [deletedOnServer removeLastObject];
    }
    [newFeeds enumerateObjectsUsingBlock:^(NSDictionary *feedDict, NSUInteger idx, BOOL *stop) {
        Feed *feed = [self feedWithId:[feedDict objectForKey:@"id"]];
        int unreadCount = [[feedDict objectForKey:@"unreadCount"] intValue];
        if (unreadCount < 0) {
            unreadCount = 0;
        }
        feed.unreadCountValue = unreadCount;
        feed.folderId = [feedDict objectForKey:@"folderId"];
        [self.context processPendingChanges]; //Prevents crash if a feed has moved to another folder
    }];
    
    for (NSNumber *feedId in feedsToDelete) {
        Feed *feed = [self feedWithId:feedId];
        [self deleteFeedOffline:feed]; //the feed will have been readded as new on server
    }
    [feedsToDelete removeAllObjects];
    
    for (NSString *urlString in feedsToAdd) {
        [self addFeedOffline:urlString];
    }
    [feedsToAdd removeAllObjects];
    
    //@{@"feedId": aFeedId, @"folderId": aFolderId}];
    for (NSDictionary *dict in feedsToMove) {
        [self moveFeedOfflineWithId:[dict objectForKey:@"feedId"] toFolderWithId:[dict objectForKey:@"folderId"]];
    }
    [feedsToMove removeAllObjects];
    
    for (NSDictionary *dict in feedsToRename) {
        [self renameFeedOfflineWithId:[dict objectForKey:@"feedId"] To:[dict objectForKey:@"name"]];
    }
    [feedsToRename removeAllObjects];

//    [self.context processPendingChanges]; //Prevents crash if a feed has moved to another folder
    [self updateTotalUnreadCount];
}

- (Folder*)folderWithId:(NSNumber*)anId {
    [self.folderRequest setPredicate:[NSPredicate predicateWithFormat:@"myId == %@", anId]];
    NSArray *myFolders = [self.context executeFetchRequest:self.folderRequest error:nil];
    return (Folder*)[myFolders lastObject];
}

- (Feed*)feedWithId:(NSNumber*)anId {
    [self.feedRequest setPredicate:[NSPredicate predicateWithFormat:@"myId == %@", anId]];
    NSArray *myFeeds = [self.context executeFetchRequest:self.feedRequest error:nil];
    return (Feed*)[myFeeds lastObject];
}

- (NSArray*)feedsInFolderWithId:(NSNumber*)folderId {
//    NSMutableArray *idArray = [NSMutableArray new];
    self.feedRequest.predicate = [NSPredicate predicateWithFormat:@"folderId == %@", folderId];
    NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:nil];
//    [feeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
//        [idArray addObject:feed.myId];
//    }];
    return feeds;
}

- (Item*)itemWithId:(NSNumber *)anId {
    [self.itemRequest setPredicate:[NSPredicate predicateWithFormat:@"myId == %@", anId]];
    NSArray *myItems = [self.context executeFetchRequest:self.itemRequest error:nil];
    return (Item*)[myItems lastObject];
}

- (long)feedCount {
    [self.feedRequest setPredicate:nil];
    long count = [self.context countForFetchRequest:self.feedRequest error:nil];
    return count - 2;
}

- (long)itemCount {
    [self.itemRequest setPredicate:nil];
    long count = [self.context countForFetchRequest:self.itemRequest error:nil];
    return count;
}

- (void)updateFolderWithId:(NSNumber *)anId {
    NSNumber *lastMod = [self folderLastModified:anId];
    [self updateItemsWithLastModified:lastMod type:[NSNumber numberWithInt:OCUpdateTypeFolder] andId:anId];
}

- (void)updateFeedWithId:(NSNumber*)anId {
    NSNumber *lastMod = [self feedLastModified:anId];
    if ([anId intValue] == -1) {
        [self updateItemsWithLastModified:lastMod type:[NSNumber numberWithInt:OCUpdateTypeStarred] andId:[NSNumber numberWithInt:0]];
    } else {
        [self updateItemsWithLastModified:lastMod type:[NSNumber numberWithInt:OCUpdateTypeFeed] andId:anId];
    }
}

- (NSNumber*)folderLastModified:(NSNumber *)aFolderId {
    Folder *folder = [self folderWithId:aFolderId];
    NSNumber *lastFolderUpdate = folder.lastModified;
    NSNumber *lastSync = [NSNumber numberWithLong:[[NSUserDefaults standardUserDefaults] integerForKey:@"LastModified"]];
    return [NSNumber numberWithInt:MAX([lastFolderUpdate intValue], [lastSync intValue])];
}

- (NSNumber*)feedLastModified:(NSNumber *)aFeedId {
    Feed *feed = [self feedWithId:aFeedId];
    NSNumber *lastFeedUpdate = feed.lastModified;
    NSNumber *lastSync = [NSNumber numberWithLong:[[NSUserDefaults standardUserDefaults] integerForKey:@"LastModified"]];
    return [NSNumber numberWithInt:MAX([lastFeedUpdate intValue], [lastSync intValue])];
}

- (void)updateItemsWithLastModified:(NSNumber*)lastMod type:(NSNumber*)aType andId:(NSNumber*)anId {
    NSDictionary *itemParams = @{@"lastModified": lastMod,
                                         @"type": aType,
                                           @"id": anId};
    
    [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
    [[OCAPIClient sharedClient] GET:@"items/updated" parameters:itemParams progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
        __block int errorCount = 0;
        NSDictionary *itemDict;

        if (responseObject && [responseObject isKindOfClass:[NSDictionary class]])
        {
            itemDict = (NSDictionary*)responseObject;
        }
        else
        {
//            NSString *responseString = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
//            NSLog(@"Response: %@", responseString);
            id json = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
            if (json && [json isKindOfClass:[NSDictionary class]]) {
                itemDict = (NSDictionary*)json;
            } else {
                itemDict = @{@"items": @""};
            }
        }
        
        //NSLog(@"New Items: %@", itemDict);
        NSArray *newItems = [NSArray arrayWithArray:[itemDict objectForKey:@"items"]];
        if (newItems.count > 0) {
            __block NSMutableSet *possibleDuplicateItems = [NSMutableSet new];
            [possibleDuplicateItems addObjectsFromArray:[newItems valueForKey:@"id"]];
            [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"myId IN %@", possibleDuplicateItems]];
            
            [self.itemRequest setResultType:NSManagedObjectResultType];
            
            NSArray *duplicateItems = [self.context executeFetchRequest:self.itemRequest error:nil];
            
            for (NSManagedObject *item in duplicateItems) {
                [self.context deleteObject:item];
            }
            [self saveContext];
            
            __block NSMutableSet *feedsWithNewItems = [[NSMutableSet alloc] init];
            [newItems enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
                NSNumber *myFeedId = [item objectForKey:@"feedId"];
                [feedsWithNewItems addObject:myFeedId];
                [self addItemFromDictionary:item];
            }];
            [self saveContext];
            
            NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"myId" ascending:NO];
            [self.itemRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
//            NSLog(@"Feeds with new items: %lu", (unsigned long)feedsWithNewItems.count);
            [feedsWithNewItems enumerateObjectsUsingBlock:^(NSNumber *feedId, BOOL *stop) {
                Feed *feed = [self feedWithId:feedId];
                [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"feedId == %@", feedId]];
                
                NSArray *feedItems = [self.context executeFetchRequest:self.itemRequest error:nil];
                NSMutableArray *filteredArray = [NSMutableArray arrayWithArray:[feedItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"unread == %@", [NSNumber numberWithBool:NO]]]];
                filteredArray = [NSMutableArray arrayWithArray:[filteredArray filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"starred == %@", [NSNumber numberWithBool:NO]]]];
                while (filteredArray.count > feed.articleCountValue) {
//                    Item *itemToRemove = [filteredArray lastObject];
//                    [self.context deleteObject:itemToRemove];
                    [filteredArray removeLastObject];
                }
                
                NSArray *unreadItems = [feedItems filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"unread == %@", [NSNumber numberWithBool:YES]]];
//                NSLog(@"Unread item count: %lu", (unsigned long)unreadItems.count);
                if (feed.unreadCountValue != unreadItems.count) {
                    ++errorCount;
                }
                feed.unreadCountValue = (int)unreadItems.count;
            }];
        }
        
        switch ([aType intValue]) {
            case OCUpdateTypeAll: {
                [self markItemsReadOffline:[itemsToMarkRead mutableCopy]];
                for (NSNumber *itemId in itemsToMarkUnread) {
                    [self markItemUnreadOffline:itemId];
                }
                for (NSNumber *itemId in itemsToStar) {
                    [self starItemOffline:itemId];
                }
                for (NSNumber *itemId in itemsToUnstar) {
                    [self unstarItemOffline:itemId];
                }
                [self updateStarredCount];
                [self updateTotalUnreadCount];
                if (errorCount == 0) {
                    [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]] forKey:@"LastModified"];
                }
            }
                break;
            case OCUpdateTypeFolder: {
                Folder *folder = [self folderWithId:anId];
                folder.lastModified = [NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]];
            }
                break;
            case OCUpdateTypeFeed:
            case OCUpdateTypeStarred: {
                if (errorCount == 0) {
                    Feed *feed = [self feedWithId:anId];
                    feed.lastModified = [NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]];
                }
            }
                break;
                
            default:
                break;
        }
        
        [self updateStarredCount];
        [self updateTotalUnreadCount];
        if (_completionHandler && !completionHandlerCalled) {
            _completionHandler((newItems.count > 0) ? UIBackgroundFetchResultNewData : UIBackgroundFetchResultNoData);
            completionHandlerCalled = YES;
        }
        [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
        

    } failure:^(NSURLSessionDataTask *task, NSError *error) {
        //feedsToUpdate;
        switch ([aType intValue]) {
            case OCUpdateTypeAll:
                [self updateFeedItemsWithLastModified:lastMod type:aType andId:anId];
                break;
            case OCUpdateTypeFolder: {
                //update feeds individually
                [self updateFeedItemsWithLastModified:lastMod type:aType andId:anId];
            }
                break;
            case OCUpdateTypeFeed:
            case OCUpdateTypeStarred: {
                if (_completionHandler && !completionHandlerCalled) {
                    _completionHandler(UIBackgroundFetchResultFailed);
                    completionHandlerCalled = YES;
                }
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                NSString *message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Items", @"Title", message, @"Message", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
            }
                break;
                
            default:
                break;
        }
    }];
}


- (void)updateFeedItemsWithLastModified:(NSNumber*)lastMod type:(NSNumber*)aType andId:(NSNumber*)anId {
    __block NSMutableArray *operations = [NSMutableArray new];
    __block NSMutableArray *addedItems = [NSMutableArray new];
    __block NSMutableArray *responseObjects = [NSMutableArray new];
    __block OCAPIClient *client = [OCAPIClient sharedClient];
    client.requestSerializer = [OCAPIClient jsonRequestSerializer];

    //update feeds individually
    [self.feedRequest setPredicate:[NSPredicate predicateWithFormat:@"myId > 0"]];
    __block NSArray *allFeeds = [self.context executeFetchRequest:self.feedRequest error:nil];
    if ([aType intValue] == OCUpdateTypeFolder) {
        allFeeds = [allFeeds filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"folderId == %@", anId]];
    }

    dispatch_group_t group = dispatch_group_create();
    [allFeeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
        dispatch_group_enter(group);
        NSDictionary *itemParams = [NSDictionary dictionaryWithObjectsAndKeys:[self feedLastModified:feed.myId], @"lastModified",
                                    [NSNumber numberWithInt:0], @"type",
                                    feed.myId, @"id", nil];
        
        
        NSURLSessionDataTask *task = [client GET:@"items/updated" parameters:itemParams progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            dispatch_group_leave(group);
            @synchronized(responseObjects) {
                [responseObjects addObject:responseObject];
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            dispatch_group_leave(group);
        }];

        [operations addObject:task];
    }];
    
    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __block int errorCount = 0;
        __block NSMutableSet *feedsWithNewItems;
        [operations enumerateObjectsUsingBlock:^(NSURLSessionDataTask *task, NSUInteger idx, BOOL *stop) {
            if (task.error) {
                ++errorCount;
            }
        }];
        [responseObjects enumerateObjectsUsingBlock:^(id respObject, NSUInteger idx, BOOL *stop) {
            NSDictionary *itemDict;
            
            if (respObject && [respObject isKindOfClass:[NSDictionary class]])
            {
                itemDict = (NSDictionary*)respObject;
            }
            else
            {
                //NSString *responseString = [[NSString alloc] initWithData:responseObject encoding:NSUTF8StringEncoding];
                //NSLog(@"Response: %@", responseString);
                id json = [NSJSONSerialization JSONObjectWithData:respObject options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    itemDict = (NSDictionary*)json;
                } else {
                    itemDict = @{@"items": @""};
                }
            }

            NSArray *newItems = [NSArray arrayWithArray:[itemDict objectForKey:@"items"]];
            if (newItems.count > 0) {
                [feedsWithNewItems addObject:[(NSDictionary*)[newItems objectAtIndex:0] objectForKey:@"feedId"]];
                [addedItems addObjectsFromArray:newItems];
                //NSLog(@"Feed: %@ (%d) adding %d for %d total items", feed.title, feed.unreadCountValue, newItems.count, addedItems.count);
            }
        }];
        if (addedItems.count > 0) {
            __block NSMutableSet *possibleDuplicateItems = [NSMutableSet new];
            [possibleDuplicateItems addObjectsFromArray:[addedItems valueForKey:@"id"]];
//            NSLog(@"Item count: %lu; possibleDuplicateItems count: %lu", (unsigned long)addedItems.count, (unsigned long)possibleDuplicateItems.count);
            [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"myId IN %@", possibleDuplicateItems]];
            [self.itemRequest setResultType:NSManagedObjectResultType];
            NSError *error = nil;
            NSArray *duplicateItems = [self.context executeFetchRequest:self.itemRequest error:&error];
//            NSLog(@"duplicateItems Count: %lu", (unsigned long)duplicateItems.count);
            
            for (NSManagedObject *item in duplicateItems) {
                //NSLog(@"Deleting duplicate with title: %@", ((Item*)item).title);
                [self.context deleteObject:item];
            }
            
            [addedItems enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
                [self addItemFromDictionary:item];
            }];
            [self saveContext];
            
            NSSortDescriptor *sort = [[NSSortDescriptor alloc] initWithKey:@"myId" ascending:NO];
            [self.itemRequest setSortDescriptors:[NSArray arrayWithObject:sort]];
            
            [feedsWithNewItems enumerateObjectsUsingBlock:^(NSNumber *feedId, BOOL *stop) {
                
                Feed *feed = [self feedWithId:feedId];
                
                [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"feedId == %@", feedId]];
                
                NSError *error = nil;
                NSMutableArray *feedItems = [NSMutableArray arrayWithArray:[self.context executeFetchRequest:self.itemRequest error:&error]];
                
                while (feedItems.count > feed.articleCountValue) {
                    Item *itemToRemove = [feedItems lastObject];
                    if (!itemToRemove.starredValue) {
                        if (!itemToRemove.unreadValue) {
//                            NSLog(@"Deleting item with id %i and title %@", itemToRemove.myIdValue, itemToRemove.title);
                            [self.context deleteObject:itemToRemove];
                            [feedItems removeLastObject];
                        }
                    }
                }
                [self saveContext];
            }];
            if ([aType intValue] == OCUpdateTypeAll) {
                [self markItemsReadOffline:[itemsToMarkRead mutableCopy]];
                for (NSNumber *itemId in itemsToMarkUnread) {
                    [self markItemUnreadOffline:itemId];
                }
                for (NSNumber *itemId in itemsToStar) {
                    [self starItemOffline:itemId];
                }
                for (NSNumber *itemId in itemsToUnstar) {
                    [self unstarItemOffline:itemId];
                }
            }
        }
        [self updateStarredCount];
        [self updateTotalUnreadCount];
        if (errorCount > 0) {
            if (_completionHandler && !completionHandlerCalled) {
                _completionHandler(UIBackgroundFetchResultFailed);
                completionHandlerCalled = YES;
            }
            NSString *message = @"At least one feed failed to update properly. Try syncing again.";
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Items", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        } else {
            if (_completionHandler && !completionHandlerCalled) {
                _completionHandler(UIBackgroundFetchResultNewData);
                completionHandlerCalled = YES;
            }
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]] forKey:@"LastModified"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
        }
    });
}

- (void)updateItemsFirstTime {
    __block NSMutableArray *operations = [NSMutableArray new];
    __block NSMutableArray *addedItems = [NSMutableArray new];
    __block NSMutableArray *responseObjects = [NSMutableArray new];
    __block OCAPIClient *client = [OCAPIClient sharedClient];
    client.requestSerializer = [OCAPIClient jsonRequestSerializer];

    NSError *error = nil;
    [self.feedRequest setPredicate:nil];
    NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:&error];

    dispatch_group_t group = dispatch_group_create();
    
    [feeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
        // Enter the group for each request we create
        dispatch_group_enter(group);
        int batchSize = MAX(50, feed.unreadCountValue);
        NSDictionary *itemParams = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:batchSize], @"batchSize",
                                    [NSNumber numberWithInt:0], @"offset",
                                    [NSNumber numberWithInt:0], @"type",
                                    feed.myId, @"id",
                                    @"true", @"getRead", nil];
        
        NSURLSessionDataTask *task = [client GET:@"items" parameters:itemParams progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            dispatch_group_leave(group);
            @synchronized(responseObjects) {
                [responseObjects addObject:responseObject];
            }
        }
        failure:^(NSURLSessionDataTask *task, NSError *error) {
            dispatch_group_leave(group);
        }];
        
        [operations addObject:task];
    }];

    dispatch_group_notify(group, dispatch_get_main_queue(), ^{
        __block int errorCount = 0;
        [operations enumerateObjectsUsingBlock:^(NSURLSessionDataTask *task, NSUInteger idx, BOOL *stop) {
            if (task.error) {
                ++errorCount;
            }
        }];
        [responseObjects enumerateObjectsUsingBlock:^(NSDictionary *JSON, NSUInteger idx, BOOL *stop) {
            NSArray *newItems = [NSArray arrayWithArray:[JSON objectForKey:@"items"]];
            [addedItems addObjectsFromArray:newItems];
        }];
        [addedItems enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
            [self addItemFromDictionary:item];
        }];
        [self saveContext];
        [self updateStarredCount];
        [self updateTotalUnreadCount];
        if (errorCount > 0) {
            if (_completionHandler && !completionHandlerCalled) {
                _completionHandler(UIBackgroundFetchResultFailed);
                completionHandlerCalled = YES;
            }
            NSString *message = @"At least one feed failed to update properly. Try syncing again.";
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Updating Items", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        } else {
            if (_completionHandler && !completionHandlerCalled) {
                _completionHandler(UIBackgroundFetchResultNewData);
                completionHandlerCalled = YES;
            }
            [[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:[[NSDate date] timeIntervalSince1970]] forKey:@"LastModified"];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
        }

    });
}

- (void)updateReadItems:(NSArray *)items {
    if (items) {
        [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"myId IN %@", items]];
        
        NSError *error = nil;
        NSArray *allItems = [self.context executeFetchRequest:self.itemRequest error:&error];
        if (!allItems || error) {
//            NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
        }
//        NSLog(@"Count: %lu", (unsigned long)items.count);
        
        if (allItems) {
            [allItems enumerateObjectsUsingBlock:^(Item *item, NSUInteger idx, BOOL *stop) {
                Feed *feed = [self feedWithId:item.feedId];
                if (item.unreadValue) {
                    ++feed.unreadCountValue;
                } else {
                    --feed.unreadCountValue;
                }
                if (feed.unreadCountValue < 0) {
                    feed.unreadCountValue = 0;
                }
            }];
        }
        [self updateTotalUnreadCount];
    }
}

- (void)updateFolderUnreadCount {
    self.folderRequest.predicate = nil;
    NSArray *folders = [self.context executeFetchRequest:self.folderRequest error:nil];
    [folders enumerateObjectsUsingBlock:^(Folder *folder, NSUInteger idx, BOOL *stop) {
        self.feedRequest.predicate = [NSPredicate predicateWithFormat:@"folderId == %@", folder.myId];
        NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:nil];
        folder.unreadCountValue = (int)[[feeds valueForKeyPath:@"@sum.unreadCount"] integerValue];
    }];
}

- (void)updateTotalUnreadCount {
    [self.feedRequest setPredicate:[NSPredicate predicateWithFormat:@"myId > 0"]];
    NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:nil];
    int totalUnreadCount = (int)[[feeds valueForKeyPath:@"@sum.unreadCount"] integerValue];
    [self feedWithId:[NSNumber numberWithInt:-2]].unreadCountValue = totalUnreadCount;
    [self feedWithId:[NSNumber numberWithInt:-2]].articleCountValue = (int)[self itemCount];
    
    UIUserNotificationSettings *currentSettings = [[UIApplication sharedApplication] currentUserNotificationSettings];
    if (currentSettings.types & UIUserNotificationTypeBadge) {
        [UIApplication sharedApplication].applicationIconBadgeNumber = totalUnreadCount;
    }
    [self updateFolderUnreadCount];
    [self saveContext];
}

- (void)updateStarredCount {
    [self.itemRequest setPredicate:[NSPredicate predicateWithFormat: @"starred == 1"]];
    
    NSError *error = nil;
    NSArray *starredItems = [self.context executeFetchRequest:self.itemRequest error:&error];
    if (!starredItems || error) {
//        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }
//    NSLog(@"Starred Count: %lu", (unsigned long)starredItems.count);
    
    error = nil;
    NSArray *feeds = [self.context executeFetchRequest:self.feedsRequest error:&error];
    if (!feeds || error) {
//        NSLog(@"Unresolved error %@, %@", error, [error userInfo]);
    }

    Feeds *theFeeds = [feeds lastObject];
    theFeeds.starredCountValue = (int)starredItems.count;
    
    [[self feedWithId:[NSNumber numberWithInt:-1]] setUnreadCountValue:(int)starredItems.count];
    [self saveContext];
}

- (void)addFolderOffline:(NSString*)name {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = @{@"name": name};
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] POST:@"folders" parameters:params progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            __unused int newFolderId = [self addFolder:responseObject];
            [foldersToAdd removeObject:name];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSString *message;
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            switch (response.statusCode) {
                case 409:
                    message = @"The folder already exists.";
                    break;
                case 422:
                    message = @"The folder name is invalid.";
                    break;
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'.", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Adding Folder", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
        
    } else {
        //offline
        [foldersToAdd addObject:name];
        Folder *newFolder = [NSEntityDescription insertNewObjectForEntityForName:@"Folder" inManagedObjectContext:self.context];
        newFolder.myId = [NSNumber numberWithLong:10000 + foldersToAdd.count];
        newFolder.name = name;
    }
    [self updateTotalUnreadCount];
}

- (void)deleteFolderOffline:(Folder*)folder {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSString *path = [NSString stringWithFormat:@"folders/%@", [folder.myId stringValue]];
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
        [[OCAPIClient sharedClient] DELETE:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
//            NSLog(@"Success");
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
//            NSLog(@"Failure");
            NSString *message;
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            switch (response.statusCode) {
                case 404:
                    message = @"The folder does not exist.";
                    break;
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'.", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Deleting Folder", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        //offline
        [foldersToDelete addObject:folder.myId];
    }
    [self deleteFolder:folder];
}

- (void)renameFolderOfflineWithId:(NSNumber*)anId To:(NSString*)newName {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = @{@"name": newName};
        NSString *path = [NSString stringWithFormat:@"folders/%@", [anId stringValue]];
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] PUT:path parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
//             NSLog(@"Success");
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
//            NSLog(@"Failure");
            NSString *message;
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            switch (response.statusCode) {
                case 404:
                    message = @"The folder does not exist.";
                    break;
                case 409:
                    message = @"A folder with this name already exists.";
                    break;
                case 422:
                    message = @"The folder name is invalid";
                    break;
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'.", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Renaming Feed", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        //offline
        [foldersToRename addObject:@{@"folderId": anId, @"name": newName}];
    }
    [[self folderWithId:anId] setName:newName];
    [self saveContext];
}

- (void)addFeedOffline:(NSString *)urlString {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:urlString, @"url", [NSNumber numberWithInt:0], @"folderId", nil];
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] POST:@"feeds" parameters:params progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
            NSDictionary *feedDict = nil;
            if (responseObject && [responseObject isKindOfClass:[NSDictionary class]])
            {
                feedDict = (NSDictionary*)responseObject;
            }
            else
            {
                id json = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
                if (json && [json isKindOfClass:[NSDictionary class]]) {
                    feedDict = (NSDictionary*)json;
                }
            }
            if (feedDict) {
                int newFeedId = [self addFeed:feedDict];
                NSDictionary *params = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:200], @"batchSize",
                                        [NSNumber numberWithInt:0], @"offset",
                                        [NSNumber numberWithInt:0], @"type",
                                        [NSNumber numberWithInt:newFeedId], @"id",
                                        [NSNumber numberWithInt:1], @"getRead", nil];
                
                [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
                [[OCAPIClient sharedClient] GET:@"items" parameters:params progress:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                    NSDictionary *itemsDict = nil;
                    if (responseObject && [responseObject isKindOfClass:[NSDictionary class]])
                    {
                        itemsDict = (NSDictionary*)responseObject;
                    }
                    else
                    {
                        id json = [NSJSONSerialization JSONObjectWithData:responseObject options:0 error:nil];
                        if (json && [json isKindOfClass:[NSDictionary class]]) {
                            itemsDict = (NSDictionary*)json;
                        }
                    }
                    if (itemsDict) {
                        NSArray *newItems = [NSArray arrayWithArray:[itemsDict objectForKey:@"items"]];
                        [newItems enumerateObjectsUsingBlock:^(NSDictionary *item, NSUInteger idx, BOOL *stop ) {
                            [self addItemFromDictionary:item];
                        }];
                        [self saveContext];
                    }
                } failure:^(NSURLSessionDataTask *task, NSError *error) {
                    NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                    NSString *message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Retrieving Items", @"Title", message, @"Message", nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
                    [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
                }];
            }
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
            NSString *message;
            switch (response.statusCode) {
                case 409:
                    message = @"The feed already exists";
                    break;
                case 422:
                    message = @"The feed could not be read. It most likely contains errors";
                    break;
                default:
                    message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                    break;
            }
            
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Adding Feed", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    
    } else {
        //offline
        [feedsToAdd addObject:urlString];
        Feed *newFeed = [NSEntityDescription insertNewObjectForEntityForName:@"Feed" inManagedObjectContext:self.context];
        newFeed.myId = [NSNumber numberWithLong:10000 + feedsToAdd.count];
        newFeed.url = urlString;
        newFeed.title = urlString;
        newFeed.faviconLink = @"favicon";
        newFeed.added = [NSNumber numberWithInt:1];
        newFeed.folderId = [NSNumber numberWithInt:0];
        newFeed.unreadCount = [NSNumber numberWithInt:0];
        newFeed.link = @"";
        //[feedsToDelete addObject:[NSNumber numberWithInt:10000 + feedsToAdd.count]]; //should be deleted when we get the real feed
    }
    [self updateTotalUnreadCount];
}

- (void) deleteFeedOffline:(Feed*)feed {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSString *path = [NSString stringWithFormat:@"feeds/%@", [feed.myId stringValue]];
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
        [[OCAPIClient sharedClient] DELETE:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
//            NSLog(@"Success");
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
//            NSLog(@"Failure");
            NSString *message = [NSString stringWithFormat:@"The error reported was '%@'", [error localizedDescription]];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Deleting Feed", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        //offline
        [feedsToDelete addObject:feed.myId];
    }
    [self deleteFeed:feed];
    [self saveContext];
}

- (void)moveFeedOfflineWithId:(NSNumber *)aFeedId toFolderWithId:(NSNumber *)aFolderId {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        NSDictionary *params = @{@"folderId": aFolderId};
        NSString *path = [NSString stringWithFormat:@"feeds/%@/move", [aFeedId stringValue]];
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] PUT:path parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
//            NSLog(@"Success");
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
//            NSLog(@"Failure");
            NSString *message = [NSString stringWithFormat:@"The error reported was '%@'", [error localizedDescription]];
            NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Moving Feed", @"Title", message, @"Message", nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
            [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
        }];
    } else {
        //offline
        [feedsToMove addObject:@{@"feedId": aFeedId, @"folderId": aFolderId}];
    }
}

- (void)renameFeedOfflineWithId:(NSNumber*)anId To:(NSString*)newName {
    if ([anId intValue] > 0) {
        if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
            //online
            NSDictionary *params = @{@"feedTitle": newName};
            NSString *path = [NSString stringWithFormat:@"feeds/%@/rename", [anId stringValue]];
            [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
            [[OCAPIClient sharedClient] PUT:path parameters:params success:^(NSURLSessionDataTask *task, id responseObject) {
//                NSLog(@"Success");
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
//                NSLog(@"Failure");
                NSString *message;
                NSHTTPURLResponse *response = (NSHTTPURLResponse *)task.response;
                switch (response.statusCode) {
                    case 404:
                        message = @"The feed does not exist.";
                        break;
                    case 405:
                        message = @"Please update the News app on the server to enable feed renaming.";
                        break;
                    default:
                        message = [NSString stringWithFormat:@"The server responded '%@' and the error reported was '%@'.", [NSHTTPURLResponse localizedStringForStatusCode:response.statusCode], [error localizedDescription]];
                        break;
                }
                NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys:@"Error Renaming Feed", @"Title", message, @"Message", nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkCompleted" object:self userInfo:nil];
                [[NSNotificationCenter defaultCenter] postNotificationName:@"NetworkError" object:self userInfo:userInfo];
            }];
        } else {
            //offline
            [feedsToRename addObject:@{@"feedId": anId, @"name": newName}];
        }
    }
    
    [[self feedWithId:anId] setTitle:newName];
    [self saveContext];
}

- (void)markItemsReadOffline:(NSMutableSet *)itemIds {
    if (!itemIds || itemIds.count == 0) {
        return;
    }
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] PUT:@"items/read/multiple" parameters:[NSDictionary dictionaryWithObject:[itemIds allObjects] forKey:@"items"] success:^(NSURLSessionDataTask *task, id responseObject) {
            [itemIds enumerateObjectsUsingBlock:^(NSNumber *itemId, BOOL *stop) {
                [itemsToMarkRead removeObject:itemId];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            [itemIds enumerateObjectsUsingBlock:^(NSNumber *itemId, BOOL *stop) {
                [itemsToMarkRead addObject:itemId];
            }];
        }];
    } else {
        //offline
        for (NSNumber *itemId in itemIds) {
            [itemsToMarkUnread removeObject:itemId];
        }
        [itemIds enumerateObjectsUsingBlock:^(NSNumber *itemId, BOOL *stop) {
            [itemsToMarkRead addObject:itemId];
        }];
    }
    [self updateReadItems:[itemIds allObjects]];
}

- (void)markAllItemsRead:(OCUpdateType)updateType feedOrFolderId:(NSNumber *)feedOrFolderId {

    NSError *error = nil;
    NSArray *feeds = [self.context executeFetchRequest:self.feedsRequest error:&error];
    
    Feeds *theFeeds = [feeds objectAtIndex:0];
    NSNumber *newestItem = theFeeds.newestItemId;
    NSString *path;
    
    NSBatchUpdateRequest *req = [[NSBatchUpdateRequest alloc] initWithEntityName:@"Item"];
    NSPredicate *pred1 = [NSPredicate predicateWithFormat:@"unread == %@", @(YES)];
    
    switch (updateType) {
        case OCUpdateTypeAll:
        {
            req.predicate = pred1;
            path = @"items/read";
            [self.feedRequest setPredicate:[NSPredicate predicateWithFormat:@"myId > 0"]];
            NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:nil];
            [feeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
                feed.unreadCountValue = 0;
            }];
        }
            break;
        case OCUpdateTypeFolder:
        {
            NSMutableArray *feedsArray = [NSMutableArray new];
            NSArray *folderFeeds = [[OCNewsHelper sharedHelper] feedsInFolderWithId:feedOrFolderId];
            [folderFeeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
                [feedsArray addObject:[NSCompoundPredicate andPredicateWithSubpredicates:@[[NSPredicate predicateWithFormat:@"feedId == %@", feed.myId], pred1]]];
            }];
            req.predicate = [NSCompoundPredicate orPredicateWithSubpredicates:feedsArray];
            path = [NSString stringWithFormat:@"folders/%@/read", feedOrFolderId];
            self.feedRequest.predicate = [NSPredicate predicateWithFormat:@"folderId == %@", feedOrFolderId];
            NSArray *feeds = [self.context executeFetchRequest:self.feedRequest error:nil];
            [feeds enumerateObjectsUsingBlock:^(Feed *feed, NSUInteger idx, BOOL *stop) {
                feed.unreadCountValue = 0;
            }];
        }
            break;
        case OCUpdateTypeFeed:
        {
            NSPredicate *pred2 = [NSPredicate predicateWithFormat:@"feedId == %@", feedOrFolderId];
            req.predicate = [NSCompoundPredicate andPredicateWithSubpredicates:@[pred1, pred2]];
            path = [NSString stringWithFormat:@"feeds/%@/read", feedOrFolderId];
            Feed *feed = [self feedWithId:feedOrFolderId];
            feed.unreadCountValue = 0;
        }
            break;
        case OCUpdateTypeStarred:
            //
            break;
            
        default:
            break;
    }
    
    req.propertiesToUpdate = @{@"unread": [NSNumber numberWithInt:0]};
    req.resultType = NSUpdatedObjectIDsResultType;
    NSBatchUpdateResult *res = (NSBatchUpdateResult *)[self.context executeRequest:req error:nil];
//    NSLog(@"%@ objects updated", res.result);
    
    __block NSMutableArray *itemIds = [NSMutableArray new];
    [(NSArray *)res.result enumerateObjectsUsingBlock:^(NSManagedObjectID *objID, NSUInteger idx, BOOL *stop) {
        Item *obj = (Item*)[context objectWithID:objID];
        if (![obj isFault]) {
            [self.context refreshObject:obj mergeChanges:YES];
        }
        [itemIds addObject:obj.myId];
    }];
    
    [self updateTotalUnreadCount];

    // /feeds/{feedId}/read
    // /folders/{folderId}/read
    // /items/read
    /*{
        // mark all items read lower than equal that id
        // this is mean to prevent marking items as read which the client/user does not yet know of
        "newestItemId": 10
    }*/    
    
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        [OCAPIClient sharedClient].requestSerializer = [OCAPIClient jsonRequestSerializer];
        [[OCAPIClient sharedClient] PUT:path parameters:@{@"newestItemId": newestItem} success:^(NSURLSessionDataTask *task, id responseObject) {
            [itemIds enumerateObjectsUsingBlock:^(NSNumber *objID, NSUInteger idx, BOOL *stop) {
                [itemsToMarkRead removeObject:objID];
            }];
        } failure:^(NSURLSessionDataTask *task, NSError *error) {
            [itemIds enumerateObjectsUsingBlock:^(NSNumber *objID, NSUInteger idx, BOOL *stop) {
                [itemsToMarkRead addObject:objID];
            }];
        }];
    } else {
        //offline
        [itemIds enumerateObjectsUsingBlock:^(NSNumber *objID, NSUInteger idx, BOOL *stop) {
            [itemsToMarkRead addObject:objID];
            [itemsToMarkUnread removeObject:objID];
        }];
    }
}

- (void)markItemUnreadOffline:(NSNumber*)itemId {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        Item *item = [self itemWithId:itemId];
        if (item) {
            NSString *path = [NSString stringWithFormat:@"items/%@/unread", item.myId];
            [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
            [[OCAPIClient sharedClient] PUT:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                [itemsToMarkUnread removeObject:itemId];
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                [itemsToMarkUnread addObject:itemId];
            }];
        }
    } else {
        [itemsToMarkRead removeObject:itemId];
        [itemsToMarkUnread addObject:itemId];
    }
    [self updateReadItems:@[itemId]];
}

- (void)starItemOffline:(NSNumber*)itemId {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        Item *item = [self itemWithId:itemId];
        if (item) {
            NSString *path = [NSString stringWithFormat:@"items/%@/%@/star", [item.feedId stringValue], item.guidHash];
            [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
            [[OCAPIClient sharedClient] PUT:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                [itemsToStar removeObject:itemId];
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                [itemsToStar addObject:itemId];
            }];
        }
    } else {
        //offline
        [itemsToUnstar removeObject:itemId];
        [itemsToStar addObject:itemId];
    }
    [self updateStarredCount];
}

- (void)unstarItemOffline:(NSNumber*)itemId {
    if ([OCAPIClient sharedClient].reachabilityManager.isReachable) {
        //online
        Item *item = [self itemWithId:itemId];
        if (item) {
            NSString *path = [NSString stringWithFormat:@"items/%@/%@/unstar", [item.feedId stringValue], item.guidHash];
            [OCAPIClient sharedClient].requestSerializer = [OCAPIClient httpRequestSerializer];
            [[OCAPIClient sharedClient] PUT:path parameters:nil success:^(NSURLSessionDataTask *task, id responseObject) {
                [itemsToUnstar removeObject:itemId];
            } failure:^(NSURLSessionDataTask *task, NSError *error) {
                [itemsToUnstar addObject:itemId];
            }];
        }
    } else {
        //offline
        [itemsToStar removeObject:itemId];
        [itemsToUnstar addObject:itemId];
    }
    [self updateStarredCount];
}

- (NSFetchRequest *)feedsRequest {
    if (!feedsRequest) {
        feedsRequest = [[NSFetchRequest alloc] init];
        [feedsRequest setEntity:[NSEntityDescription entityForName:@"Feeds" inManagedObjectContext:self.context]];
    }
    return feedsRequest;
}

- (NSFetchRequest *)feedRequest {
    if (!feedRequest) {
        feedRequest = [[NSFetchRequest alloc] init];
        [feedRequest setEntity:[NSEntityDescription entityForName:@"Feed" inManagedObjectContext:self.context]];
        feedRequest.predicate = nil;
    }
    return feedRequest;
}

- (NSFetchRequest *)folderRequest {
    if (!folderRequest) {
        folderRequest = [[NSFetchRequest alloc] init];
        [folderRequest setEntity:[NSEntityDescription entityForName:@"Folder" inManagedObjectContext:self.context]];
        folderRequest.predicate = nil;
    }
    return folderRequest;
}

- (NSFetchRequest *)itemRequest {
    if (!itemRequest) {
        itemRequest = [[NSFetchRequest alloc] init];
        [itemRequest setEntity:[NSEntityDescription entityForName:@"Item" inManagedObjectContext:self.context]];
        itemRequest.predicate = nil;
    }
    return itemRequest;
}

- (NSURL*) documentsDirectoryURL {
    return [[[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask] lastObject];
}

@end
