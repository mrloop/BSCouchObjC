//
//  BSCouchDBServer.m
//  BSCouchObjC
//
//  Created by Daniel Thorpe on 07/01/2011.
//  Copyright 2011 Blinding Skies Limited. All rights reserved.
//

#import "BSCouchDBServer.h"
#import "BSCouchObjC.h"
#import "NSStringAdditions.h"

#import "ASIHTTPRequest.h"
#import "ASIDownloadCache.h"
#import "ASIHTTPRequestDelegate.h"

#pragma mark Functions

@interface RequestDelegate : NSObject <ASIHTTPRequestDelegate> {
@private
	void (^sBlock)(ASIHTTPRequest *);
	void (^fBlock)(ASIHTTPRequest *);
}


- (id)initWithSuccessBlock:(void (^)(ASIHTTPRequest *))successBlock 
			  failureBlock:(void (^)(ASIHTTPRequest *))failureBlock;
- (void)requestFinished:(ASIHTTPRequest *)request;
- (void)requestFailed:(ASIHTTPRequest *)request;

@end

@implementation RequestDelegate

- (id)initWithSuccessBlock:(void (^)(ASIHTTPRequest *))successBlock 
			  failureBlock:(void (^)(ASIHTTPRequest *))failureBlock
{
	self = [super init];
	if (self) {
		sBlock = successBlock;
		fBlock = failureBlock;
	}
	return self;
}

- (void)requestFinished:(ASIHTTPRequest *)request
{
	sBlock(request);
}

- (void)requestFailed:(ASIHTTPRequest *)request
{
	fBlock(request);
}

@end



