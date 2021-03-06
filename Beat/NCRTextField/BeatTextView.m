//
//	BeatTextView.m
//  Based on NCRAutocompleteTextView.m
//  Heavily modified for Beat
//
//  Copyright (c) 2014 Null Creature. All rights reserved.
//  Parts copyright © 2019 Lauri-Matti Parppei. All rights reserved.
//

/*
 
 This NSTextView subclass is used to provide the additional editor features:
 - auto-completion (filled by methods from Document)
 - force line type (set in this class)
 - draw masks (array of masks provided by Document)
 - draw page breaks (array of breaks with y position provided by Document/FountainPaginator)
 
 Document acts as delegate, so its methods are accessible from this class too, see forcing elements.
 
 Auto-completion function is based on NCRAutoCompleteTextView.
 
 */

#import <QuartzCore/QuartzCore.h>
#import "BeatTextView.h"
#import "DynamicColor.h"
#import "Line.h"
#import "ScrollView.h"
#import "ContinousFountainParser.h"
#import "FountainPaginator.h"
#import "BeatColors.h"
#import "ThemeManager.h"

// This helps to create some sense of easeness
#define MARGIN_CONSTANT 10

#define MAX_RESULTS 10

#define HIGHLIGHT_STROKE_COLOR [NSColor selectedMenuItemColor]
#define HIGHLIGHT_FILL_COLOR [NSColor selectedMenuItemColor]
#define HIGHLIGHT_RADIUS 0.0
#define INTERCELL_SPACING NSMakeSize(20.0, 3.0)

#define WORD_BOUNDARY_CHARS [NSCharacterSet newlineCharacterSet]
#define POPOVER_WIDTH 300.0
#define POPOVER_PADDING 0.0

#define POPOVER_APPEARANCE NSAppearanceNameVibrantDark
//#define POPOVER_APPEARANCE NSAppearanceNameVibrantLight

#define POPOVER_FONT [NSFont fontWithName:@"Courier Prime" size:12.0]
// The font for the characters that have already been typed
#define POPOVER_BOLDFONT [NSFont fontWithName:@"Courier Prime Bold" size:12.0]
#define POPOVER_TEXTCOLOR [NSColor whiteColor]

@interface NCRAutocompleteTableRowView : NSTableRowView
@end

#pragma mark - Draw autocomplete table
@implementation NCRAutocompleteTableRowView

- (void)drawSelectionInRect:(NSRect)dirtyRect {
	if (self.selectionHighlightStyle != NSTableViewSelectionHighlightStyleNone) {
		NSRect selectionRect = NSInsetRect(self.bounds, 0.5, 0.5);
		[HIGHLIGHT_STROKE_COLOR setStroke];
		[HIGHLIGHT_FILL_COLOR setFill];
		NSBezierPath *selectionPath = [NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:HIGHLIGHT_RADIUS yRadius:HIGHLIGHT_RADIUS];
		[selectionPath fill];
		[selectionPath stroke];
	}
}
- (NSBackgroundStyle)interiorBackgroundStyle {
	if (self.isSelected) {
		return NSBackgroundStyleDark;
	} else {
		return NSBackgroundStyleLight;
	}
}
@end

static NSTouchBarItemIdentifier ColorPickerItemIdentifier = @"com.TouchBarCatalog.colorPicker";

#pragma mark - Autocompleting
@interface BeatTextView ()
@property (nonatomic, weak) IBOutlet NSTouchBar *touchBar;

@property (nonatomic, strong) NSPopover *infoPopover;
@property (nonatomic, strong) NSTextView *infoTextView;

@property (nonatomic, strong) NSPopover *autocompletePopover;
@property (nonatomic, weak) NSTableView *autocompleteTableView;
@property (nonatomic, strong) NSArray *matches;

@property (nonatomic) bool nightMode;
@property (nonatomic) bool forceElementMenu;

// Used to highlight typed characters and insert text
@property (nonatomic, copy) NSString *substring;

// Used to keep track of when the insert cursor has moved so we
// can close the popover. See didChangeSelection:
@property (nonatomic, assign) NSInteger lastPos;

// New scene numbering system
@property (nonatomic) NSMutableArray *sceneNumberLabels;

@end

@implementation BeatTextView

