//
//  IGKWindowController.m
//  Ingredients
//
//  Created by Alex Gordon on 23/01/2010.
//  Copyright 2010 Fileability. All rights reserved.
//

#import "IGKWindowController.h"
#import "IGKApplicationDelegate.h"
#import "IGKHTMLGenerator.h"
#import "IGKSourceListWallpaperView.h"
#import "IGKArrayController.h"
#import "IGKBackForwardManager.h"
#import "IGKPredicateEditor.h"
#import "IGKDocRecordManagedObject.h"
#import "CHSymbolButtonImage.h"

@interface IGKWindowController ()

- (void)startIndexing;
- (void)indexedAllPaths:(NSNotification *)notif;
- (void)stopIndexing;

- (void)advancedSearchDoubleAction:(id)sender;

- (void)executeSideSearch:(NSString *)query;
- (void)restoreAdvancedSearchStateIntoTwoUp:(BOOL)selectFirst;
- (void)sideSearchTableChangedSelection;

- (void)tableOfContentsChangedSelection;
- (void)registerDisplayTypeInTableView:(IGKHTMLDisplayType)type title:(NSString *)title;

- (void)loadManagedObject:(IGKDocRecordManagedObject *)mo tableOfContentsMask:(IGKHTMLDisplayTypeMask)tm;

- (void)setMode:(int)modeIndex;
- (IGKArrayController *)currentArrayController;

- (void)loadNoSelectionRecordHistory:(BOOL)recordHistory;

- (void)loadURL:(NSURL *)url recordHistory:(BOOL)recordHistory;
- (void)recordHistoryForURL:(NSURL *)url title:(NSString *)title;

- (void)setUpBackMenu;
- (void)setUpForwardMenu;

- (void)loadDocs;
- (void)loadDocIntoBrowser;
- (void)setUpForWebView:(WebView *)sender frame:(WebFrame *)frame;

- (void)reloadTableOfContents;

- (void)loadURL:(NSURL *)url recordHistory:(BOOL)recordHistory;

@end

@implementation IGKWindowController

@synthesize appDelegate;
@synthesize sideFilterPredicate;
@synthesize advancedFilterPredicate;
@synthesize selectedFilterDocset;
@synthesize shouldIndex;
@synthesize isInFullscreen;

- (id)init
{
	if (self = [super init])
	{
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(indexedAllPaths:) name:@"IGKHasIndexedAllPaths" object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(showSavingProgressSheet:) name:@"IGKWillSaveIndex" object:nil];
		
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(userDefaultsDidChange:) name:NSUserDefaultsDidChangeNotification object:nil];
		
		isInFullscreen = NO;
	}
	
	return self;
}

- (NSManagedObjectContext *)managedObjectContext
{
	return [[[NSApp delegate] valueForKey:@"kitController"] managedObjectContext];
}

- (void)backForwardManagerUpdatedLists:(id)bfm
{
	[self setUpBackMenu];
	[self setUpForwardMenu];
}

- (void)setUpBackMenu
{
	NSArray *backList = [backForwardManager backList];
	if (![backList count])
	{
		[backForwardButton setEnabled:NO forSegment:0];
		[backForwardButton setMenu:nil forSegment:0];
		return;
	}
	
	NSTimeInterval t = [NSDate timeIntervalSinceReferenceDate];
	NSMenu *newBackMenu = [[NSMenu alloc] initWithTitle:@"Back"];
	for (WebHistoryItem *item in backList)
	{
		//NSURL *url = [NSURL URLWithString:[item URLString]];
		//IGKDocRecordManagedObject *mo = [IGKDocRecordManagedObject resolveURL:url inContext:[self managedObjectContext] tableOfContentsMask:NULL];
		
		NSMenuItem *menuItem = [newBackMenu addItemWithTitle:[item title] action:@selector(backMenuItem:) keyEquivalent:@""];
		[menuItem setRepresentedObject:item];
		[menuItem setTarget:self];
		//[menuItem setImage:[mo normalIcon]];
	}
	
	[backForwardButton setMenu:newBackMenu forSegment:0];
	
	[backForwardButton setEnabled:YES forSegment:0];
}
- (void)setUpForwardMenu
{
	NSArray *forwardList = [backForwardManager forwardList];
	if (![forwardList count])
	{
		[backForwardButton setEnabled:NO forSegment:1];
		[backForwardButton setMenu:nil forSegment:1];
		return;
	}
	
	NSMenu *newForwardMenu = [[NSMenu alloc] initWithTitle:@"Forward"];
	for (WebHistoryItem *item in forwardList)
	{
		//NSURL *url = [NSURL URLWithString:[item URLString]];
		//IGKDocRecordManagedObject *mo = [IGKDocRecordManagedObject resolveURL:url inContext:[self managedObjectContext] tableOfContentsMask:NULL];
		
		NSMenuItem *menuItem = [newForwardMenu addItemWithTitle:[item title] action:@selector(forwardMenuItem:) keyEquivalent:@""];
		[menuItem setRepresentedObject:item];
		[menuItem setTarget:self];
		//[menuItem setImage:[mo normalIcon]];
	}
	
	[backForwardButton setMenu:newForwardMenu forSegment:1];
	
	[backForwardButton setEnabled:YES forSegment:1];
}
- (void)backMenuItem:(NSMenuItem *)sender
{	
	NSInteger index = [[backForwardButton menuForSegment:0] indexOfItem:sender];
	NSInteger amount = index + 1;
	
	[backForwardManager goBackBy:amount];
}
- (void)forwardMenuItem:(NSMenuItem *)sender
{	
	NSInteger index = [[backForwardButton menuForSegment:1] indexOfItem:sender];
	NSInteger amount = index + 1;
	
	[backForwardManager goForwardBy:amount];
}

- (NSString *)windowNibName
{
	return @"CHDocumentationBrowser";
}