NSString *percentEscape(NSString *str) {
	if (![str hasPrefix:@"org.couchdb.user%3A"]) {
		return [str stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	}
	return str;
}

#pragma mark PrivateMethods

@interface BSCouchDBServer ()

- (ASIHTTPRequest *)requestWithPath:(NSString *)aPath;

@end

#pragma mark -

@implementation BSCouchDBServer

@synthesize hostname;
@synthesize port;
@synthesize path;
@synthesize cookie;
@synthesize login;
@synthesize password;
@synthesize url;
@synthesize isSSL;

#pragma mark -
#pragma mark Initialization

+ (void)initialize {
	[super initialize];
	// Turn on the ASIHTTPRequest response cache
	[ASIHTTPRequest setDefaultCache:[ASIDownloadCache sharedCache]];
}

- (id)initWithHost:(NSString *)_hostname port:(NSUInteger)_port path:(NSString *)_path ssl:(BOOL)_isSSL {
	self = [super init];
	if (self) {
		self.hostname = _hostname;
		self.port = _port;
		self.path = _path;
		self.isSSL = _isSSL;
	}
	return self;
}

- (id)initWithHost:(NSString *)_hostname port:(NSUInteger)_port {
	return [self initWithHost:_hostname port:_port path:nil ssl:NO];
}

- (id)init {
	return [self initWithHost:@"localhost" port:5984 path:nil ssl:NO];
}

- (void)dealloc {
	self.hostname = nil; [hostname release];
	self.path = nil; [path release];
	self.cookie = nil; [cookie release];
	self.url = nil; [url release];
	[super dealloc];
}

#pragma mark -
#pragma mark Dynamic methods

- (NSURL *)url {
	if (!url) {
		self.url = [self urlWithAuthentication:YES];
	}
	return url;
}

#pragma mark -
#pragma mark HTTP Requests

/**
 This does starts the request going synchronously.
 We perform all requests synchronously so that the function returns
 with the answer. The calling method should ideally not be run in 
 the main thread (to avoid locking the interface), although we don't
 enforce or check this. 
 */
- (NSString *)sendSynchronousRequest:(ASIHTTPRequest *)request {
	
	// Set credentials
	[request setValidatesSecureCertificate:NO];
	if (self.login && self.password) {
		request.username = self.login;
		request.password = self.password;
	}
	
	[request startSynchronous];
	NSError *error = [request error];
	if (error) {
		NSLog(@"Error: %@", [error userInfo]);
		NSLog(@"response string: %@",[request responseString]); 
		return nil;
	}
	
	NSData *data = [request responseData];
	
	// Get the data as a UTF8 string
	NSString *str = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
	
	return [str autorelease];	
}


/**
 This does starts the request going asynchronously
 */
- (void)sendAsynchronousRequest:(ASIHTTPRequest *)request 
				  usingDelegate:(id<ASIHTTPRequestDelegate>)delegate

{
	// Set credentials
	[request setValidatesSecureCertificate:NO];
	if (self.login && self.password) {
		request.username = self.login;
		request.password = self.password;
	}
	
	request.delegate = delegate;
	[request startAsynchronous];
}

- (void)sendAsynchronousRequest:(ASIHTTPRequest *)request 
			  usingSuccessBlock:(void (^)(ASIHTTPRequest *))successBlock
			  usingFailureBlock:(void (^)(ASIHTTPRequest *))failureBlock

{
	// Set credentials
	[request setValidatesSecureCertificate:NO];
	if (self.login && self.password) {
		request.username = self.login;
		request.password = self.password;
	}
	
	request.delegate = [[[RequestDelegate alloc] initWithSuccessBlock:successBlock failureBlock:failureBlock] autorelease];
	[request startAsynchronous];
}



- (ASIHTTPRequest *)requestWithPath:(NSString *)aPath {
    NSURL *aUrl = self.url;
    if (aPath && ![aPath isEqualToString:@"/"])
        aUrl = [NSURL URLWithString:aPath relativeToURL:self.url];
    return [ASIHTTPRequest requestWithURL:aUrl];
}


#pragma mark -
#pragma mark Server Infomation

// Check whether the server is online/reachable
- (BOOL)isReachableWithError:(NSError *)error {
	return [self.url checkResourceIsReachableAndReturnError:&error];
}

// Returns the CouchDB version string of the server
- (NSString *)version {
    ASIHTTPRequest *request = [self requestWithPath:nil];
    NSString *json = [self sendSynchronousRequest:request];
    return [[json JSONValue] valueForKey:@"version"];
}

- (NSString *)serverURLAsString:(BOOL)authenticateIfPossible {
	if(authenticateIfPossible && self.login && self.password) {
		if(!self.path)
			return [NSString stringWithFormat:@"%@://%@:%@@%@:%u", self.isSSL ? @"https" : @"http", self.login, self.password, self.hostname, self.port];  
		return [NSString stringWithFormat:@"%@://%@:%@@%@:%u/%@/", self.isSSL ? @"https" : @"http", self.login, self.password,  self.hostname, self.port, self.path];  		
	}	
	if(!self.path)
		return [NSString stringWithFormat:@"%@://%@:%u/", self.isSSL ? @"https" : @"http", self.hostname, self.port];  
	return [NSString stringWithFormat:@"%@://%@:%u/%@/", self.isSSL ? @"https" : @"http", self.hostname, self.port, self.path];  		
}

// Return the url with the option of authentication details or not
- (NSURL *)urlWithAuthentication:(BOOL)authenticateIfPossible {
	return [NSURL URLWithString:[self serverURLAsString:authenticateIfPossible]];
}


#pragma mark -
#pragma mark Databases

// Returns a list of the databases on the server
- (NSArray *)allDatabases {	
	// Use the special CouchDB request	
    ASIHTTPRequest *request = [self requestWithPath:@"_all_dbs"];	
	NSString *json = [self sendSynchronousRequest:request];
	if (json) {
		return [json JSONValue];
	}
    return nil;
}

// Creates a database
- (BOOL)createDatabase:(NSString *)databaseName {
	// Just call PUT databasename
    ASIHTTPRequest *request = [self requestWithPath:percentEscape(databaseName)];
    request.requestMethod = @"PUT";
	request.postBody = [NSData dataWithBytes:@"" length:0];
	NSString *json = [self sendSynchronousRequest:request];
	BSCouchDBResponse *response = [BSCouchDBResponse responseWithJSON:json];	
	return response.ok;
}

// Deletes a database
- (BOOL)deleteDatabase:(NSString *)databaseName {
	// Just call DELETE databaseName
    ASIHTTPRequest *request = [self requestWithPath:percentEscape(databaseName)];
    request.requestMethod = @"DELETE";
	// Make the request
	NSString *json = [self sendSynchronousRequest:request];
	// Get the CouchDB response
	BSCouchDBResponse *response = [BSCouchDBResponse responseWithJSON:json];	
	return response.ok;
}

// Gets a database
- (BSCouchDBDatabase *)database:(NSString *)databaseName {
	return [[[BSCouchDBDatabase alloc] initWithServer:self name:databaseName] autorelease];
}




#pragma mark -
#pragma mark Users & Authentication

// Create a database reader (non admin user)
- (BSCouchDBResponse *)createUser:(NSString *)_name password:(NSString *)_password {
	
	NSParameterAssert(_name);
	NSParameterAssert(_password);	
	NSAssert(self.login != nil, @"The server need's an administrator login name");
	NSAssert(self.password != nil, @"The server need's an administrator login password");
	
	// Create a salt
	NSString *salt = [[NSString stringWithFormat:@"%lf", [[NSDate date] timeIntervalSince1970]] sha1];
	
	// Hash the password and salt
	NSString *digest = [[NSString stringWithFormat:@"%@%@", _password, salt] sha1];
	
	// Create the document id
	NSString *docid = [NSString stringWithFormat:@"org.couchdb.user%%3A%@", _name];
	
	// Create a dictionary
	NSMutableDictionary *dic = [[NSMutableDictionary alloc] initWithCapacity:6];
	
	// Create an empty roles array
	NSArray *roles = [[NSArray alloc] init];	
	
	// Set the properties of the dictionary
	[dic setObject:salt forKey:@"salt"];
	[dic setObject:digest forKey:@"password_sha"];
	[dic setObject:_name forKey:@"name"];
	[dic setObject:@"user" forKey:@"type"];
	[dic setObject:roles forKey:@"roles"];
	[dic setObject:docid forKey:@"_id"];
	
	// Release memory
	[roles release];
	
	// Now we push the dictionary to the authentication db
	NSString *authenticationDB = @"_users";
	
	// Create a SBCouchDatabase instance
	BSCouchDBDatabase *db = [self database:authenticationDB];
	
	// Put the document on the server
	BSCouchDBResponse *response = [db putDocument:dic named:docid];
	
	// Release memory
	[dic release];
	
	return response;	
}

// Login using a name / password
- (BOOL)loginUsingName:(NSString *)_username andPassword:(NSString *)_password {
	
	// We're going to login using the credential and the store the cookie that we get back
	NSString *post = [NSString stringWithFormat:@"name=%@&password=%@", _username, _password];
	NSMutableData *postData = [NSMutableData dataWithData:[post dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:YES]];
	
	// Create a request
	ASIHTTPRequest *request = [self requestWithPath:@"_session"];
	[request setRequestMethod:@"POST"];
	[request addRequestHeader:@"Content-Type" value:@"application/x-www-form-urlencoded; charset=UTF-8"];
	[request setPostBody:postData];
	
    NSString *json = [self sendSynchronousRequest:request];
	NSLog(@"result: %@", json);	
	BSCouchDBResponse *response = [BSCouchDBResponse responseWithJSON:json];	
	
    if (response.ok) {
		// We need to get the Set-Cookie response header
		self.cookie = [[request responseHeaders] objectForKey:@"Set-Cookie"];
    }
	return response.ok;
}




#pragma mark -
#pragma mark Replication

// Replicate databases
- (BSCouchDBReplicationResponse *)replicateFrom:(NSString *)source to:(NSString *)target docs:(NSArray *)doc_ids filter:(NSString *)filter params:(NSDictionary *)queryParams {
	
	NSParameterAssert(source);
	NSParameterAssert(target);	
	NSAssert(self.login, @"We require admin privileges to the target database");
	NSAssert(self.password, @"We require admin privileges to the target database");
	
	// Get the source and target databases (this function assumes the databases are on the same server)
	BSCouchDBDatabase *sourceDB = [self database:source];
	BSCouchDBDatabase *targetDB = [self database:target];
	
	// Work out the payload
	NSMutableDictionary *dic = [NSMutableDictionary dictionaryWithCapacity:3];
	[dic setValue:[sourceDB.url absoluteString] forKey:@"source"];
	[dic setValue:[targetDB.url absoluteString] forKey:@"target"];
	
	if(doc_ids) {
		[dic setValue:doc_ids forKey:@"doc_ids"];
	}
	if(filter) {
		[dic setValue:filter forKey:@"filter"];
	}
	if(queryParams) {
		[dic setValue:queryParams forKey:@"query_params"];
	}
	
	// Get the JSON representation of this (this is the post data)
	NSString *json = [dic JSONRepresentation];
	
	// Create a request
	ASIHTTPRequest *request = [self requestWithPath:@"_replicate"];
	NSMutableData *body = [NSMutableData dataWithData:[json dataUsingEncoding:NSUTF8StringEncoding allowLossyConversion:NO]];
	[request setRequestMethod:@"POST"];
	[request addRequestHeader:@"Content-Type" value:@"application/json; charset=UTF-8"];
	[request setPostBody:body];
	
    json = [self sendSynchronousRequest:request];
	
    if (200 == [request responseStatusCode	]) {
        return [BSCouchDBReplicationResponse responseWithJSON:json];
    }
    return nil;
}



#pragma mark -
#pragma mark NSURLConnectionDelegate methods

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	// We've got enough information to create a NSURLResponse
	// Because it can be called multiple times, such as for a redirect,
	// we reset the data each time.
	NSLog(@"connection did receive response.");
	//	[self.receivedData setLength:0];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
	// We received some data
	NSLog(@"connection did receive %d bytes of data.", [data length]);
	//	[self.receivedData appendData:data];
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	// We encountered an error
	
	// Release the retained connection and the data received so far
	//	self.currentConnection = nil; [currentConnection release];
	//	self.receivedData = nil; [receivedData release];
	
	// Log the error
    NSLog(@"Connection failed! Error - %@ %@", [error localizedDescription], [[error userInfo] objectForKey:NSURLErrorFailingURLStringErrorKey]);
	
	//	failureCallback(error);
	
	// Unblock the connection
	//	self.blockConnection = NO;
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection {
	// We received all the data without errors
	// Unblock the connection
	NSLog(@"connection did finish.");	
	//	self.blockConnection = NO;	
}

@end