- (void)awakeFromNib {
	self.pageBreaks = [NSArray array];
	
	// Make a table view with 1 column and enclosing scroll view. It doesn't
	// matter what the frames are here because they are set when the popover
	// is displayed
	NSTableColumn *column1 = [[NSTableColumn alloc] initWithIdentifier:@"text"];
	[column1 setEditable:NO];
	[column1 setWidth:POPOVER_WIDTH - 2 * POPOVER_PADDING];
	
	NSTableView *tableView = [[NSTableView alloc] initWithFrame:NSZeroRect];
	[tableView setSelectionHighlightStyle:NSTableViewSelectionHighlightStyleRegular];
	[tableView setBackgroundColor:[NSColor clearColor]];
	[tableView setRowSizeStyle:NSTableViewRowSizeStyleSmall];
	[tableView setIntercellSpacing:INTERCELL_SPACING];
	[tableView setHeaderView:nil];
	[tableView setRefusesFirstResponder:YES];
	[tableView setTarget:self];
	[tableView setDoubleAction:@selector(insert:)];
	[tableView addTableColumn:column1];
	[tableView setDelegate:self];
	[tableView setDataSource:self];
	self.autocompleteTableView = tableView;
	
	NSScrollView *tableScrollView = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	[tableScrollView setDrawsBackground:NO];
	[tableScrollView setDocumentView:tableView];
	[tableScrollView setHasVerticalScroller:YES];
	
	NSView *contentView = [[NSView alloc] initWithFrame:NSZeroRect];
	[contentView addSubview:tableScrollView];
	
	NSViewController *contentViewController = [[NSViewController alloc] init];
	[contentViewController setView:contentView];;
	
	// Autocomplete popover
	self.autocompletePopover = [[NSPopover alloc] init];
	self.autocompletePopover.appearance = [NSAppearance appearanceNamed:POPOVER_APPEARANCE];
	
	self.autocompletePopover.animates = NO;
	self.autocompletePopover.contentViewController = contentViewController;
	
	// Info popover
	self.infoPopover = [[NSPopover alloc] init];

	self.matches = [NSMutableArray array];
	NSView *infoContentView = [[NSView alloc] initWithFrame:NSZeroRect];
	_infoTextView = [[NSTextView alloc] initWithFrame:NSZeroRect];
	[_infoTextView setEditable:NO];
	[_infoTextView setDrawsBackground:NO];
	[_infoTextView setRichText:NO];
	[_infoTextView setUsesRuler:NO];
	[_infoTextView setSelectable:NO];
	[_infoTextView setTextContainerInset:NSMakeSize(8, 8)];
	
	[infoContentView addSubview:_infoTextView];
	NSViewController *infoViewController = [[NSViewController alloc] init];
	[infoViewController setView:infoContentView];;

	self.infoPopover.contentViewController = infoViewController;

	self.lastPos = -1;
		
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(didChangeSelection:) name:@"NSTextViewDidChangeSelectionNotification" object:nil];
	
	// Arrays for special elements
	self.masks = [NSMutableArray array];
	self.sections = [NSArray array];
	
	NSTrackingArea *trackingArea = [[NSTrackingArea alloc] initWithRect:self.frame options:(NSTrackingMouseMoved | NSTrackingActiveAlways | NSTrackingInVisibleRect) owner:self userInfo:nil];
	[self.window setAcceptsMouseMovedEvents:YES];
	[self addTrackingArea:trackingArea];
	
	[self resetCursorRects];
}
-(void)removeFromSuperview {
	[NSNotificationCenter.defaultCenter removeObserver:self];
	[super removeFromSuperview];
}

- (void)closePopovers {
	[_infoPopover close];
	[_autocompletePopover close];
	_forceElementMenu = NO;
}

