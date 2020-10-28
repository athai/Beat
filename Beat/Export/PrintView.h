//
//  PrintView.h
//  Writer / Beat
//
//  Copyright © 2016 Hendrik Noeller. All rights reserved.
//  Parts copyright © 2019 Lauri-Matti Parppei. All rights reserved.

//

/*
 Permission is hereby granted, free of charge, to any person obtaining a copy
 of this software and associated documentation files (the "Software"), to deal
 in the Software without restriction, including without limitation the rights
 to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 copies of the Software, and to permit persons to whom the Software is
 furnished to do so, subject to the following conditions:
 
 The above copyright notice and this permission notice shall be included in
 all copies or substantial portions of the Software.
 
 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
 THE SOFTWARE.
 */

#import <Cocoa/Cocoa.h>
#import "Document.h"
#import <WebKit/WebKit.h>

typedef enum : NSUInteger {
	BeatToPDF = 0,
	BeatToPrint,
	BeatToPreview,
} BeatPrintOperation;

@protocol PrintViewDelegate
@property (nonatomic) NSString* header;
- (void) didFinishPreviewAt:(NSURL*)url;
@end

@interface PrintView : NSView
@property (weak) id<PrintViewDelegate> delegate;
// WIP: move all these values to the delegate
- (id)initWithDocument:(Document*)document script:(NSArray*)lines operation:(BeatPrintOperation)mode compareWith:(NSString*)oldScript;
- (id)initWithDocument:(Document*)document script:(NSArray*)lines operation:(BeatPrintOperation)mode compareWith:(NSString*)oldScript delegate:(id)delegate;
//- (id)initWithDocument:(Document*)document toPDF:(bool)pdf toPrint:(bool)print preview:(bool)preview;
//- (id)initWithDocument:(Document*)document toPDF:(bool)pdf toPrint:(bool)print;

@end