- (void)userDefaultsDidChange:(NSNotification *)notif
{
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"IGKKeepOnAllSpaces"])
	{
		[[self window] setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
	}
	else
	{
		[[self window] setCollectionBehavior:NSWindowCollectionBehaviorDefault];
	}
}
- (void)windowDidLoad
{	
	currentModeIndex = CHDocumentationBrowserUIMode_NeedsSetup;
	[self setMode:CHDocumentationBrowserUIMode_TwoUp];
	sideSearchQuery = @"";
		
	//	[sideSearchIndicator startAnimation:self];
	
	sideSearchResults = [[NSMutableArray alloc] init];
	
	BOOL didIndex = YES;
	
	if (shouldIndex)
		[self startIndexing];
	else
	{
		didIndex = NO;
		[self loadNoSelectionRecordHistory:YES];
	}
	
	[backForwardButton setEnabled:NO forSegment:0];
	[backForwardButton setEnabled:NO forSegment:1];
	
	[searchViewTable setTarget:self];
	[searchViewTable setDoubleAction:@selector(advancedSearchDoubleAction:)];
	
	sideSortDescriptor = [NSSortDescriptor sortDescriptorWithKey:nil
													   ascending:YES
													  comparator:^NSComparisonResult (id obja, id objb)
	{
		NSString *a = [obja valueForKey:@"name"];
		NSString *b = [objb valueForKey:@"name"];
		
		NSUInteger qLength = [sideSearchQuery length];
		NSString *qlower = [sideSearchQuery lowercaseString];
		NSUInteger qlowerLength = [qlower length];

		if (qLength == 0)
			return NSOrderedAscending;
		
		NSUInteger aLength = [a length];
		NSUInteger bLength = [b length];
		
		NSInteger l1 = abs(aLength - qLength);
		NSInteger l2 = abs(bLength - qLength);
		
		if (l1 == l2)
		{
			//If l1 == l2 then attempt to see if one of them equals or starts with the substring
			
			//Case sensitive equality
			if (aLength == qLength && [a isEqual:sideSearchQuery])
				return NSOrderedAscending;
			if (bLength == qLength && [b isEqual:sideSearchQuery])
				return NSOrderedDescending;
			
			//Case insensitive equality
			NSString *alower = [a lowercaseString];
			NSUInteger alowerLength = [alower length]; //We can't use aLength since alower may be a different length to a in some locales. Probably not an issue, since identifiers won't have unicode in them, but let's not risk the crash
			
			if (alowerLength == qlowerLength && [alower isEqual:sideSearchQuery])
				return NSOrderedAscending;

			NSString *blower = [a lowercaseString];
			NSUInteger blowerLength = [alower length];
			
			if (blowerLength == qlowerLength && [blower isEqual:sideSearchQuery])
				return NSOrderedAscending;
			
			//Case sensitive starts-with
			if (aLength > qLength && [[a substringToIndex:qLength] isEqual:sideSearchQuery])
				return NSOrderedAscending;
			if (bLength > qLength && [[b substringToIndex:qLength] isEqual:sideSearchQuery])
				return NSOrderedDescending;
			
			//Case insensitive start-with
			if (alowerLength > qlowerLength && [[alower substringToIndex:qlowerLength] isEqual:qlower])
				return NSOrderedAscending;
			if (blowerLength > qlowerLength && [[blower substringToIndex:qlowerLength] isEqual:qlower])
				return NSOrderedDescending;
			
			//So neither a nor b starts with q. Now we apply prioritization. Some types get priority over others. For instance, a class > method > typedef > constant
			NSUInteger objaPriority = [[obja valueForKey:@"priority"] shortValue];
			NSUInteger objbPriority = [[objb valueForKey:@"priority"] shortValue];
			
			//Higher priorities are better
			if (objaPriority > objbPriority)
				return NSOrderedAscending;
			else if (objaPriority < objbPriority)
				return NSOrderedDescending;
			
			//Just a normal compare
			return [a localizedCompare:b];
			
		}
		else if(l1 < l2)
			return NSOrderedAscending;
		
		return NSOrderedDescending;
		
	}];
	
	[sideSearchController setMaxRows:100];
	[sideSearchController setSmartSortDescriptors:[NSArray arrayWithObject:sideSortDescriptor]];
	
	[advancedController setSmartSortDescriptors:[NSArray arrayWithObject:sideSortDescriptor]];	
	
	if ([searchViewPredicateEditor numberOfRows] > 0)
		[searchViewPredicateEditor removeRowsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, [searchViewPredicateEditor numberOfRows])] includeSubrows:YES];
	[searchViewPredicateEditor addRow:nil];
	
	[[browserWebView preferences] setDefaultFontSize:16];
	[[browserWebView preferences] setDefaultFixedFontSize:16];
	
	if (!didIndex)
	{
		[self didFinishIndexingOrLoading];
	}
	
	[self tableViewSelectionDidChange:nil];
	
	//Simulate user defaults changing
	[self userDefaultsDidChange:nil];
	
	[self setRightFilterBarShown:NO];
}
- (void)didFinishIndexingOrLoading
{	
	[docsetsController addObserver:self forKeyPath:@"arrangedObjects" options:NSKeyValueObservingOptionNew context:NULL];
	//[self performSelector:@selector(didFinishIndexingOrLoadingDelayed) withObject:nil afterDelay:0.0];	
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if ([keyPath isEqual:@"arrangedObjects"])
	{
		[self didFinishIndexingOrLoadingDelayed];
	}
}
- (void)didFinishIndexingOrLoadingDelayed
{
	NSString *selectedFilterDocsetPath = [[NSClassFromString(@"IGKPreferencesController") sharedPreferencesController] selectedFilterDocsetPath];
	if (selectedFilterDocsetPath)
	{
		for (id docset in [docsetsController arrangedObjects])
		{
			if ([[docset valueForKey:@"path"] isEqual:selectedFilterDocsetPath])
			{
				selectedFilterDocset = docset;
				
				for (NSMenuItem *m in [docsetsFilterPopupButton itemArray])
				{
					if ([m representedObject] == docset)
					{						
						[docsetsFilterPopupButton selectItem:m];
					}
				}
				
				BOOL successful = [docsetsController setSelectedObjects:[NSArray arrayWithObject:docset]];
				
				break;
			}
		}
	}
}

- (void)close
{
	if ([appDelegate hasMultipleWindowControllers])
		[[appDelegate windowControllers] removeObject:self];
	
	[super close];
}

#pragma mark UI