- (IBAction)showInfo:(id)sender {
	bool wholeDocument = NO;
	NSRange range;
	if (self.selectedRange.length == 0) {
		wholeDocument = YES;
		range = NSMakeRange(0, self.string.length);
	} else {
		range = self.selectedRange;
	}
		
	NSInteger words = 0;
	NSArray *lines = [[self.string substringWithRange:range] componentsSeparatedByString:@"\n"];
	NSInteger symbols = [[self.string substringWithRange:range] length];
	
	for (NSString *line in lines) {
		for (NSString *word in [line componentsSeparatedByString:@" "]) {
			if (word.length > 0) words += 1;
		}
		
	}
	[_infoTextView setString:@""];
	[_infoTextView.layoutManager ensureLayoutForTextContainer:_infoTextView.textContainer];
	
	NSString *infoString = [NSString stringWithFormat:@"Words: %lu\nCharacters: %lu", words, symbols];

	// Get number of pages / page number for selection
	if (wholeDocument) {
		NSInteger pages = [self numberOfPages];
		if (pages > 0) infoString = [infoString stringByAppendingFormat:@"\nPages: %lu", pages];
	} else {
		NSInteger page = [self getPageNumber:self.selectedRange.location];
		if (page > 0) infoString = [infoString stringByAppendingFormat:@"\nPage: %lu", page];
	}
	
	NSMutableDictionary *attributes = [[NSMutableDictionary alloc] init];
	[attributes setObject:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]] forKey:NSFontAttributeName];
	
	
	if (wholeDocument) infoString = [NSString stringWithFormat:@"Document\n%@", infoString];
	else infoString = [NSString stringWithFormat:@"Selection\n%@", infoString];
	_infoTextView.font = [NSFont systemFontOfSize:[NSFont systemFontSize]];
	_infoTextView.string = infoString;
	[_infoTextView.textStorage addAttributes:attributes range:NSMakeRange(0, [infoString rangeOfString:@"\n"].location)];
		
	[_infoTextView.layoutManager ensureLayoutForTextContainer:_infoTextView.textContainer];
	NSRect result = [_infoTextView.layoutManager usedRectForTextContainer:_infoTextView.textContainer];
	
	NSRect frame = NSMakeRect(0, 0, 200, result.size.height + 16);
	[self.infoPopover setContentSize:NSMakeSize(NSWidth(frame), NSHeight(frame))];
	[self.infoTextView setFrame:NSMakeRect(0, 0, NSWidth(frame), NSHeight(frame))];
	
	self.substring = [self.string substringWithRange:NSMakeRange(range.location, 0)];
	
	NSRect rect;
	if (!wholeDocument) {
		rect = [self firstRectForCharacterRange:NSMakeRange(range.location, 0) actualRange:NULL];
	} else {
		rect = [self firstRectForCharacterRange:NSMakeRange(self.selectedRange.location, 0) actualRange:NULL];
	}
	rect = [self.window convertRectFromScreen:rect];
	rect = [self convertRect:rect fromView:nil];
	rect.size.width = 5;
	
	[self.infoPopover showRelativeToRect:rect ofView:self preferredEdge:NSMaxYEdge];
	[self.window makeFirstResponder:self];
}

- (void)mouseDown:(NSEvent *)event {
	[self closePopovers];
	[super mouseDown:event];
}

- (NSTouchBar*)makeTouchBar {
	[NSApp setAutomaticCustomizeTouchBarMenuItemEnabled:NO];
	
	if (@available(macOS 10.15, *)) {
		NSTouchBar.automaticCustomizeTouchBarMenuItemEnabled = NO;
	}
	
	return _touchBar;
}
- (nullable NSTouchBarItem *)touchBar:(NSTouchBar *)touchBar makeItemForIdentifier:(NSTouchBarItemIdentifier)identifier
{
    if ([identifier isEqualToString:ColorPickerItemIdentifier]) {
		// What?
	}
	return nil;
}

- (void)keyDown:(NSEvent *)theEvent {
	NSInteger row = self.autocompleteTableView.selectedRow;
	BOOL shouldComplete = YES;
	
	switch (theEvent.keyCode) {
		case 51:
			// Delete
			[self closePopovers];
			shouldComplete = NO;
			
			break;
		case 53:
			// Esc
			if (self.autocompletePopover.isShown || self.infoPopover.isShown) [self closePopovers];
		
			return; // Skip default behavior
		case 125:
			// Down
			if (self.autocompletePopover.isShown) {
				[self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row+1] byExtendingSelection:NO];
				[self.autocompleteTableView scrollRowToVisible:self.autocompleteTableView.selectedRow];
				return; // Skip default behavior
			}
			break;
		case 126:
			// Up
			if (self.autocompletePopover.isShown) {
				[self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:row-1] byExtendingSelection:NO];
				[self.autocompleteTableView scrollRowToVisible:self.autocompleteTableView.selectedRow];
				return; // Skip default behavior
			}
			break;
		case 48:
			// Tab
			if (_forceElementMenu) {
				[self force:self];
				return; // skip default
			} else if (self.autocompletePopover.isShown) {
				[self insert:self];
				return; // don't insert a line-break after tab key
			} else {
				// Call delegate to handle tab press
				if ([self.delegate respondsToSelector:@selector(handleTabPress)]) {
					[(id)self.delegate handleTabPress];
					return; // skip default
				}
			}
			break;
		case 36:
			// Return
			if (self.autocompletePopover.isShown) {
				// Check whether to force an element or to just autocomplete
				if (_forceElementMenu) {
					[self force:self];
					return; // skip default
				} else if (self.autocompletePopover.isShown) {
					[self insert:self];
				}
			}
			else if (theEvent.modifierFlags) {
				NSUInteger flags = [theEvent modifierFlags] & NSEventModifierFlagDeviceIndependentFlagsMask;
				
				// Alt was pressed && autocomplete is not visible
				if (flags == NSEventModifierFlagOption && ![self.autocompletePopover isShown]) {
					_forceElementMenu = YES;
					self.automaticTextCompletionEnabled = YES;

					[self forceElement:self];
					return; // Skip defaut behavior
				}
			}
