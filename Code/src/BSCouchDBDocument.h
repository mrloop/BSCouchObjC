//
//  BSCouchDBDocument.h
//  BSCouchObjC
//
//  Created by Daniel Thorpe on 11/01/2011.
//  Copyright 2011 Blinding Skies Limited. All rights reserved.
//

@class BSCouchDBDatabase;

@interface BSCouchDBDocument : NSMutableDictionary {
@private
	BSCouchDBDatabase *database;
}

@property (nonatomic, readwrite, retain) BSCouchDBDatabase *database;

+ (BSCouchDBDocument *)documentWithDictionary:(NSDictionary *)otherDictionary database:(BSCouchDBDatabase *)aDatabase;
- (id)initWithDictionary:(NSDictionary *)otherDictionary database:(BSCouchDBDatabase *)aDatabase;

#pragma mark Revision Information

// Returns this revision identifier
- (NSString *)revision;

// Returns an array of NSString objects for each revision
- (NSArray *)revisions;

// Returns the prevision revision identifier as a NSString
- (NSString *)previousRevision;

// Returns the index of this revision of the document
- (NSInteger)revisionIndex;

@end