- (void)setMode:(int)modeIndex
{
	//If we're already in this mode, bail
	if (modeIndex == currentModeIndex)
		return;
		
	if (currentModeIndex == CHDocumentationBrowserUIMode_TwoUp)
	{
		// two-up -> browser
		if (modeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
		{
			CGFloat leftWidth = [sideSearchView frame].size.width;
						
			NSRect newFrame = [twoPaneSplitView frame];
			newFrame.origin.x = 0.0 - leftWidth - 1;
			newFrame.size.width = [contentView frame].size.width + leftWidth + 1;
			[twoPaneSplitView setEnabled:NO];

			[[twoPaneSplitView animator] setFrame:newFrame];		
		}
		
		// two-up -> search
		else if (modeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
		{
			[twoPaneView removeFromSuperview];

			[searchView setFrame:[contentView bounds]];
			[contentView addSubview:searchView];
		}
	}
	else if (currentModeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
	{
		// browser -> two-up
		if (modeIndex == CHDocumentationBrowserUIMode_TwoUp)
		{
			[[twoPaneSplitView animator] setFrame:[contentView frame]];	
			[twoPaneSplitView setEnabled:YES];
		}
		
		// browser -> search
		else if (modeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
		{
			[twoPaneView removeFromSuperview];
			
			[searchView setFrame:[contentView bounds]];
			[contentView addSubview:searchView];
		}
	}
	else if (currentModeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
	{
		// search -> two-up
		if (modeIndex == CHDocumentationBrowserUIMode_TwoUp)
		{
			[searchView removeFromSuperview];
			
			[twoPaneView setFrame:[contentView bounds]];
			[contentView addSubview:twoPaneView];
			
			[twoPaneSplitView setFrame:[contentView frame]];	
			[twoPaneSplitView setEnabled:YES];
		}
		
		// search -> browser
		else if (modeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
		{
			[searchView removeFromSuperview];
			
			[twoPaneView setFrame:[contentView bounds]];
			[contentView addSubview:twoPaneView];
			
			CGFloat leftWidth = [sideSearchView frame].size.width;
			NSRect newFrame = [twoPaneSplitView frame];
			newFrame.origin.x = 0.0 - leftWidth - 1;
			newFrame.size.width = [contentView frame].size.width + leftWidth + 1;
			[twoPaneSplitView setEnabled:NO];
			
			[twoPaneSplitView setFrame:newFrame];
		}
	}
	else if (currentModeIndex == CHDocumentationBrowserUIMode_NeedsSetup)
	{
		//Set up subviews of the two-up view
		//Main
		[twoPaneView setFrame:[contentView bounds]];
		
		//Browser
		[browserView setFrame:[[[twoPaneSplitView subviews] objectAtIndex:1] bounds]];
		[[[twoPaneSplitView subviews] objectAtIndex:1] addSubview:browserView];
		
		//Side search
		[sideSearchView setFrame:[twoPaneContentsTopView bounds]];
		[twoPaneContentsTopView addSubview:sideSearchView];
		
		//Table of contents
		//[tableOfContentsView setFrame:[[[twoPaneContentsSplitView subviews] objectAtIndex:1] bounds]];
		//[[[twoPaneContentsSplitView subviews] objectAtIndex:1] addSubview:tableOfContentsView];
		
		
		//Set up the search view
		[searchView setFrame:[contentView bounds]];
		
		
		// none -> two-up
		if (modeIndex == CHDocumentationBrowserUIMode_TwoUp || modeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
		{
			[contentView addSubview:twoPaneView];
			[twoPaneSplitView setEnabled:YES];
			
			// none -> browser
			if (modeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
			{
				CGFloat leftWidth = [twoPaneContentsTopView bounds].size.width;
				
				[twoPaneSplitView setEnabled:NO];
				
				NSRect newFrame = [twoPaneSplitView frame];
				newFrame.origin.x = - leftWidth - 1;
				newFrame.size.width = [twoPaneView frame].size.width + leftWidth + 1;
				[twoPaneSplitView setFrame:newFrame];
			}
		}
		
		//none -> search
		else if (modeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
		{
			[contentView addSubview:searchView];
		}
	}
	
	[self willChangeValueForKey:@"ui_currentModeIndex"];
	currentModeIndex = modeIndex;
	[self didChangeValueForKey:@"ui_currentModeIndex"];
	
	
	
	if (modeIndex == CHDocumentationBrowserUIMode_TwoUp)
	{
		[[sideSearchViewField window] makeFirstResponder:sideSearchViewField];
	}
	else if (modeIndex == CHDocumentationBrowserUIMode_BrowserOnly)
	{
		if ([browserWebView window])
			[[browserWebView window] makeFirstResponder:browserWebView];
		else if ([noselectionView window])
			[[noselectionView window] makeFirstResponder:noselectionView];
		else
			[[self window] makeFirstResponder:[self window]];
	}
	else if (modeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
	{
		[self closeFindPanel:nil];
		
		[[searchViewField window] makeFirstResponder:searchViewField];
	}
}

- (IBAction)executeSearch:(id)sender
{
	[self executeSearchWithString:[sender stringValue]];
}

- (IBAction)changeViewModeTagged:(id)sender
{	
	NSInteger selectedSegment = [sender tag];
	if (selectedSegment == 0)
	{
		//We use self.ui_currentModeIndex instead of [self setMode:] because we want to refetch the side search view if we're already in advanced search
		self.ui_currentModeIndex = [NSNumber numberWithInt:CHDocumentationBrowserUIMode_BrowserOnly];
	}
	else if (selectedSegment == 1)
	{
		self.ui_currentModeIndex = [NSNumber numberWithInt:CHDocumentationBrowserUIMode_TwoUp];
	}
	else if (selectedSegment == 2)
	{
		self.ui_currentModeIndex = [NSNumber numberWithInt:CHDocumentationBrowserUIMode_AdvancedSearch];
	}
}

- (void)swipeWithEvent:(NSEvent *)event
{
	if (currentModeIndex != CHDocumentationBrowserUIMode_TwoUp &&
		currentModeIndex != CHDocumentationBrowserUIMode_AdvancedSearch)
		return;
	
	float dx = [event deltaX];
	float dy = [event deltaY];
	
	//Horizontal Swipe
	if (fabsf(dx) > fabsf(dy))
	{
		//Swipe left (positive is left and negative is right - go figure)
		if (dx > 0.0)
		{
			[backForwardManager goBack:nil];
		}
		//Swipe right
		else
		{
			[backForwardManager goForward:nil];
		}
	}
}
- (IBAction)backForward:(id)sender
{
	NSInteger selectedSegment = [sender selectedSegment];
	if(selectedSegment == 0)
		[backForwardManager goBack:nil];
	else if(selectedSegment == 1)
		[backForwardManager goForward:nil];
}

- (void)loadURLWithoutRecordingHistory:(NSURL *)url
{
	[self loadURL:url recordHistory:NO];
}
- (void)loadURLRecordHistory:(NSURL *)url
{
	[self loadURL:url recordHistory:YES];
}
- (void)loadURL:(NSURL *)url recordHistory:(BOOL)recordHistory
{
	isNonFilterBarType = YES;
	
	// set default title
	[[self window] setTitle:@"Documentation"];
	
	if ([[url scheme] isEqual:@"special"] && [[url resourceSpecifier] isEqual:@"no-selection"])
	{
		//[self setBrowserActive:NO];
		[browserWebView stopLoading:nil];
		[self loadNoSelectionRecordHistory:YES];
	}
	else if ([[url scheme] isEqual:@"ingr-doc"])
	{
		NSLog(@"Load URL = %@, record history = %d", url, recordHistory);
		NSManagedObjectContext *ctx = [[[NSApp delegate] valueForKey:@"kitController"] managedObjectContext];
		
		tableOfContentsMask = IGKHTMLDisplayType_None;
		IGKDocRecordManagedObject *result = [IGKDocRecordManagedObject resolveURL:url inContext:ctx tableOfContentsMask:&tableOfContentsMask];
				
		if (result)
		{
			
			[self setBrowserActive:YES];
			[self loadManagedObject:result tableOfContentsMask:tableOfContentsMask];
			if (recordHistory)
				[self recordHistoryForURL:url title:[result valueForKey:@"name"]];
			
			
		}
		
		[self reloadTableOfContents];
	}
	else
	{
		[self loadNoSelectionRecordHistory:NO];
		[self setBrowserActive:YES];
		[browserWebView stopLoading:nil];
		[[browserWebView mainFrame] loadRequest:[NSURLRequest requestWithURL:url]];
	}
}
- (void)loadManagedObject:(IGKDocRecordManagedObject *)mo tableOfContentsMask:(IGKHTMLDisplayTypeMask)tm
{
	currentObjectIDInBrowser = [mo objectID];
	
	IGKHTMLGenerator *generator = [[IGKHTMLGenerator alloc] init];
	[generator setContext:[[[NSApp delegate] valueForKey:@"kitController"] managedObjectContext]];
	[generator setManagedObject:mo];
	[generator setDisplayTypeMask:tm];
	
	acceptableDisplayTypes = [generator acceptableDisplayTypes];
	
	NSString *html = [generator html];
	
	//Load the HTML into the webview
	[[browserWebView mainFrame] loadHTMLString:html
									   baseURL:[[NSBundle mainBundle] resourceURL]];
	
	
	// set the window title to something proper...
	NSString *docsetName = [[mo valueForKey:@"docset"] localizedUserInterfaceName];
	NSString *objectName = [mo valueForKey:@"name"];
	NSString *parentName = [[mo valueForSoftKey:@"container"] valueForKey:@"name"];
	NSString *newTitle;
	if(parentName)
	{
		newTitle = [NSString stringWithFormat:@"%@ %C %@ %C %@", docsetName, 0x203A, parentName, 0x203A, objectName];
	}
	else {
		newTitle = [NSString stringWithFormat:@"%@ %C %@", docsetName, 0x203A, objectName];
	}
	
	[[self window] setTitle:newTitle];
	
	
	[self reloadRightFilterBarTable:mo transient:[generator transientObject]];
}
- (void)recordHistoryForURL:(NSURL *)url title:(NSString *)title
{
	WebHistoryItem *item = [[WebHistoryItem alloc] initWithURLString:[url absoluteString] title:title lastVisitedTimeInterval:[NSDate timeIntervalSinceReferenceDate]];
	[backForwardManager visitPage:item];
}


@dynamic ui_currentModeIndex;

- (void)setUi_currentModeIndex:(NSNumber *)n
{	
	CHDocumentationBrowserUIMode oldMode = currentModeIndex;
	CHDocumentationBrowserUIMode newMode = [n intValue];
	
	if (newMode == CHDocumentationBrowserUIMode_BrowserOnly || 
		newMode == CHDocumentationBrowserUIMode_TwoUp)
	{
		if (oldMode == CHDocumentationBrowserUIMode_AdvancedSearch)
		{
			
			if (newMode == CHDocumentationBrowserUIMode_TwoUp)
				[self restoreAdvancedSearchStateIntoTwoUp:NO];
			else
				[self restoreAdvancedSearchStateIntoTwoUp:NO];
		}
	}
	
	[self setMode:newMode];
		
	[self loadDocs];
}
- (NSNumber *)ui_currentModeIndex
{
	return [NSNumber numberWithInt:currentModeIndex];
}

- (void)executeSearchWithString:(NSString *)query
{
	if (currentModeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
		[self executeAdvancedSearch:query];
	else
		[self executeSideSearch:query];	
}

- (void)executeSideSearch:(NSString *)query
{
	sideSearchQuery = query;
	
	if ([query length] > 0)
	{
		NSPredicate *fetchPredicate = nil;
		if (selectedFilterDocset)
			fetchPredicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ && docset == %@", query, selectedFilterDocset];
		else
			fetchPredicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@", query];
		
		[sideSearchController setPredicate:fetchPredicate];
	}
	else
	{
		[sideSearchController setPredicate:[NSPredicate predicateWithValue:NO]];
	}
	
	sideSearchController.vipObject = nil;
	
	[sideSearchController refresh];
}
- (void)executeAdvancedSearch:(NSString *)query
{
	sideSearchQuery = query;
	
	NSPredicate *predicate = nil;
	NSMutableArray *subpredicates = [[NSMutableArray alloc] initWithCapacity:2];
	
	if ([query length] > 0)
	{
		if (selectedFilterDocset)
			predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@ && docset == %@", query, selectedFilterDocset];
		else
			predicate = [NSPredicate predicateWithFormat:@"name CONTAINS[c] %@", query];
	}
	NSString *entityToFetch = [[NSString alloc] init];
	NSPredicate *predicateResults = [searchViewPredicateEditor predicateWithEntityNamed:&entityToFetch];

	if (predicateResults)
	{
		[subpredicates addObject:predicateResults];
	}
	if (predicate)
		[subpredicates addObject:predicate];
	
	
	[advancedController setEntityToFetch:entityToFetch];
	if ([subpredicates count])
		[advancedController setPredicate:[[NSCompoundPredicate alloc] initWithType:NSAndPredicateType subpredicates:subpredicates]];
	else
		[advancedController setPredicate:[NSPredicate predicateWithValue:NO]];
	
	
	[advancedController refresh];
}

- (void)startIndexing
{
	[self setRightFilterBarShown:NO];
	
	isIndexing = YES;
	
	wallpaperView = [[IGKSourceListWallpaperView alloc] initWithFrame:[[[twoPaneSplitView subviews] objectAtIndex:0] bounds]];
	[wallpaperView setAutoresizingMask:NSViewWidthSizable | NSViewHeightSizable];
	[[[twoPaneSplitView subviews] objectAtIndex:0] addSubview:wallpaperView];
	
	[sideSearchViewField setEnabled:NO];
	[sideSearchViewField setEditable:NO];
	
	[self setBrowserActive:YES];
	
	NSRect topBarFrame = [browserTopbar frame];
	topBarFrame.origin.y += topBarFrame.size.height;
	[browserTopbar setFrame:topBarFrame];
	[browserTopbar setHidden:YES];
	
	NSRect browserViewFrame = [browserSplitViewContainer frame];
	browserViewFrame.size.height += topBarFrame.size.height;
	[browserSplitViewContainer setFrame:browserViewFrame];
	
	[twoPaneSplitView setColorIsEnabled:YES];
	[twoPaneSplitView setColor:[NSColor colorWithCalibratedRed:0.166 green:0.166 blue:0.166 alpha:1.000]];
	
	[[browserWebView mainFrame] loadRequest:[NSURLRequest requestWithURL:
											 [NSURL fileURLWithPath:
											  [[NSBundle mainBundle] pathForResource:@"tictactoe" ofType:@"html"]
											  ]
											 ]];
	
	[self reloadTableOfContents];
}
- (void)showSavingProgressSheet:(NSNotification *)notif
{
	[savingProgressIndicator setUsesThreadedAnimation:YES];
	[savingProgressIndicator startAnimation:nil];
	[NSApp beginSheet:savingProgressWindow modalForWindow:[self window] modalDelegate:nil didEndSelector:NULL contextInfo:NULL];
}
- (void)indexedAllPaths:(NSNotification *)notif
{
	[NSApp endSheet:savingProgressWindow];
	[savingProgressWindow orderOut:nil];
	[savingProgressIndicator stopAnimation:nil];
	
	[self stopIndexing];
}
- (void)stopIndexing
{
	isIndexing = NO;
	
	[wallpaperView removeFromSuperview];
	
	[sideSearchViewField setEnabled:YES];
	[sideSearchViewField setEditable:YES];
	
	[twoPaneSplitView setColor:[NSColor colorWithCalibratedRed:0.647 green:0.647 blue:0.647 alpha:1.000]];
	
	[docsetsController fetch:nil];
	
	[self didFinishIndexingOrLoading];
	
	//*** Show the top bar ***
	
	//Geometry for the top bar
	NSRect topBarFrame = [browserTopbar frame];
	topBarFrame.origin.y -= topBarFrame.size.height;
	[browserTopbar setHidden:NO];
	
	//Geometry for the browser container
	NSRect browserViewFrame = [browserSplitViewContainer frame];
	browserViewFrame.size.height -= topBarFrame.size.height;
	
	//Animate
	[NSAnimationContext beginGrouping];
	
	[[browserTopbar animator] setFrame:topBarFrame];
	[[browserSplitViewContainer animator] setFrame:browserViewFrame];
	
	[NSAnimationContext endGrouping];
	
	[browserWebView stringByEvaluatingJavaScriptFromString:@"completed();"];

	
	[[self window] makeFirstResponder:sideSearchViewField];
}

- (void)setAdvancedFilterPredicate:(NSPredicate *)pred
{
	advancedFilterPredicate = pred;
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command
{
	if (control == sideSearchViewField)
	{
		if ([NSStringFromSelector(command) isEqual:@"moveUp:"])
		{
			[[self currentArrayController] selectPrevious:nil];
			return YES;
		}
		else if ([NSStringFromSelector(command) isEqual:@"moveDown:"])
		{
			[[self currentArrayController] selectNext:nil];
			return YES;
		}
		else if ([NSStringFromSelector(command) isEqual:@"insertNewline:"])
		{
			if ([self currentArrayController] == sideSearchController)
				[[browserWebView window] makeFirstResponder:browserWebView];
		}
		else if ([NSStringFromSelector(command) isEqual:@"cancelOperation:"])
		{
			
		}
	}
	
	return NO;
}

- (IBAction)changeSelectedFilterDocset:(id)sender
{
	selectedFilterDocset = [[sender selectedItem] representedObject];
	
	[[NSClassFromString(@"IGKPreferencesController") sharedPreferencesController] selectedFilterDocsetForPath:[selectedFilterDocset valueForKey:@"path"]];
	
	[self executeSearch:sideSearchViewField];
}

- (IBAction)predicateEditor:(id)sender
{	
	//Work out the new height of the rule editor
	NSUInteger numRows = [searchViewPredicateEditor numberOfRows];
	CGFloat height = numRows * [searchViewPredicateEditor rowHeight];
	
	NSView *superview = [searchViewPredicateEditorScrollView superview];
	CGFloat superviewHeight = [superview frame].size.height;
	
	const CGFloat maximumHeight = 200;
	if (height > maximumHeight)
		height = maximumHeight;
		
	NSRect predicateEditorRect = [searchViewPredicateEditorScrollView frame];
	predicateEditorRect.size.height = height;
	predicateEditorRect.origin.y = superviewHeight - height;
	
	NSRect tableRect = [searchViewTableScrollView frame];
	tableRect.size.height = superviewHeight - height;
	tableRect.origin.y = 0;
	
	[searchViewPredicateEditorScrollView setFrame:predicateEditorRect];
	[searchViewTableScrollView setFrame:tableRect];
	
	[self executeSearch:searchViewField];
}


#pragma mark -
#pragma mark Table View Delegate 

- (void)setBrowserActive:(BOOL)active
{
	currentObjectIDInBrowser = nil;
	
	if (active)
	{
		id superview = [noselectionView superview];
		if (superview)
		{
			[noselectionView removeFromSuperview];
			[browserSplitViewContainer setFrame:[noselectionView frame]];
			[superview addSubview:browserSplitViewContainer];
		}
	}
	else
	{
		// set default title
		[[self window] setTitle:@"Documentation"];
		id superview = [browserSplitViewContainer superview];
		if (superview)
		{
			[browserSplitViewContainer removeFromSuperview];
			[noselectionView setFrame:[browserSplitViewContainer frame]];
			[superview addSubview:noselectionView];
		}
		
		[self closeFindPanel:nil];
	}
}

//Table of contents datasource
- (void)reloadTableOfContents
{
	tableOfContentsTypes = [[NSMutableArray alloc] init];
	tableOfContentsTitles = [[NSMutableArray alloc] init];
	
	[[tableOfContentsPicker selectedRowIndexes] removeAllIndexes];
	[[tableOfContentsPicker selectedRowIndexes] addIndex:0];
	
	IGKHTMLDisplayTypeMask m = acceptableDisplayTypes;
	
	if (IGKHTMLDisplayTypeMaskIsSingle(acceptableDisplayTypes))
	{
		//Hide the list
	}
	else
	{
		//Show the list
		
		IGKHTMLDisplayTypeMask displayTypeMask = acceptableDisplayTypes;
		if (displayTypeMask & IGKHTMLDisplayType_All)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_All title:@"All"];//[tableOfContentsItems addObject:@"All"];
		
		if (displayTypeMask & IGKHTMLDisplayType_Overview)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_Overview title:@"Overview"];//[tableOfContentsItems addObject:@"Overview"];
		//if (displayTypeMask & IGKHTMLDisplayType_Tasks)
		//	[tableOfContentsItems addObject:@"Tasks"];
		if (displayTypeMask & IGKHTMLDisplayType_Properties)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_Properties title:@"Properties"];//[tableOfContentsItems addObject:@"Properties"];
		if (displayTypeMask & IGKHTMLDisplayType_Methods)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_Methods title:@"Methods"];//[tableOfContentsItems addObject:@"Methods"];
		if (displayTypeMask & IGKHTMLDisplayType_Notifications)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_Notifications title:@"Notifications"];//[tableOfContentsItems addObject:@"Notifications"];
		if (displayTypeMask & IGKHTMLDisplayType_Delegate)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_Delegate title:@"Delegate"];//[tableOfContentsItems addObject:@"Delegate"];
		if (displayTypeMask & IGKHTMLDisplayType_BindingListings)
			[self registerDisplayTypeInTableView:IGKHTMLDisplayType_BindingListings title:@"Bindings"];//[tableOfContentsItems addObject:@"Bindings"];
	}
	
	
	
	[tableOfContentsTableView reloadData];
	[tableOfContentsPicker reloadData];
	
	
	
	if (IGKHTMLDisplayTypeMaskIsSingle(m))
	{
		NSRect newSideSearchContainerRect = [sideSearchContainer frame];
		newSideSearchContainerRect.origin.y = 0.0;
		newSideSearchContainerRect.size.height = [[sideSearchContainer superview] frame].size.height;
		
		NSRect newTableOfContentsRect = [tableOfContentsPicker frame];
		newTableOfContentsRect.origin.y = -newTableOfContentsRect.size.height;
		
		[NSAnimationContext beginGrouping];
		
		[sideSearchContainer setFrame:newSideSearchContainerRect];
		[tableOfContentsPicker setFrame:newTableOfContentsRect];
		
		[NSAnimationContext endGrouping];
	}
	else
	{
		CGFloat contentsHeight = [tableOfContentsPicker heightToFit];
		
		NSRect newSideSearchContainerRect = [sideSearchContainer frame];
		newSideSearchContainerRect.origin.y = contentsHeight;
		newSideSearchContainerRect.size.height = [[sideSearchContainer superview] frame].size.height - contentsHeight;
		
		NSRect newTableOfContentsRect = [tableOfContentsPicker frame];
		newTableOfContentsRect.origin.y = 0.0;
		newTableOfContentsRect.size.height = contentsHeight;
		
		[NSAnimationContext beginGrouping];
		
		[[sideSearchContainer animator] setFrame:newSideSearchContainerRect];
		[[tableOfContentsPicker animator] setFrame:newTableOfContentsRect];
		
		[NSAnimationContext endGrouping];
	}
}
- (void)registerDisplayTypeInTableView:(IGKHTMLDisplayType)type title:(NSString *)title
{
	[tableOfContentsTypes addObject:[NSNumber numberWithLongLong:type]];
	[tableOfContentsTitles addObject:title];
}
- (void)reloadRightFilterBarTable:(IGKDocRecordManagedObject *)mo transient:(IGKDocRecordManagedObject *)transientObject
{	
	[rightFilterBarSearchField setStringValue:@""];
	
	isNonFilterBarType = NO;
	
	if (![mo isKindOfEntityNamed:@"ObjCAbstractMethodContainer"])
	{
		isNonFilterBarType = YES;
		[self setRightFilterBarShown:NO];
		
		rightFilterBarTaskGroupedItems = [[NSMutableArray alloc] init];
		rightFilterBarNameGroupedItems = [[NSArray alloc] init];
		rightFilterBarKindGroupedItems = [[NSMutableArray alloc] init];
		rightFilterBarItems = [[NSMutableArray alloc] init];
		
		[rightFilterBarTable reloadData];
		
		return;
	}
	
	
	//*** Task grouped items ***
	rightFilterBarTaskGroupedItems = [[NSMutableArray alloc] init];
	
	NSSortDescriptor *positionIndexSort = [[NSSortDescriptor alloc] initWithKey:@"positionIndex" ascending:YES];
	NSArray *taskgroups = [[transientObject valueForSoftKey:@"taskgroups"] sortedArrayUsingDescriptors:[NSArray arrayWithObject:positionIndexSort]];
	
	for (NSManagedObject *taskgroup in taskgroups)
	{
		NSString *name = [taskgroup valueForKey:@"name"];
		if (![name length])
			continue;
		
		NSArray *taskitems = [[taskgroup valueForKey:@"items"] sortedArrayUsingDescriptors:[NSArray arrayWithObject:positionIndexSort]];
		
		if (![taskitems count])
			continue;
		
		[rightFilterBarTaskGroupedItems addObject:name];
		
		for (NSManagedObject *taskitem in taskitems)
		{
			NSMutableDictionary *taskitemDict = [[NSMutableDictionary alloc] init];
			
			/*
			 BOOL containsInDocument = [IGKHTMLGenerator containsInDocument:mo transientObject:transientObject displayTypeMask:acceptableDisplayTypes containerName:[transientObject valueForKey:@"name"] itemName:[mo valueForKey:@"name"] ingrcode:ingrcode];
			 
			 if (containsInDocument)
				[taskitemDict setValue:[NSString stringWithFormat:@"#%@.%@", [mo valueForKey:@"name"], ingrcode] forKey:@"href"];
			 else
				[taskitemDict setValue:[mo docURL:IGKHTMLDisplayType_All] forKey:@"href"];
			*/		 
			
			[taskitemDict setValue:[IGKHTMLGenerator hrefToActualFragment:taskitem transientObject:transientObject displayTypeMask:acceptableDisplayTypes]
							forKey:@"href"];
			
			NSString *taskitemHref = [taskitem valueForKey:@"href"];
			
			NSString *taskitemName = nil;
			NSString *applecode = [IGKHTMLGenerator extractApplecodeFromHref:taskitemHref itemName:&taskitemName];
			NSString *ingrcode = [IGKHTMLGenerator applecodeToIngrcode:applecode itemName:taskitemName];
			NSString *entityName = [IGKDocRecordManagedObject entityNameFromURLComponentExtension:ingrcode];
			CHSymbolButtonImageMask iconmask = [IGKDocRecordManagedObject iconMaskForEntity:entityName isInstanceMethod:[ingrcode isEqual:@"instance-method"]];
			
			[taskitemDict setValue:[NSNumber numberWithUnsignedLongLong:iconmask] forKey:@"iconMask"];
			[taskitemDict setValue:taskitemName forKey:@"name"];				
			
			[rightFilterBarTaskGroupedItems addObject:taskitemDict];
		}
	}
	
	
	//*** Name grouped items ***
	rightFilterBarKindGroupedItems = [[NSMutableArray alloc] init];
	
	NSSortDescriptor *nameSort = [[NSSortDescriptor alloc] initWithKey:@"name" ascending:YES];
	
	NSSet *properties = [mo valueForSoftKey:@"properties"];
	
	if (properties)
	{
		NSArray *sortDescriptors = [NSArray arrayWithObject:nameSort];
		NSArray *sortedProperties = [properties sortedArrayUsingDescriptors:sortDescriptors];
		
		for (NSManagedObject *property in sortedProperties)
		{
			[rightFilterBarKindGroupedItems addObject:[self makeDictionaryFromManagedObject:property transientObject:transientObject]];
		}
	}
	
	NSSet *methods = [mo valueForSoftKey:@"methods"];
	if (methods)
	{		
		NSSortDescriptor *instanceMethodSort = [[NSSortDescriptor alloc] initWithKey:@"isInstanceMethod" ascending:YES];
		
		for (NSManagedObject *method in [methods sortedArrayUsingDescriptors:[NSArray arrayWithObjects:instanceMethodSort, nameSort, nil]])
		{
			[rightFilterBarKindGroupedItems addObject:[self makeDictionaryFromManagedObject:method transientObject:transientObject]];
		}
	}
	
	rightFilterBarNameGroupedItems = [rightFilterBarKindGroupedItems sortedArrayUsingComparator:^NSComparisonResult(id obj1, id obj2){
		
		NSString *str1 = obj1;				
		if (![obj1 respondsToSelector:@selector(characterAtIndex:)])
			str1 = [obj1 valueForKey:@"name"];
		
		NSString *str2 = obj2;
		if (![obj2 respondsToSelector:@selector(characterAtIndex:)])
			str2 = [obj2 valueForKey:@"name"];
		
		return [str1 localizedCompare:str2];
	}];
	
	rightFilterBarItems = [[self currentFilterBarAllItems] mutableCopy];
	
	[rightFilterBarTable reloadData];
}
- (NSDictionary *)makeDictionaryFromManagedObject:(IGKDocRecordManagedObject *)mo transientObject:(IGKDocRecordManagedObject *)transientObject
{
	NSMutableDictionary *taskitemDict = [[NSMutableDictionary alloc] init];
	[taskitemDict setValue:[mo valueForKey:@"name"] forKey:@"name"];				
	
	NSString *ingrcode = [mo URLComponentExtension];
	BOOL containsInDocument = [IGKHTMLGenerator containsInDocument:mo transientObject:transientObject displayTypeMask:acceptableDisplayTypes containerName:[transientObject valueForKey:@"name"] itemName:[mo valueForKey:@"name"] ingrcode:ingrcode];
	
	if (containsInDocument)
		[taskitemDict setValue:[NSString stringWithFormat:@"#%@.%@", [mo valueForKey:@"name"], ingrcode] forKey:@"href"];
	else
		[taskitemDict setValue:[mo docURL:IGKHTMLDisplayType_All] forKey:@"href"];
	
	[taskitemDict setValue:[NSNumber numberWithUnsignedLongLong:[mo iconMask]] forKey:@"iconMask"];
	
	return taskitemDict;
}
- (IBAction)rightFilterGroupByMenu:(id)sender
{
	[self rightFilterSearchField:rightFilterBarSearchField];
}
- (NSArray *)currentFilterBarAllItems
{
	CHDocumentationBrowserFilterGroupByMode groupBy = [[rightFilterBarGroupByMenu selectedItem] tag];
	if (groupBy == CHDocumentationBrowserFilterGroupByTasks)
	{
		return rightFilterBarTaskGroupedItems;
	}
	else if (groupBy == CHDocumentationBrowserFilterGroupByName)
	{			
		return rightFilterBarNameGroupedItems;
	}
	else if (groupBy == CHDocumentationBrowserFilterGroupByKind)
	{
		return rightFilterBarKindGroupedItems;
	}
	
	return nil;
}
- (IBAction)rightFilterSearchField:(id)sender
{
	//Filter rightFilterBarAllItems by name and put into rightFilterBarItems
	NSString *queryString = [sender stringValue];
	
	//If there's no query string, show all objects
	if (![queryString length])
	{
		[rightFilterBarItems setArray:[self currentFilterBarAllItems]];
		[rightFilterBarTable reloadData];
		
		return;
	}
	
	[rightFilterBarItems removeAllObjects];
	
	for (id obj in [self currentFilterBarAllItems])
	{
		//If it's an NSString
		if ([obj respondsToSelector:@selector(characterAtIndex:)])
		{
			//Check if the last object was a string
			if ([[rightFilterBarItems lastObject] respondsToSelector:@selector(characterAtIndex:)])
			{
				//If so, remove it
				[rightFilterBarItems removeLastObject];
			}
			
			//Add the new string
			[rightFilterBarItems addObject:obj];
			
			continue;
		}
		
		//Otherwise, add to the array if obj contains queryString
		if ([[obj valueForKey:@"name"] isCaseInsensitiveLike:[NSString stringWithFormat:@"*%@*", queryString]])
		{
			[rightFilterBarItems addObject:obj];
		}
	}
	
	//Check if the last object was a string
	if ([[rightFilterBarItems lastObject] respondsToSelector:@selector(characterAtIndex:)])
	{
		//If so, remove it
		[rightFilterBarItems removeLastObject];
	}
	
	[rightFilterBarTable reloadData];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	if (tableView == tableOfContentsTableView)
	{
		return [tableOfContentsTitles count];
	}
	else if (tableView == rightFilterBarTable)
	{
		return [rightFilterBarItems count];
	}
	
	return 0;
}

- (NSInteger)numberOfRowsInTableOfContents
{
	return [tableOfContentsTitles count];
}
- (id)valueForTableOfContentsColumn:(IGKTableOfContentsColumn)col row:(NSInteger)row
{
	id title = [tableOfContentsTitles objectAtIndex:row];
	
	if (col == IGKTableOfContentsTitleColumn)
	{
		return NSLocalizedString(title, @"");
	}
	
	if (col == IGKTableOfContentsIconColumn)
	{
		BOOL isSelected = [[tableOfContentsPicker selectedRowIndexes] containsIndex:row];
		NSString *imageName = [NSString stringWithFormat:@"ToC_%@%@", title, (isSelected ? @"_S" : @"")];
		return [NSImage imageNamed:imageName];
	}
	
	return nil;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == tableOfContentsTableView)
	{
		id title = [tableOfContentsTitles objectAtIndex:row];
		
		if ([[tableColumn identifier] isEqual:@"title"])
		{
			return NSLocalizedString(title, @"");
		}
		
		if ([[tableColumn identifier] isEqual:@"icon"])
		{
			BOOL isSelected = [[tableView selectedRowIndexes] containsIndex:row];
			NSString *imageName = [NSString stringWithFormat:@"ToC_%@%@", title, (isSelected ? @"_S" : @"")];
			return [NSImage imageNamed:imageName];
		}
	}
	else if (tableView == rightFilterBarTable)
	{
		id item = [rightFilterBarItems objectAtIndex:row];
		
		if ([[tableColumn identifier] isEqual:@"name"])
		{
			if ([item respondsToSelector:@selector(characterAtIndex:)])
				return item;
			
			return [item valueForKey:@"name"];
		}
		
		if ([[tableColumn identifier] isEqual:@"normalIcon"])
		{
			BOOL isSelected = NO;//[[tableView selectedRowIndexes] containsIndex:row];

			if ([item respondsToSelector:@selector(objectForKey:)])
			{
				NSNumber *iconMask = [item objectForKey:@"iconMask"];
				CHSymbolButtonImageMask iconMaskC = [iconMask unsignedLongLongValue];
				NSArray *iconMaskImages = [CHSymbolButtonImage symbolImageWithMask:iconMaskC];
				
				return (isSelected ? [iconMaskImages objectAtIndex:1] : [iconMaskImages objectAtIndex:0]);
			}
		}
		
		return nil;
	}
	
	return nil;
}	

- (void)advancedSearchDoubleAction:(id)sender
{
	[self sideSearchTableChangedSelection];
}
- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == tableOfContentsTableView)
	{
		[self tableOfContentsChangedSelection];
	}
	else if ([aNotification object] == sideSearchViewResults)
	{
		[self sideSearchTableChangedSelection];
	}
	else if ([aNotification object] == rightFilterBarTable)
	{
		[self rightFilterTableChangedSelection];
	}
}
- (BOOL)filterBarTableRowIsGroup:(NSInteger)row
{
	id currentRow = [rightFilterBarItems objectAtIndex:row];
	
	if ([currentRow respondsToSelector:@selector(characterAtIndex:)])
		return YES;
	
	return NO;
}
- (void)tableView:(NSTableView *)tableView willDisplayCell:(id)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == rightFilterBarTable)
	{
		id currentRow = [rightFilterBarItems objectAtIndex:row];
		
		if ([currentRow respondsToSelector:@selector(characterAtIndex:)])
		{
			//[cell setAlignment:NSCenterTextAlignment];
			[cell setFont:[NSFont boldSystemFontOfSize:11.5]];//[NSFont fontWithName:@"Menlo-Bold" size:12]];
			if ([cell respondsToSelector:@selector(setTextColor:)])
				[cell setTextColor:[NSColor colorWithCalibratedWhite:0.0 alpha:0.80]];
			//[(NSCell *)cell setTag:10];
		}
		else
		{
			//[cell setAlignment:NSNaturalTextAlignment];
			[cell setFont:[NSFont fontWithName:@"Menlo" size:12]];
			//[(NSCell *)cell setTag:-2];
			//[cell setTag:-2];
			
			if ([cell respondsToSelector:@selector(setTextColor:)])
				[cell setTextColor:[NSColor blackColor]];
			
		}
	}
}
- (BOOL)tableView:(NSTableView *)tableView shouldSelectRow:(NSInteger)row
{
	if (tableView == rightFilterBarTable)
	{
		id currentRow = [rightFilterBarItems objectAtIndex:row];
		
		if ([currentRow respondsToSelector:@selector(characterAtIndex:)])
		{
			return NO;
		}
	}
	
	return YES;
}
/*
- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	if (tableView == rightFilterBarTable)
	{
		id currentRow = [rightFilterBarItems objectAtIndex:row];
		
		if ([currentRow respondsToSelector:@selector(characterAtIndex:)])
		{
			return 28;
		}
	}
	
	return [tableView rowHeight];
}
 */

- (void)rightFilterTableChangedSelection
{
	NSInteger selind = [rightFilterBarTable selectedRow];
	if (selind == -1)
		return;

	id kvobject = [rightFilterBarItems objectAtIndex:selind];
	
	[self jumpToObject:kvobject];
}
- (void)jumpToObject:(id)kvobject
{
	if ([kvobject respondsToSelector:@selector(characterAtIndex:)])
	{
		
	}
	else if ([kvobject isKindOfClass:[NSManagedObject class]])
	{
		//[browserWebView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.location.hash = '%@';", [kvobject URLComponent]]]
	}
	else
	{
		NSString *href = [kvobject valueForKey:@"href"];
		
		if ([href isLike:@"#*"])
		{
			[browserWebView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.location.hash = '%@';", href]];
		}
		else
		{
			[browserWebView stringByEvaluatingJavaScriptFromString:[NSString stringWithFormat:@"window.location = '%@';", href]];
		}
	}
}

- (void)tableOfContentsChangedSelection
{
	[self loadDocIntoBrowser];
}
- (void)sideSearchTableChangedSelection
{
	//If we're indexing, don't change what page is displayed
	if (isIndexing)
		return;
	
	if ([self currentArrayController] == advancedController)
	{
		//We need to load our predicate into the side search controller
		[self restoreAdvancedSearchStateIntoTwoUp:YES];
		
		//Open in two up
		//TODO: Make which view this switched to a preference. It could switch to either Two Up or Browser Only
		[self setMode:CHDocumentationBrowserUIMode_TwoUp];
	}
	
	//If there's no selection, switch to the no selection search page
	else if ([sideSearchController selection] == nil)
	{
		[self loadNoSelectionRecordHistory:YES];
		
		return;
	}
	
	//Otherwise switch to the webview
	[self setBrowserActive:YES];
	
	[self loadDocs];
}
- (void)loadNoSelectionRecordHistory:(BOOL)recordHistory
{
	currentObjectIDInBrowser = nil;
	acceptableDisplayTypes = 0;
	
	[self setBrowserActive:NO];
	[self reloadTableOfContents];
	
	if (recordHistory)
		[self recordHistoryForURL:[NSURL URLWithString:@"special:no-selection"] title:@"No Selection"];
}
- (void)loadDocs
{
	[self loadDocIntoBrowser];
	[self reloadTableOfContents];
}
- (void)restoreAdvancedSearchStateIntoTwoUp:(BOOL)selectSelected
{	
	//Restore the predicate, etc into the side search's array controlller
	[sideSearchController setPredicate:[advancedController predicate]];
	sideSearchController.vipObject = [advancedController selection];
	
	[sideSearchViewField setStringValue:[searchViewField stringValue]];
	
	if (selectSelected)
		[sideSearchController refreshAndSelectObject:[advancedController selection] renderSelection:NO];
	else
		[sideSearchController refreshAndSelectIndex:-1 renderSelection:NO];
}

- (IGKHTMLDisplayTypeMask)tableOfContentsSelectedDisplayTypeMask
{
	__block IGKHTMLDisplayTypeMask dtmask = IGKHTMLDisplayType_None;
	
	NSIndexSet *selectedIndicies = [tableOfContentsPicker selectedRowIndexes];
	[selectedIndicies enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
		
		//Get the mask at this selected index
		if (index >= [tableOfContentsTypes count])
			return;
		
		IGKHTMLDisplayType dt = [[tableOfContentsTypes objectAtIndex:index] longLongValue];
		
		//Append it to the bitmask 
		dtmask |= dt;
	}];
	
	//A display type of none is a little unhelpful - pass all along instead
	if (dtmask == IGKHTMLDisplayType_None)
		return IGKHTMLDisplayType_All;
	
	//Otherwise use the mask as-is
	return dtmask;
}
- (IGKArrayController *)currentArrayController
{
	if (currentModeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
		return advancedController;
	else
		return sideSearchController;
}
- (void)loadDocIntoBrowser
{	
	//Generate the HTML
	if (![[self currentArrayController] selection])
		return;
	
	NSManagedObject *currentSelectionObject = [[self currentArrayController] selection];
	BOOL objectSelectionHasNotChanged = (currentObjectIDInBrowser && [[currentSelectionObject objectID] isEqual:currentObjectIDInBrowser]);
	
	IGKHTMLDisplayTypeMask dtmask = [self tableOfContentsSelectedDisplayTypeMask];
	BOOL displayTypeSelectionHasNotChanged = (tableOfContentsMask && dtmask && tableOfContentsMask == dtmask);
	
	//If the object selection hasn't change AND the display type hasn't changed, then there's no need to do anything
	if (objectSelectionHasNotChanged && displayTypeSelectionHasNotChanged)
		return;
	
	
	
	tableOfContentsMask = dtmask;
	
	[self loadManagedObject:(IGKDocRecordManagedObject *)currentSelectionObject tableOfContentsMask:[self tableOfContentsSelectedDisplayTypeMask]];
	
	[self recordHistoryForURL:[(IGKDocRecordManagedObject *)currentSelectionObject docURL:[self tableOfContentsSelectedDisplayTypeMask]] title:[currentSelectionObject pageTitle:[self tableOfContentsSelectedDisplayTypeMask]]];
}

- (IBAction)openInSafari:(id)sender
{
	[[NSWorkspace sharedWorkspace] openURL:[[[[browserWebView mainFrame] dataSource] request] URL]];
}
- (IBAction)noselectionSearchField:(id)sender
{	
	NSString *url = nil;
	
	CFStringRef query = (CFStringRef)[noselectionSearchField stringValue];
	NSString *urlencodedQuery = NSMakeCollectable(CFURLCreateStringByAddingPercentEscapes(NULL, query, NULL, CFSTR("!*'();:@&=+$,/?%#[]"), kCFStringEncodingUTF8));
	
	if ([noselectionPopupButton selectedTag] == 0) // Google
	{
		url = [NSString stringWithFormat:@"http://www.google.com/search?q=%@", urlencodedQuery];
	}
	else if ([noselectionPopupButton selectedTag] == 1) // Cocoabuilder
	{
		url = [NSString stringWithFormat:@"http://www.cocoabuilder.com/archive/search/1?q=%@&l=cocoa", urlencodedQuery];
	}
	else if ([noselectionPopupButton selectedTag] == 2) // CocoaDev
	{
		url = [NSString stringWithFormat:@"http://www.google.com/search?q=site%%3Awww.cocoadev.com&q=%@", urlencodedQuery];
	}
	else if ([noselectionPopupButton selectedTag] == 3) // Stack Overflow
	{
		url = [NSString stringWithFormat:@"http://www.google.com/search?q=site%%3Astackoverflow.com&q=%@", urlencodedQuery];
	}
	
	if (!url)
		return;
	
	/*
	id superview = [noselectionView superview];
	if (superview)
	{
		[noselectionView removeFromSuperview];
		[browserSplitViewContainer setFrame:[noselectionView frame]];
		[superview addSubview:browserSplitViewContainer];
	}
	 */
	[self setBrowserActive:YES];
	
	[self loadURL:[NSURL URLWithString:@"about:blank"] recordHistory:NO];
	[self loadURL:[NSURL URLWithString:url] recordHistory:YES];
	//[[browserWebView mainFrame] loadRequest:[NSURLRequest requestWithURL:[NSURL URLWithString:url]]];
}

- (void)webView:(WebView *)sender runJavaScriptAlertPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
	NSAlert *alert = [NSAlert alertWithMessageText:message defaultButton:@"OK" alternateButton:@"" otherButton:@"" informativeTextWithFormat:@""];
	[alert beginSheetModalForWindow:[self window] modalDelegate:nil didEndSelector:nil contextInfo:nil];
}
- (BOOL)webView:(WebView *)sender runJavaScriptConfirmPanelWithMessage:(NSString *)message initiatedByFrame:(WebFrame *)frame
{
	NSAlert *alert = [NSAlert alertWithMessageText:message defaultButton:@"OK" alternateButton:@"" otherButton:@"" informativeTextWithFormat:@""];
	NSInteger r = [alert runModal];
	
	if (r == NSAlertDefaultReturn)
		return YES;
	return NO;
}
/*
- (NSString *)webView:(WebView *)sender runJavaScriptTextInputPanelWithPrompt:(NSString *)prompt defaultText:(NSString *)defaultText initiatedByFrame:(WebFrame *)frame;
{
	//FIXME: Implement JavaScript input() in webview
	return @"";
}
*/

- (NSURLRequest *)webView:(WebView *)sender resource:(id)identifier willSendRequest:(NSURLRequest *)request redirectResponse:(NSURLResponse *)redirectResponse fromDataSource:(WebDataSource *)dataSource
{
	NSURL *url = [request URL];
	
	if ([[[[request URL] host] lowercaseString] isEqual:@"ingr-doc"])
	{
		NSArray *comps = [[url path] pathComponents];
		if ([comps count] > 3)
		{
			NSArray *newcomps = [[NSArray arrayWithObject:@"/"] arrayByAddingObjectsFromArray:[comps subarrayWithRange:NSMakeRange(2, [comps count] - 2)]];
			NSURL *newURL = [[NSURL alloc] initWithScheme:@"ingr-doc" host:[comps objectAtIndex:1] path:[NSString pathWithComponents:newcomps]];
			
			[self performSelector:@selector(loadURLRecordHistory:) withObject:newURL afterDelay:0.0];
			return nil;
		}
	}
	else if ([[[[request URL] host] lowercaseString] isEqual:@"ingr-link"])
	{
		NSArray *comps = [[url path] pathComponents];
		if ([comps count] == 2)
		{
			NSString *term = [comps objectAtIndex:1];
						
			NSFetchRequest *fetch = [[NSFetchRequest alloc] init];
			[fetch setPredicate:[NSPredicate predicateWithFormat:@"name=%@", term]];
			[fetch setEntity:[NSEntityDescription entityForName:@"DocRecord" inManagedObjectContext:[self managedObjectContext]]];
			
			NSArray *items = [[self managedObjectContext] executeFetchRequest:fetch error:nil];
			for (id item in items)
			{
				[self performSelector:@selector(loadURLRecordHistory:) withObject:[item docURL:IGKHTMLDisplayType_All] afterDelay:0.0];
				break;
			}
			
			/*
			for (id kvobject in rightFilterBarKindGroupedItems)
			{
				if ([[kvobject valueForKey:@"name"] isEqual:term])
				{
					NSString *url = [NSString stringWithFormat:@"ingr-doc://%@/%@"];
					[self performSelector:@selector(loadURLRecordHistory:) withObject:newURL afterDelay:0.0];
				}
			}
			 */
		}
		
		return nil;
	}
	
	return request;
}
- (void)webView:(WebView *)sender didStartProvisionalLoadForFrame:(WebFrame *)frame
{
	[self setUpForWebView:sender frame:frame];
}
- (void)webView:(WebView *)sender didReceiveServerRedirectForProvisionalLoadForFrame:(WebFrame *)frame
{
	[self setUpForWebView:sender frame:frame];
}
- (void)webView:(WebView *)sender didCommitLoadForFrame:(WebFrame *)frame
{
	[self setUpForWebView:sender frame:frame];
}
- (void)webView:(WebView *)sender didReceiveTitle:(NSString *)title forFrame:(WebFrame *)frame
{
	if (![[[[frame dataSource] request] URL] isEqual:[NSURL URLWithString:@"about:blank"]])
		[self recordHistoryForURL:[[[frame dataSource] request] URL] title:title];
	
	[self setUpForWebView:sender frame:frame];
	
	if ([title length]) [[self window] setTitle:title];
}
- (void)webView:(WebView *)sender didFinishLoadForFrame:(WebFrame *)frame
{
	[self setUpForWebView:sender frame:frame];
}
- (void)setUpForWebView:(WebView *)sender frame:(WebFrame *)frame
{
	if (sender != browserWebView || frame != [browserWebView mainFrame])
		return;
	
	//[self setBrowserActive:YES];
	
	BOOL rightFilterBarIsShown = NO;
	
	NSURL *url = [[[frame dataSource] request] URL];
	if (!url || [[url scheme] isEqual:@"file"])
	{
		[urlField setStringValue:@""];
		
		NSRect r = [browserToolbar frame];
		[browserToolbar setFrame:NSMakeRect(0, -r.size.height, r.size.width, r.size.height)];

		NSRect r2 = [browserWebViewContainer frame];
		[browserWebView setFrame:NSMakeRect(0, 0, r2.size.width, r2.size.height/* - [browserTopbar frame].size.height*/)];
		
		NSURL *mainURL = [[[frame dataSource] request] mainDocumentURL];
		if ([[mainURL lastPathComponent] isEqual:@"Resources"])
		{
			if (![[NSUserDefaults standardUserDefaults] boolForKey:@"IGKRightFilterBarIsHidden"])
			{
				rightFilterBarIsShown = YES;
			}
		}
	}
	else
	{
		[urlField setStringValue:[url absoluteString]];
		
		NSRect r = [browserToolbar frame];
		[browserToolbar setFrame:NSMakeRect(0, 0, r.size.width, r.size.height)];
		
		NSRect r2 = [browserWebViewContainer frame];
		[browserWebView setFrame:NSMakeRect(0, r.size.height, r2.size.width, r2.size.height - r.size.height/* - [browserTopbar frame].size.height*/)];
	}
	
	
	//Hide or show the filter bar, but only if the user hasn't explicitly hidden it
	BOOL userHasHiddenRightFilterBar = [[NSUserDefaults standardUserDefaults] boolForKey:@"rightFilterBarIsHidden"];
	
	if (userHasHiddenRightFilterBar || isNonFilterBarType)
		[self setRightFilterBarShown:NO];
	else
		[self setRightFilterBarShown:rightFilterBarIsShown];
}
- (IBAction)toggleRightFilterBar:(id)sender
{
	BOOL shown = ![self rightFilterBarShown];
	
	if ([self isInValidStateForRightFilterBar])
		[self setRightFilterBarShown:shown];
	
	[[NSUserDefaults standardUserDefaults] setBool:!shown forKey:@"rightFilterBarIsHidden"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}
- (BOOL)rightFilterBarShown
{
	return ([rightFilterBarView superview] != nil);
}
- (void)setRightFilterBarShown:(BOOL)shown
{
	NSView *sideview = [[browserSplitView subviews] objectAtIndex:1];
	
	if (shown)
	{
		
		NSRect r = [browserSplitView frame];
		r.size.width = [[browserSplitView superview] frame].size.width;
		[browserSplitView setFrame:r];
		[browserSplitView setEnabled:YES];
		
		if (![rightFilterBarView superview])
		{
			[rightFilterBarView setFrame:[sideview bounds]];
			[sideview addSubview:rightFilterBarView];
		}
	}
	else
	{
		NSRect r = [browserSplitView frame];
		r.size.width = [[browserSplitView superview] frame].size.width + [[[browserSplitView subviews] objectAtIndex:1] frame].size.width + 1;// + [browserSplitView dividerThickness];
		[browserSplitView setFrame:r];
		[browserSplitView setEnabled:NO];
		
		if ([rightFilterBarView superview])
		{
			[rightFilterBarView removeFromSuperview];
		}
	}
}

- (IBAction)toggleFullscreen:(id)sender
{
	
	
	
	NSMutableDictionary *fsOptions = [[NSMutableDictionary alloc] init];
	NSInteger presentationOptions = (NSApplicationPresentationAutoHideDock|NSApplicationPresentationAutoHideMenuBar);
	[fsOptions setObject:[NSNumber numberWithInt:presentationOptions] forKey:NSFullScreenModeApplicationPresentationOptions];
	[fsOptions setObject:[NSNumber numberWithBool:NO] forKey:NSFullScreenModeAllScreens];
	
	
	if(isInFullscreen)
	{
		[[[NSApp delegate] kitController] setFullscreenWindowController:nil];
		[[[self window] contentView] exitFullScreenModeWithOptions:fsOptions];
		[[self window] makeKeyAndOrderFront:sender];
		isInFullscreen = NO;
	}
	else 
	{
		if(![[[NSApp delegate] kitController] fullscreenWindowController])
		{
			[[[NSApp delegate] kitController] setFullscreenWindowController:self];
			[[[self window] contentView] enterFullScreenMode:[[self window] screen] 
											 withOptions:fsOptions];
			[[self window] orderOut:sender];
		
			isInFullscreen = YES;
		}
		else {
			// noooooooooo!
			return;
		}

	}

}


#pragma mark Search Timeout

- (void)arrayControllerTimedOut:(IGKArrayController *)ac
{
	if (ac == sideSearchController)
		[sideSearchIndicator startAnimation:nil];
}
- (void)arrayControllerFinishedSearching:(IGKArrayController *)ac
{
	if (ac == sideSearchController)
		[sideSearchIndicator stopAnimation:nil];
}

#pragma mark Find

- (void)windowDidResize:(NSNotification *)notification
{
	[self relayoutFindPanel];
}
- (void)viewResized:(id)resizedView
{
	[self relayoutFindPanel];
}

- (IBAction)doFindPanelAction:(id)sender
{
	if (![self isInValidStateForFindPanel])
		return;
	
	[self relayoutFindPanel];
	
	[[self window] addChildWindow:findWindow ordered:NSWindowAbove];
	[findWindow setParentWindow:[self window]];
	[[[[findWindow contentView] subviews] lastObject] viewDidMoveToParentWindow:[self window]];
	[findWindow makeKeyAndOrderFront:nil];
	[[self window] makeMainWindow];
}
- (IBAction)closeFindPanel:(id)sender
{
	[[self window] removeChildWindow:findWindow];
	[findWindow close];
}

- (IBAction)findPanelSearchField:(id)sender
{
	[self findPanelNext:sender];
}
- (IBAction)findPanelSegmentedControl:(id)sender
{
	if ([sender selectedSegment] == 1)
	{
		[self findPanelNext:sender];
	}
	else
	{
		[self findPanelPrevious:sender];
	}
}
- (IBAction)findPanelPrevious:(id)sender
{
	if (![self isInValidStateForFindPanel])
		return;
	
	[browserWebView searchFor:[findSearchField stringValue] direction:NO caseSensitive:NO wrap:YES];
}
- (IBAction)findPanelNext:(id)sender
{
	if (![self isInValidStateForFindPanel])
		return;
	
	[browserWebView searchFor:[findSearchField stringValue] direction:YES caseSensitive:NO wrap:YES];
}

- (BOOL)isInValidStateForFindPanel
{
	if (![browserWebView window])
	{
		[self closeFindPanel:self];
		return NO;
	}
	if (currentModeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
	{
		[self closeFindPanel:self];
		return NO;
	}
	
	return YES;
}
- (BOOL)isInValidStateForRightFilterBar
{
	if (![browserWebView window] || isNonFilterBarType || currentModeIndex == CHDocumentationBrowserUIMode_AdvancedSearch)
	{
		[self setRightFilterBarShown:NO];
		return NO;
	}
	
	return YES;
}

- (BOOL)validateUserInterfaceItem:(id <NSValidatedUserInterfaceItem>)anItem
{
	if ([anItem action] == @selector(doFindPanelAction:) || [anItem action] == @selector(findPanelNext:) || [anItem action] == @selector(findPanelPrevious:))
	{
		return [self isInValidStateForFindPanel];
	}
	
	if ([anItem action] == @selector(toggleRightFilterBar:))
	{
		return [self isInValidStateForRightFilterBar];
	}
	
	return YES;
}

- (void)relayoutFindPanel
{
	if (![self isInValidStateForFindPanel])
		return;
	
	NSRect newFindViewFrame = [findView frame];
	newFindViewFrame.origin.y = [browserWebViewContainer frame].size.height - newFindViewFrame.size.height + 1;
	newFindViewFrame.origin.x = [browserWebViewContainer frame].size.width - newFindViewFrame.size.width - 20.0 - 15.0;
	
	NSRect webViewConvertedFrame = [browserWebView convertRect:[browserWebView bounds] toView:[[self window] contentView]];
	
	NSRect newFrame = [findWindow frame];
	newFrame.origin = [[self window] frame].origin;
	newFrame.origin.y += [browserWebViewContainer frame].size.height - newFrame.size.height + 1;
	newFrame.origin.x += NSMaxX(webViewConvertedFrame) - 20.0 - 15.0 - newFindViewFrame.size.width; //[browserWebViewContainer frame].size.width - newFindViewFrame.size.width - 20.0 - 15.0 + [[self window] frame].size.width - [browserSplitView frame].size.width;
	
	NSRect stepperFrame = [findBackForwardStepper frame];
	stepperFrame.size.height = 20.0;
	[findBackForwardStepper setFrame:stepperFrame];
	
	[findWindow setFrame:newFrame display:YES];
}

@end