/*
		// To allow autocompletion of scene headings, we don't want to close autocomplete on space key
		case 49:
			// Space
			if (self.autocompletePopover.isShown) {
				[self.autocompletePopover close];
			}
			break;
*/
	}
	
	if (self.infoPopover.isShown) [self closePopovers];
	
	[super keyDown:theEvent];
	if (shouldComplete) {
		if (self.automaticTextCompletionEnabled) {
			[self complete:self];
		}
	}
}

// Phantom methods
- (void)handleTabPress { }


// Beat customization
- (IBAction)toggleDarkPopup:(id)sender {
	/*
	 // Nah. Saved for later use.
	 
	_nightMode = !_nightMode;
	
	if (_nightMode) {
		self.autocompletePopover.appearance = [NSAppearance appearanceNamed: NSAppearanceNameVibrantDark];
	} else {
		self.autocompletePopover.appearance = [NSAppearance appearanceNamed: NSAppearanceNameVibrantLight];
	}
	 */
}

- (void)force:(id)sender {
	if (self.autocompleteTableView.selectedRow >= 0 && self.autocompleteTableView.selectedRow < self.matches.count) {
		if ([self.delegate respondsToSelector:@selector(forceElement:)]) {
			[(id)self.delegate forceElement:[self.matches objectAtIndex:self.autocompleteTableView.selectedRow]];
		}
	}
	[self.autocompletePopover close];
	_forceElementMenu = NO;
}
- (NSInteger)getPageNumber:(NSInteger)location {
	if ([self.delegate respondsToSelector:@selector(getPageNumber:)]) {
		return [(id)self.delegate getPageNumber:location];
	}
	return 0;
}
- (NSInteger)numberOfPages {
	if ([self.delegate respondsToSelector:@selector(numberOfPages)]) {
		return [(id)self.delegate numberOfPages];
	}
	return 0;
}

- (void)insert:(id)sender {
	if (self.autocompleteTableView.selectedRow >= 0 && self.autocompleteTableView.selectedRow < self.matches.count) {
		NSString *string = [self.matches objectAtIndex:self.autocompleteTableView.selectedRow];
		NSInteger beginningOfWord = self.selectedRange.location - self.substring.length;
		NSRange range = NSMakeRange(beginningOfWord, self.substring.length);
		
		if ([self shouldChangeTextInRange:range replacementString:string]) {
			[self replaceCharactersInRange:range withString:string];
			[self didChangeText];
		}
	}
	[self.autocompletePopover close];
}

- (void)didChangeSelection:(NSNotification *)notification {
	if ((self.selectedRange.location - self.lastPos) > 1) {
		// If selection moves by more than just one character, hide autocomplete
		[self.autocompletePopover close];
	}
}

