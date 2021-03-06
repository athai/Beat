//
//  BeatDocumentSettings.m
//  Beat
//
//  Created by Lauri-Matti Parppei on 30.10.2020.
//  Copyright © 2020 KAPITAN!. All rights reserved.
//

/*
 
 This creates a settings string that can be saved at the end of a Fountain file.
 Kind of stretching the rules of Fountain markup, but this is just an experiment.
 
 */

#import "BeatDocumentSettings.h"

#define JSON_MARKER @"\n\n/* If you're seeing this, you can remove the following stuff - BEAT:"
#define JSON_MARKER_END @"END_BEAT */"

@interface BeatDocumentSettings ()
@end

@implementation BeatDocumentSettings
-(id)init {
	self = [super init];
	if (self) {
		_settings = [NSMutableDictionary dictionary];
	}
	return self;
}

- (void)setBool:(NSString*)key as:(bool)value {
	[_settings setValue:[NSNumber numberWithBool:value] forKey:key];
}
- (void)setInt:(NSString*)key as:(NSInteger)value {
	[_settings setValue:[NSNumber numberWithInteger:value] forKey:key];
}
- (NSInteger)getInt:(NSString *)key {
	return [(NSNumber*)[_settings valueForKey:key] integerValue];
}
- (bool)getBool:(NSString *)key {
	return [(NSNumber*)[_settings valueForKey:key] boolValue];
}
- (void)remove:(NSString *)key {
	[_settings removeObjectForKey:key];
}


- (NSString*)getSettingsString {
	NSError *error;
	NSData *jsonData = [NSJSONSerialization dataWithJSONObject:_settings options:NSJSONWritingPrettyPrinted error:&error];

	if (! jsonData) {
		NSLog(@"%s: error: %@", __func__, error.localizedDescription);
		return @"";
	} else {
		NSString *json = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
		return [NSString stringWithFormat:@"%@ %@ %@", JSON_MARKER, json, JSON_MARKER_END];
	}
}
- (NSRange)readSettingsAndReturnRange:(NSString*)string {
	NSRange r1 = [string rangeOfString:JSON_MARKER];
	NSRange r2 = [string rangeOfString:JSON_MARKER_END];
	NSRange rSub = NSMakeRange(r1.location + r1.length, r2.location - r1.location - r1.length);
	
	if (r1.location != NSNotFound && r2.location != NSNotFound) {
		NSString *settingsString = [string substringWithRange:rSub];
		NSData *settingsData = [settingsString dataUsingEncoding:NSUTF8StringEncoding];
		NSError *error;
		
		NSDictionary *settings = [NSJSONSerialization JSONObjectWithData:settingsData options:kNilOptions error:&error];
		_settings = [NSMutableDictionary dictionaryWithDictionary:settings];
		
		// Return the index where settings start
		return NSMakeRange(r1.location, r1.length + rSub.length + r2.length);
	}
	
	return NSMakeRange(0, 0);
}

@end
/*
 
 olen nimennyt nämä seinät
 kodikseni
 sä et pääse enää sisään
 sä et pääse enää sisään ikinä
 
 mun kasvit kasvaa
 osaan pitää mullan kosteena
 mun kasvit kasvaa ilman sua
 
 sä et pääse enää sisään
 en tarvii sua mihinkään
 sä et pääse enää sisään
 ikinä.
 
 */