- (void)forceElement:(id)sender {
	NSInteger location = self.selectedRange.location;
	self.matches = @[@"Action", @"Scene Heading", @"Character", @"Lyrics"];
	
	self.lastPos = self.selectedRange.location;
	[self.autocompleteTableView reloadData];
	
	NSInteger index = 0;
	
	[self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
	[self.autocompleteTableView scrollRowToVisible:index];
	
	NSInteger numberOfRows = MIN(self.autocompleteTableView.numberOfRows, MAX_RESULTS);
	CGFloat height = (self.autocompleteTableView.rowHeight + self.autocompleteTableView.intercellSpacing.height) * numberOfRows + 2 * POPOVER_PADDING;
	NSRect frame = NSMakeRect(0, 0, POPOVER_WIDTH, height);
	[self.autocompleteTableView.enclosingScrollView setFrame:NSInsetRect(frame, POPOVER_PADDING, POPOVER_PADDING)];
	[self.autocompletePopover setContentSize:NSMakeSize(NSWidth(frame), NSHeight(frame))];
	
	self.substring = [self.string substringWithRange:NSMakeRange(location, 0)];
	
	NSRect rect = [self firstRectForCharacterRange:NSMakeRange(location, 0) actualRange:NULL];
	rect = [self.window convertRectFromScreen:rect];
	rect = [self convertRect:rect fromView:nil];
	
	rect.size.width = 5;
	
	[self.autocompletePopover showRelativeToRect:rect ofView:self preferredEdge:NSMaxYEdge];
}

- (void)complete:(id)sender {
	NSInteger startOfWord = self.selectedRange.location;
	for (NSInteger i = startOfWord - 1; i >= 0; i--) {
		if ([WORD_BOUNDARY_CHARS characterIsMember:[self.string characterAtIndex:i]]) {
			break;
		} else {
			startOfWord--;
		}
	}
	
	NSInteger lengthOfWord = 0;
	for (NSInteger i = startOfWord; i < self.string.length; i++) {
		if ([WORD_BOUNDARY_CHARS characterIsMember:[self.string characterAtIndex:i]]) {
			break;
		} else {
			lengthOfWord++;
		}
	}
	
	self.substring = [self.string substringWithRange:NSMakeRange(startOfWord, lengthOfWord)];
	NSRange substringRange = NSMakeRange(startOfWord, self.selectedRange.location - startOfWord);
	
	if (substringRange.length == 0 || lengthOfWord == 0) {
		// This happens when we just started a new word or if we have already typed the entire word
		[self.autocompletePopover close];
		return;
	}
	
	NSInteger index = 0;
	self.matches = [self completionsForPartialWordRange:substringRange indexOfSelectedItem:&index];
	
	if (self.matches.count > 0) {

		// Beat customization: if we have only one possible match and it's the same the user has already typed, close it
		if (self.matches.count == 1) {
			NSString *match = [self.matches objectAtIndex:0];
			if ([match localizedCaseInsensitiveCompare:self.substring] == NSOrderedSame) {
				[self.autocompletePopover close];
				return;
			}
		}
		
		self.lastPos = self.selectedRange.location;
		[self.autocompleteTableView reloadData];
		
		[self.autocompleteTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
		[self.autocompleteTableView scrollRowToVisible:index];
		
		// Make the frame for the popover. We want it to shrink with a small number
		// of items to autocomplete but never grow above a certain limit when there
		// are a lot of items. The limit is set by MAX_RESULTS.
		NSInteger numberOfRows = MIN(self.autocompleteTableView.numberOfRows, MAX_RESULTS);
		CGFloat height = (self.autocompleteTableView.rowHeight + self.autocompleteTableView.intercellSpacing.height) * numberOfRows + 2 * POPOVER_PADDING;
		NSRect frame = NSMakeRect(0, 0, POPOVER_WIDTH, height);
		[self.autocompleteTableView.enclosingScrollView setFrame:NSInsetRect(frame, POPOVER_PADDING, POPOVER_PADDING)];
		[self.autocompletePopover setContentSize:NSMakeSize(NSWidth(frame), NSHeight(frame))];
		
		// We want to find the middle of the first character to show the popover.
		// firstRectForCharacterRange: will give us the rect at the begeinning of
		// the word, and then we need to find the half-width of the first character
		// to add to it.
		NSRect rect = [self firstRectForCharacterRange:substringRange actualRange:NULL];
		rect = [self.window convertRectFromScreen:rect];
		rect = [self convertRect:rect fromView:nil];
		NSString *firstChar = [self.substring substringToIndex:1];
		NSSize firstCharSize = [firstChar sizeWithAttributes:@{NSFontAttributeName:self.font}];
		rect.size.width = firstCharSize.width;
		
		[self.autocompletePopover showRelativeToRect:rect ofView:self preferredEdge:NSMaxYEdge];
	
	} else {
		[self.autocompletePopover close];
	}
}

- (NSArray *)completionsForPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)index {
	if ([self.delegate respondsToSelector:@selector(textView:completions:forPartialWordRange:indexOfSelectedItem:)]) {
		return [self.delegate textView:self completions:@[] forPartialWordRange:charRange indexOfSelectedItem:index];
	}
	return @[];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return self.matches.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NSTableCellView *cellView = [tableView makeViewWithIdentifier:@"MyView" owner:self];
	if (cellView == nil) {
		cellView = [[NSTableCellView alloc] initWithFrame:NSZeroRect];
		NSTextField *textField = [[NSTextField alloc] initWithFrame:NSZeroRect];
		[textField setBezeled:NO];
		[textField setDrawsBackground:NO];
		[textField setEditable:NO];
		[textField setSelectable:NO];
		[cellView addSubview:textField];
		cellView.textField = textField;
		if ([self.delegate respondsToSelector:@selector(textView:imageForCompletion:)]) {
			NSImageView *imageView = [[NSImageView alloc] initWithFrame:NSZeroRect];
			[imageView setImageFrameStyle:NSImageFrameNone];
			[imageView setImageScaling:NSImageScaleNone];
			[cellView addSubview:imageView];
			cellView.imageView = imageView;
		}
		cellView.identifier = @"MyView";
	}
	
	NSMutableAttributedString *as = [[NSMutableAttributedString alloc] initWithString:self.matches[row] attributes:@{NSFontAttributeName:POPOVER_FONT, NSForegroundColorAttributeName:POPOVER_TEXTCOLOR}];
	
	if (self.substring) {
		NSRange range = [as.string rangeOfString:self.substring options:NSAnchoredSearch|NSCaseInsensitiveSearch];
		[as addAttribute:NSFontAttributeName value:POPOVER_BOLDFONT range:range];
	}
	
	[cellView.textField setAttributedStringValue:as];
	
	if ([self.delegate respondsToSelector:@selector(textView:imageForCompletion:)]) {
		//NSImage *image = [self.delegate textView:self imageForCompletion:self.matches[row]];
		//[cellView.imageView setImage:image];
	}
	
	return cellView;
}

- (NSTableRowView *)tableView:(NSTableView *)tableView rowViewForRow:(NSInteger)row {
	return [[NCRAutocompleteTableRowView alloc] init];
}

#pragma mark - Rects for masking, page breaks etc.

- (void)setMarginColor:(DynamicColor *)newColor {
	_marginColor = newColor;
}
 
- (void)drawRect:(NSRect)dirtyRect {
	NSGraphicsContext *context = [NSGraphicsContext currentContext];
	CGFloat factor = 1 / _zoomLevel;
	
	[context saveGraphicsState];
	
	// Section header backgrounds
	for (NSValue* value in _sections) {
		[self.marginColor setFill];
		NSRect sectionRect = [value rectValue];
		CGFloat width = self.frame.size.width * factor;

		NSRect rect = NSMakeRect(0, self.textContainerInset.height + sectionRect.origin.y - 7, width, sectionRect.size.height + 14);
		NSRectFillUsingOperation(rect, NSCompositingOperationDarken);
	}
	
	[context restoreGraphicsState];
	
	[NSGraphicsContext saveGraphicsState];
	[super drawRect:dirtyRect];
	[NSGraphicsContext restoreGraphicsState];

	// An array of NSRanges which are used to mask parts of the text.
	// Used to hide irrelevant parts when filtering scenes.
	if ([_masks count]) {
		for (NSValue * value in _masks) {
			NSColor* fillColor = self.backgroundColor;
			fillColor = [fillColor colorWithAlphaComponent:0.85];
			[fillColor setFill];
			
			NSRect rect = [self.layoutManager boundingRectForGlyphRange:value.rangeValue inTextContainer:self.textContainer];
			rect.origin.x = self.textContainerInset.width;
			// You say: never hardcode a value, but YOU DON'T KNOW ME, DO YOU!!!
			rect.origin.y += self.textContainerInset.height - 12;
			rect.size.width = self.textContainer.size.width;
			
			NSRectFillUsingOperation(rect, NSCompositingOperationSourceOver);
		}
	}
	
	NSFont* font = [NSFont fontWithName:@"Courier Prime" size:17];
	
	[context saveGraphicsState];
	
	DynamicColor *pageNumberColor = [[ThemeManager sharedManager] pageNumberColor];
	NSInteger pageNumber = 1;
	CGFloat rightEdge = (self.frame.size.width * factor - self.textContainerInset.width + 170);
	
	// Don't let page numbers fall out of view
	if (rightEdge + 40 > self.enclosingScrollView.frame.size.width * factor) {
		rightEdge = self.enclosingScrollView.frame.size.width * factor - self.textContainerInset.width + 72;
		
		// If it's STILL too far out, compact page numbers even more
		if (rightEdge + 50 > self.enclosingScrollView.frame.size.width * factor) {
			rightEdge = self.enclosingScrollView.frame.size.width * factor - 50;
		}
	}
	

	for (NSNumber *pageBreakPosition in self.pageBreaks) {

		NSString *page = [@(pageNumber) stringValue];
		
		// Do we want the dot after page number?
		// page = [page stringByAppendingString:@"."];
		
		NSAttributedString* attrStr = [[NSAttributedString alloc] initWithString:page attributes:@{ NSFontAttributeName: font, NSForegroundColorAttributeName: pageNumberColor }];
		
		[attrStr drawAtPoint:CGPointMake(rightEdge, [pageBreakPosition floatValue] + self.textContainerInset.height)];
				
		pageNumber++;
	}
	[context restoreGraphicsState];
}


- (void)updateSceneNumberLabels {
	[self updateSceneNumberLabelsWithTextLabels];
	//[self updateSceneNumberLabelsWithLayer];
}

- (void) updateSceneNumberLabelsWithTextLabels {
	// zoomDelegate is a misleading name, it's the Document, really
	ContinousFountainParser *parser = self.zoomDelegate.parser;
	if (!parser.outline.count) [parser createOutline];
	
	if (!self.sceneNumberLabels) self.sceneNumberLabels = [NSMutableArray array];
		
	NSInteger numberOfScenes = parser.numberOfScenes;
	NSInteger numberOfLabels = self.sceneNumberLabels.count;
	NSInteger difference = numberOfScenes - numberOfLabels;
	
	// Create missing labels for new scenes
	if (difference > 0 && self.sceneNumberLabels.count) {
		for (NSUInteger d = 0; d < difference; d++) {
			[self createLabel:nil];
		}
	}
	
	// Create labels if none are present
	if (![self.sceneNumberLabels count]) {
		[self createAllLabels];
	} else {
		NSUInteger index = 0;

		for (OutlineScene * scene in parser.scenes) {
			// We'll wrap this in an autorelease pool, not sure if it helps or not :-)
			@autoreleasepool {
				if (index >= [self.sceneNumberLabels count]) break;
				
				NSTextField * label = [self.sceneNumberLabels objectAtIndex:index];
				if (scene.sceneNumber) { [label setStringValue:scene.sceneNumber]; }
				
				NSRange characterRange = NSMakeRange([scene.line position], [scene.line.string length]);
				NSRange range = [self.layoutManager glyphRangeForCharacterRange:characterRange actualCharacterRange:nil];
				NSRect rect = [self.layoutManager boundingRectForGlyphRange:range inTextContainer:self.textContainer];
				
				rect.size.width = 20 * [scene.sceneNumber length];
				rect.origin.x = self.textContainerInset.width - 40 - rect.size.width + 10;
				
				rect.origin.y += _textInsetY;

				label.frame = rect;
				[label setFont:self.zoomDelegate.courier];
				if (![scene.color isEqualToString:@""] && scene.color != nil) {
					NSString *color = [scene.color lowercaseString];
					[label setTextColor:[BeatColors color:color]];
				} else {
					[label setTextColor:self.zoomDelegate.themeManager.currentTextColor];
				}
			
				index++;
			}
		}

		// Remove unused labels from the end of the array.
		if (difference < 0) {
			for (NSInteger d = 0; d > difference; d--) {
				// Let's just do a double check to reduce the chance of errors
				if ([self.sceneNumberLabels count] > [self.sceneNumberLabels count] - 1) {
					NSTextField * label = [self.sceneNumberLabels objectAtIndex:[self.sceneNumberLabels count] - 1];
				
					//[label performSelectorOnMainThread:@selector(removeFromSuperview) withObject:nil waitUntilDone:NO];
					[self.sceneNumberLabels removeObject:label];
					[label removeFromSuperview];
				}
			}
		}
	}
}


- (void)updateSceneNumberLabelsWithLayer {
	// Alternative scene numbering system.
	// Gives some performance advantage, but also takes a bigger hit sometimes.

	self.wantsLayer = YES;
	if (!self.zoomDelegate.parser.outline.count) [self.zoomDelegate.parser createOutline];
	
	// This is pretty fast, but I'm not sure. Still kind of hard to figure out.
	if (!_sceneNumberLabels.count || !_sceneNumberLabels) _sceneNumberLabels = [NSMutableArray array];
	
	NSInteger difference = _sceneNumberLabels.count - self.zoomDelegate.parser.scenes.count;

	// There are extra scene number labels, remove them from superlayer
	if (difference > 0) {
		for (NSInteger i = 0; i <= difference; i++) {
			[_sceneNumberLabels.lastObject removeFromSuperlayer];
			[_sceneNumberLabels removeLastObject];
		}
	}
	
	// Begin moving layers
	[CATransaction begin];
	[CATransaction setValue: (id) kCFBooleanTrue forKey: kCATransactionDisableActions];
	
	NSInteger index = 0;
	for (OutlineScene* scene in self.zoomDelegate.parser.scenes) {
		NSString *number = scene.sceneNumber;
		
		NSRange characterRange = NSMakeRange(scene.line.position, scene.line.string.length);
		NSRange range = [self.layoutManager glyphRangeForCharacterRange:characterRange actualCharacterRange:nil];
		NSRect rect = [self.layoutManager boundingRectForGlyphRange:range inTextContainer:self.textContainer];
		
		// Create frame
		rect.size.width = 90;
		rect.origin.y += self.textContainerInset.height;
		CGFloat factor = 1 / self.enclosingScrollView.magnification;
		rect.origin.x += (self.textContainerInset.width - 140) * factor;
		
		
		// Color
		NSColor *color;
		if (scene.color) [BeatColors color:scene.color];
		else color = ThemeManager.sharedManager.textColor;
			
		// Retrieve or create layer
		CATextLayer *label;
		if (_sceneNumberLabels.count > index) {
			label = [_sceneNumberLabels objectAtIndex:index];
			[label setString:number];
			[label setFrame:rect];
			[label setForegroundColor:color.CGColor];
		} else {
			label = [CATextLayer layer];
			[label setShouldRasterize:YES];
			[label setFont:@"Courier Prime"];
			[label setRasterizationScale:4.0];
			[label setFontSize:17.2];
			[label setAlignmentMode:kCAAlignmentRight];
			
			[self.layer addSublayer:label];
			[_sceneNumberLabels addObject:label];
		}

		[label setContentsScale:1 / self.enclosingScrollView.magnification];
		[label setFrame:rect];
		[label setString:number];
		[label setForegroundColor:color.CGColor];
			
		index++;
	}
	[CATransaction commit];
	[self updateLayer];
}


- (NSTextField *) createLabel: (OutlineScene *) scene {
	NSTextField * label;
	label = [[NSTextField alloc] init];
	
	if (scene != nil) {
		NSRange characterRange = NSMakeRange([scene.line position], [scene.line.string length]);
		NSRange range = [self.layoutManager glyphRangeForCharacterRange:characterRange actualCharacterRange:nil];
		
		if (scene.sceneNumber) [label setStringValue:scene.sceneNumber]; else [label setStringValue:@""];
		NSRect rect = [self.layoutManager boundingRectForGlyphRange:range inTextContainer:self.textContainer];
		rect.origin.y += _textInsetY;
		rect.size.width = 20 * [scene.sceneNumber length];
		rect.origin.x = self.textContainerInset.width - 80 - rect.size.width;
	}
	
	[label setBezeled:NO];
	[label setSelectable:NO];
	[label setDrawsBackground:NO];
	[label setFont:self.zoomDelegate.courier];
	[label setAlignment:NSTextAlignmentRight];
	[self addSubview:label];
	
	[self.sceneNumberLabels addObject:label];
	return label;
}

- (void) createAllLabels {
	ContinousFountainParser *parser = self.zoomDelegate.parser;
	
	for (OutlineScene * scene in parser.outline) {
		[self createLabel:scene];
	}
}
- (void) deleteSceneNumberLabels {
	for (NSTextField * label in _sceneNumberLabels) {
		[label removeFromSuperview];
	}
	[_sceneNumberLabels removeAllObjects];
}

#pragma mark - Mouse events

- (void)mouseMoved:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	NSPoint superviewPoint = [self.enclosingScrollView convertPoint:event.locationInWindow fromView:nil];
	//CGFloat x = event.locationInWindow.x;
	CGFloat y = event.locationInWindow.y;
	
	if ((point.x > self.textContainerInset.width &&
		 point.x < self.frame.size.width * (1 / _zoomLevel) - self.textContainerInset.width) &&
		 y < self.window.frame.size.height - 22 &&
		 superviewPoint.y < self.enclosingScrollView.frame.size.height
		) {
		[super mouseMoved:event];
	} else if (point.x > 10) {
		[super mouseMoved:event];
		[NSCursor.arrowCursor set];
	}
}

- (void)mouseExited:(NSEvent *)event {
	//[[NSCursor arrowCursor] set];
}

- (void)updateSections:(NSArray *)sections {
	_sections = sections;
}

- (void)scaleUnitSquareToSize:(NSSize)newUnitSize {
	[super scaleUnitSquareToSize:newUnitSize];
}

- (void)setInsets {
	CGFloat width = (self.enclosingScrollView.frame.size.width / 2 - _documentWidth * self.zoomDelegate.magnification / 2) / self.zoomDelegate.magnification;
	self.textContainerInset = NSMakeSize(width, _textInsetY);
	self.textContainer.size = NSMakeSize(_documentWidth, self.textContainer.size.height);
	[self resetCursorRects];
}

-(void)resetCursorRects {
	[super resetCursorRects];
}

@end
/*
 
 hyvä että ilmoitit aikeistasi
 olimme taas kahdestaan liikennepuistossa
 hyvä ettei kumpikaan itkisi
 jos katoaisit matkoille vuosiksi

 niin, kyllä elämä jatkuu ilman sua
 matkusta vain rauhassa
 me pärjäämme ilman sua.
 vaikka tuntuiskin
 tyhjältä.
 
 */
