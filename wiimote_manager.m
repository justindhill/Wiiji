//
//  wiimote_manager.m
//  wiipad
//
//  Created by Taylor Veltrop on 3/26/08.
//  Copyright 2008 Taylor Veltrop. All rights reserved.
//  Read COPYRIGHT.txt for legal info.
//  See ChangeLog.txt as well.
//

/**  Design synopsis to help you get acquainted **
 *
 * This program accompanies the virtual HID driver.
 * The virtual HID driver automatically instantiates for each wii remote it sees connecting to the system.
 * But the kernel-land drivers arent alowed to (and shouldnt) talk to the bluetooth devices directly.
 * But we need a kernel-land counterpart to provide nice systemwide HID support.
 * This program connects to the wii remotes, and maintains a list, and connects to their respective kernel virtual driver counterparts.
 * It then gets data from the wii remotes and sends it to its driver as 2 or 3 numbers: the button/joystick #, and its value(s).
 *
 * Note: HID is coded so that the Dpads are bound to x-y axis.
 * Note: HID bindings of the wii classic controller and the wii remote overlap wherever possible.  This should/could be changed to an optional user setting.
 * Note: The keyboard emulation is meant as a fall-back.  The Joysticks don't currently map to it, but will.  I want the joysticks to map X amount of degrees per key defined by the user. Then we arent limited to just 4 or 8 way. (in advanced settings put the number of directions in, then in the keyboard setup spot it'll automatically use the new data.
*/

/* Project todo list:
 TODO: STRUCTURE
 0 put the wiimote_types.h file into the framework! clean up the framework more!
 1 diversify into separate objects: Create WiiRemoteController, rename this object to AppController, Create SettingsData, ... (As per Apples MVC guidelines)
 2 make separate sourcefile for the static data, redirect datasource delegates there (As per Apples MVC guidelines)
 3 Version 1.1's sudden added support for 10.4 uglified the code! Do massive cleanups.

 TODO: BUGS
 1 when we connect to our virtualhid kext: make sure that it exists and is the right version; recomend to reinstall if not the right version
 2 while menu open: the menu-bar item doesn't animate and menu doesnt redraw contents
 3 Bluetooth mouse gets choppy sometimes after connect (framework)
 4 Better preferences window
 5 Real help guide
 6 wiimotes dont always connect, especcialy PPC (framework or kernel)

 TODO: FEATURES
 1 analog joysticks to support keyboard controls
 2 user can choose which wiimote elements redirect to which HID elements
 3 motion sensing
 4 ir sensing
 5 mouse control (accel mode, rotation mode, IR mode)
 6 CC analog button -> rudder/throttle support
 7 creation of virtual keyboards and mouses
 8 option to rotate axis of wiimote d-pad				(make advanced preferences tab)
 9 option to flip verticle axis
 10 User calibration?, save calibration data between uses... possible?
 11 DPad in hid.
 12 Balance board as joystick.
 13 auto Calibration of max min and center (framework <- the base to do so is there, but unused/untested)
 14 Joypad to keyboard
 15 Application modes, such as paintbrush, presentation, desktop, web, etc.
 16 Japanese localization
 17 No limit to the # of wiimotes connected, and dynamicly built menu list of wiimotes
 18 Advanced user feature to set length of query, also quering options such as continuous vs one-shot syncing.
 
 Should the framework contain the virtualHID handling?  It may be nice to have the user (and this application) in between the two to maintain more flexible customization. Separate also keeps the workload nicely separated, but I dont think they are really working on the framework so much these days.
 Should the framework go InTo virtualHID?
*/

#import "wiimote_manager.h"

#define desiredVirtualHIDVersion	@"1.1"
#define prefHelpString @"Click on a row in the above table to edit it."

// these indices corespond to wiimote_types.h
char buttonStrings[WiiNumberOfButtons][16] = {
	"Remote 1", "Remote 2", "Remote A", "Remote B", "Remote -", "Remote Home", "Remote +",  "Remote Up", "Remote Down", "Remote Left", "Remote Right",
	"Nunchuck Z", "Nunchuck C",
	"Classic Y", "Classic X", "Classic A", "Classic B", "Classic -", "Classic Home", "Classic +", "Classic Left", "Classic Right", "Classic Down", "Classic Up",     "Classic L", "Classic R", "Classic zL", "Classic zR"
};

#define numEmulatedKeys 98
// the indices of this corespond to the nstable for the prefs
char keyStrings[numEmulatedKeys][16] = {
	"a", "b", "c", "d", "e", "f", "g", "h", "i", "j",
    "k", "l", "m", "n", "o", "p", "q", "r", "s", "t",
    "u", "v", "w", "x", "y", "z",
	"0", "1", "2", "3", "4", "5", "6", "7", "8", "9",	
	"-", "+", "`", "[", "]", ";", "'", ",", ".", "/","\\",
    
	"Space", "Return", "Delete", "Tab", "Esc", "Caps Lock",
    "Num Lock", "Scroll Lock", "Pause", "Backspace", "Insert",
	"Cursor Up", "Cursor Down", "Cursor Left", "Cursor Right",
    "Page Up", "Page Down", "Home", "End",
    
	"KP 0", "KP 1", "KP 2", "KP 3", "KP 4", "KP 5", "KP 6",
    "KP 7", "KP 8", "KP 9", "KP Enter", "KP .", "KP +", "KP -", "KP *", "KP /",
    
	"F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", 
	"Shift", "Ctrl", "Option", "Command"
};

// the indices of this corespond to the nstable for the prefs
UInt8 keyCodes[numEmulatedKeys] = {
	  0, 11,  8,  2, 14,  3,  5,  4, 34, 38, 40, 37, 46, 45, 31, 35, 12, 15,  1, 17, 32,  9, 13,  7, 16,  6,  
	 29, 18, 19, 20, 21, 23, 22, 26, 28, 25,
	 27, 24, 10, 33, 30, 41, 39, 43, 47, 44, 42, 
	 49, 36,117, 48, 53, 57, 71,107,113, 51,114,
	126,125,123,124,116,121,115,119,
	 82, 83, 84, 85, 86, 87, 88, 89, 91, 92, 76, 65, 69, 78, 67, 75,
	122,120, 99,118, 96, 97, 98,100,101,109,103,111,
	 56, 59, 58, 55
};

// it would be more convinient to use an nsarray here, but too slow for the buttonChanged function
int bindings[maxNumWiimotes][WiiNumberOfButtons] = {
	{  0, 11,  8,  2, 14,  3,  5,  4, 34, 38, 40, -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1 }, 
	{ 37, 46, 45, 31, 35, 12, 15,  1, 17, 32,  9, -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1 },
	{ -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1 },
	{ -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1, -1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1 }
};

@implementation wiimote_manager

#pragma mark - Life cycle
- (id)init
{
	_isUsingKBEmu = _isVirtualHIDOpen = _isSettingPreferences = NO;
	
	if (!(_wii_discovery = [[WiiRemoteDiscovery alloc] init])) {
		NSRunCriticalAlertPanel(@"Can't Initialize", 
					@"Wiiji cant initialize discovery.\nPerhaps you don't have bluetooth hardware.",
					@"OK", nil, nil);
	}
	else {
		[_wii_discovery setDelegate:self];
	}
	
	int i;
	for (i = 0; i < maxNumWiimotes; i++)  {
		_service[i] = /*NULL*/ 0;
		_wiimote[i] = nil;
	}
	
	return self;
}

- (void) cleanUp
{
	int i;
	for (i=0; i < maxNumWiimotes; i++) {
		if (_wiimote[i] != nil) {
			[_wiimote[i] closeConnection]; 
		}
	}

	if (_wii_discovery != nil) {
		if ([_wii_discovery isDiscovering]) {
			[_wii_discovery close];
		}
	}
	
	[self closeVirtualDriver];
}



-(void)awakeFromNib
{
	int i;
	[[NSNotificationCenter defaultCenter] addObserver:self
											selector:@selector(expansionPortChanged:)
											name:@"WiiRemoteExpansionPortChangedNotification"
											object:nil];

	NSDictionary* info;
	NSString    * path = nil;
	ProcessSerialNumber psn = {0, kNoProcess};
	// get the path to our app
	while (!path && !GetNextProcess(&psn)) {	
		info = (__bridge NSDictionary *)ProcessInformationCopyDictionary(&psn, kProcessDictionaryIncludeAllInformationMask);
		if ([@"com.veltrop.taylor.Wiiji" isEqualTo:[info objectForKey:(NSString *)kCFBundleIdentifierKey]]) {
			path = [[info valueForKey:(NSString *)kCFBundleExecutableKey] copy];
		}
	}

	if (path) {
		NSString* newpath = [[[path stringByDeletingLastPathComponent] stringByDeletingLastPathComponent] copy];

		icons[0] = [[NSImage alloc] initWithContentsOfFile:[newpath stringByAppendingString:@"/Resources/wiijoy_icon_0.png"]];
		icons[1] = [[NSImage alloc] initWithContentsOfFile:[newpath stringByAppendingString:@"/Resources/wiijoy_icon_1.png"]];
		icons[2] = [[NSImage alloc] initWithContentsOfFile:[newpath stringByAppendingString:@"/Resources/wiijoy_icon_12.png"]];
		icons[3] = [[NSImage alloc] initWithContentsOfFile:[newpath stringByAppendingString:@"/Resources/wiijoy_icon_2.png"]];
		
		[[NSUserDefaults standardUserDefaults] registerDefaults:[NSDictionary dictionaryWithContentsOfFile:[newpath stringByAppendingString:@"/Resources/com.veltrop.taylor.Wiiji.defaults.plist"]]];
	}
	else {
		NSRunCriticalAlertPanel(@"Can't Initialize", 
					@"Wiiji cant initialize path string.\nDefaults and icons unavailable.",
					@"OK", nil, nil);
	}

	NSStatusBar *bar = [NSStatusBar systemStatusBar];
	wii_menu = [bar statusItemWithLength:35];
    [wii_menu setMenu:self.statusBarMenu];

	if (!icons[0])
		[wii_menu setTitle: @"Wii"];
	[wii_menu setImage:icons[0]];
		
	_isUsingKBEmu = [self.KBEnabledButton state] == NSOnState;
	[self setTable:self.keyTable isEnabled:_isUsingKBEmu];
	if (_isUsingKBEmu)
		[self.prefHelpText setStringValue:prefHelpString];
	else 
		[self.prefHelpText setStringValue:@""];
		
	[self loadKeyBindings];

	for (i = 0; i < maxNumWiimotes; i++) {
		NSMenuItem* item = [self.mainMenu itemWithTag:i+500];
		if (item) {
			[item setEnabled:NO];
			[item setState:NSOffState];
		}
	}
	
	if (_wii_discovery != nil)
		[_wii_discovery start];
}

- (void) dealloc
{
	[self cleanUp];
}

- (void)applicationWillTerminate:(NSNotification *)aNotification
{
	//NSLog(@"applicationWillTerminate");
	[self cleanUp];
}

#pragma mark - Preferences
- (void) saveKeyBindings
{
	int i,j;
	NSMutableArray* saveData = [NSMutableArray arrayWithCapacity:(maxNumWiimotes * WiiNumberOfButtons)];
	for (i = 0; i < maxNumWiimotes; i++) {
		for (j = 0; j < WiiNumberOfButtons; j++) {
			[saveData addObject:[NSNumber numberWithInt:bindings[i][j]]];
		}
	}
	
	NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
	[defs setObject:saveData forKey:@"Bindings"];
	[defs synchronize];
}

- (void) loadKeyBindings
{
	NSArray* loadData = [[NSUserDefaults standardUserDefaults] arrayForKey:@"Bindings"];
	int i,j;
	if (loadData != nil) {
		for (i = 0; i < maxNumWiimotes; i++) {
			for (j = 0; j < WiiNumberOfButtons; j++) {
				bindings[i][j] = [[loadData objectAtIndex:(i * WiiNumberOfButtons + j)] intValue];
			}
		}
		[self.keyTable reloadData];
	}
}



#pragma mark -
#pragma mark GUI Delegates, DataSources, CallBacks, etc.
- (void)tick
{
	static int i = 0;
	NSImage *img = icons[i];
	[wii_menu setImage:img];
	i++;
	if (i >= 4)
		i = 0;
}

- (IBAction)tryAgain:(id)sender
{
	if (_wii_discovery != nil) {
		if ([_wii_discovery isDiscovering]) {
			[_wii_discovery close];
		}
		else {
			[_wii_discovery start];
		}
	}
}

- (IBAction)stopAction:(id)sender;
{
    [_wii_discovery stop];
}

- (IBAction)disconnect:(id)sender
{
	int the_id = [sender tag] - 500;
	if (the_id >= 0 && the_id < maxNumWiimotes) {
		if (_wiimote[the_id]) {
			[_wiimote[the_id] closeConnection];
			_wiimote[the_id] = nil;
		}
	}
}

- (IBAction)setIsUsingKBEmu:(id)sender
{
	if (sender == self.KBEnabledButton) {
		[self.keyTable selectRowIndexes:nil byExtendingSelection:NO];
		_isSettingPreferences = NO;
		if ([self.KBEnabledButton state] == NSOnState) {
			[self setTable:self.keyTable isEnabled:YES];
			[self.prefHelpText setStringValue:prefHelpString];
			_isUsingKBEmu = YES;			
		} else {
			[self setTable:self.keyTable isEnabled:NO];
			[self.prefHelpText setStringValue:@""];
			_isUsingKBEmu = NO;
		}
	}
}

- (IBAction)setIsUsingVirtualHID:(id)sender
{
	if (sender == self.HIDEnabledButton) {
		if ([self.HIDEnabledButton state] == NSOnState) {
			int i;
			for (i=0; i < maxNumWiimotes; i++) {
				if (_wiimote[i] != NULL)
					[self syncVirtualDrivers];
			}
		} else {
			[self closeVirtualDriver];
		}
	}
}

// as of tiger, you cant simply enable/disable table views and their contents, so this is going to be ugly...
- (void)setTable:(NSTableView*)tableView isEnabled:(BOOL)enabled
{
	NSArray* columns = [tableView tableColumns];
	NSEnumerator* columnsEnumerator = [columns objectEnumerator];
	NSTableColumn* aColumn = nil;
	NSColor* color;
	if (enabled)
		color = [NSColor controlTextColor];
	else
		color = [NSColor disabledControlTextColor];
	while ((aColumn = [columnsEnumerator nextObject])) {
		[[aColumn headerCell] setEnabled:enabled];
		[[aColumn dataCell] setEnabled:enabled];
		[[aColumn dataCell] setTextColor:color];
	}
	[tableView setEnabled:enabled];
	[tableView reloadData];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(int)rowIndex
{
	if (aTableView == self.keyTable) {
		int colIndex = [[aTableColumn identifier]intValue];
		if (colIndex == 0) {
			return [NSString stringWithCString:keyStrings[rowIndex] encoding:NSUTF8StringEncoding];
		}
		else if (colIndex == 1) {
			int key_code = keyCodes[rowIndex];
			int i,j;
			for (i = 0; i < maxNumWiimotes; i++) {
				for (j = 0; j < WiiNumberOfButtons; j++) {
					if (bindings[i][j] ==  key_code) {
						// return a string describing the wii remote
						return [NSString stringWithFormat:@"#%d %s", i+1, buttonStrings[j], nil];
					}
				}
			}
		}
	}
	
	return nil;
}

- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
	if (aTableView == self.keyTable) {
		return numEmulatedKeys;
	}
		
	return 0;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(int)rowIndex
{
	if (aTableView == self.keyTable) {
		if ([self.KBEnabledButton state] == NSOnState)
			return YES;
		else
			return NO;
	}
	return NO;
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == self.keyTable) {
		int selectedRow = [self.keyTable selectedRow];
		if (selectedRow >= 0 && selectedRow <= numEmulatedKeys ) {
			_isSettingPreferences = YES;
			NSString* string = [NSString stringWithFormat: @"Press desired button for %s on desired Wii remote now.", keyStrings[selectedRow], nil];
			[self.prefHelpText setStringValue:string];
			[self.prefHelpText setTextColor:[NSColor redColor]];
		}
		else {
			_isSettingPreferences = NO;
			[self.prefHelpText setStringValue:prefHelpString];
			[self.prefHelpText setTextColor:[NSColor controlTextColor]];
		}
	}
}

// we need this function becuase we need [NSApp activateIgnoringOtherApps:YES] for each window's makeKeyAndOrderFront.  We could subclass NSWindow... but this function is ok.
- (IBAction)openWindow:(id)sender
{
	NSWindow* window;
	if ([sender tag] == 100)
		window = self.prefWindow;
	else if ([sender tag] == 101)
		window = self.aboutWindow;
	else if ([sender tag] == 103)
		window = self.helpWindow;
	else if ([sender tag] == 105) {
		[NSApp terminate:sender];
		return;
	}
	else 
		return;
	
	[window makeKeyAndOrderFront:self];
	[NSApp activateIgnoringOtherApps:YES];

//	[window orderFrontRegardless];
}

- (IBAction)donate:(id)sender
{
	NSString* urlstr = @"https://www.paypal.com/cgi-bin/webscr?cmd=_donations&business=veltrop%40gmail%2ecom&item_name=Wiiji%20Developer%20Donation&amount=1%2e50&page_style=PayPal&no_shipping=1&return=http%3a%2f%2fwiiji%2eveltrop%2ecom%2fthankyou%2ehtml&cn=Comments&tax=0&currency_code=USD&lc=US&bn=PP%2dDonationsBF&charset=UTF%2d8";
	NSWorkspace * ws = [NSWorkspace sharedWorkspace];
	NSURL * url = [NSURL URLWithString:urlstr];
	
	[ws openURL: url];
}

- (IBAction)checkForUpdates:(id)sender
{		
//	[NSThread detachNewThreadSelector:@selector(doUpdate:) toTarget:[WiijiUpdater class] withObject:sender];
}

- (void) setAutoUpdate:(int)state
{
	[self.UpdateCheckEnabledButton setState:state];
	NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
	[defs setValue:[NSNumber numberWithInt:state] forKey:@"UpdateCheckEnabled"];
	[defs synchronize];
}

#pragma mark -
#pragma mark WiiRemote delegates

// this needs to work very fast, its goal is to never allocate memory, nor send objective-c messages 
// (except in preference setting mode where performance doesnt matter)
// NOTE: if cID is out of range, we will crash.  if _service[cID] is null, are we ok?
- (void) buttonChanged:(WiiButtonType)type isPressed:(BOOL)isPressed controllerID:(int)cID
{	
	static UInt8 properties[3] = {0, 0, 0};
	static CGKeyCode hid_key;
	static CGEventRef event = NULL;

	if (_isSettingPreferences) {
		int selectedRow = [self.keyTable selectedRow];
		if (selectedRow >= 0 && selectedRow < numEmulatedKeys) {
			int key_code = keyCodes[selectedRow];
			int i,j;
			for (i = 0; i < maxNumWiimotes; i++) {  // search to see if someone else was using the binding and clear it
				for (j = 0; j < WiiNumberOfButtons; j++) {
					if (bindings[i][j] ==  key_code) {
						bindings[i][j] = -1;
					}
				}
			}
			bindings[cID][type] = key_code;  // set the number in the bindings array
			[self.prefHelpText setStringValue:prefHelpString];
			[self.keyTable selectRowIndexes:nil byExtendingSelection:NO];
			[self.prefHelpText setStringValue:prefHelpString];
			[self.prefHelpText setTextColor:[NSColor controlTextColor]];
			[self.keyTable reloadData]; // set the button string in the view
			[self saveKeyBindings];
			_isSettingPreferences = NO;
		}
	} else {
		if (_isUsingKBEmu) {
			// TODO: the KBEmu doesn't seem to repeat typed keys..., but it is in fact holding them down, it must have to do with the text input engine of os-x somehow
			hid_key = bindings[cID][type];
			CFRelease(CGEventCreate(NULL)); // Tiger's bug. see: http://www.cocoabuilder.com/archive/message/cocoa/2006/10/4/172206
			//if (!event)
			//	event = CGEventCreate(NULL);
			//CFRelease(event);	// dont release the previous event til the next one comes in (will this fix the no key repeat problem?) , it's null the first run, so it should address the above Tiger bug too
			event = CGEventCreateKeyboardEvent(NULL, hid_key, isPressed);
			CGEventPost(kCGHIDEventTap, event);
			CFRelease(event);
			//usleep(10000);
		}
		if (_isVirtualHIDOpen) {
			if (type >= WiiClassicControllerYButton) // lets overlap the classic conroller with the wiimote/nunchuck buttons
				type -= WiiClassicControllerYButton;
			properties[0] = type;
			properties[1] = isPressed;
			CFDataRef request = CFDataCreateWithBytesNoCopy(NULL, properties, 3, kCFAllocatorNull);
			IORegistryEntrySetCFProperties (_service[cID], request);
			CFRelease(request);
			//setVirtualDriverPropertiesFast(_service[cID], properties, 2);
			//[self setVirtualDriverProperties:properties length:2];
		}
	}
}

// type: WiiNunchukJoyStick 0, WiiClassicControllerLeftJoyStick 1, WiiClassicControllerRightJoyStick 2
// NOTE: if cID is out of range, we will crash.  if _service[cID] is null, are we ok?
- (void) joyStickChanged:(WiiJoyStickType) type tiltX:(unsigned short) tiltX tiltY:(unsigned short) tiltY controllerID:(int)cID
{
	//NSLog(@"%d,%d", tiltX, tiltY, nil);
	
	static UInt8 properties[3] = {0, 0, 0};
	static UInt8 factor;
	if (type == WiiNunchukJoyStick)
		factor = 128;
	else if (type == WiiClassicControllerLeftJoyStick)
		factor = 32;
	else // WiiClassicControllerRightJoyStick
		factor = 16;
		
	properties[0] = hid_XYZ + (type == WiiClassicControllerRightJoyStick);
	properties[1] = /*0x00 |*/ (tiltX - factor)*128/factor;
	properties[2] = /*0x00 | */ ((factor*2+1 - tiltY) - factor)*128/factor;
	CFDataRef request = CFDataCreateWithBytesNoCopy(NULL, properties, 3, kCFAllocatorNull);
	IORegistryEntrySetCFProperties (_service[cID], request);	
	CFRelease(request);
}

// This could go into a rudder/throttle cattegory of joystick hid
/*- (void) analogButtonChanged:(WiiButtonType) type amount:(unsigned short) press;
{
	
}*/

// NOTE: if cID is out of range, we will crash.
- (void) wiiRemoteDisconnected:(IOBluetoothDevice*)device remote:(WiiRemote*)remote controllerID:(int)cID
{
	_wiimote[cID] = nil;
	NSMenuItem* item = [self.mainMenu itemWithTag:cID+500];
	if (item) {
		[item setEnabled:NO];
		[item setState:NSOffState];
	} 
	//[mainMenu update];
		
	int i;
	for (i=0; i < maxNumWiimotes; i++) {
		if (_wiimote[i] != nil)
			break;
	}
	if (i == maxNumWiimotes)
		[wii_menu setImage:icons[0]];
		
//	[self syncVirtualDrivers];
}	

- (void)expansionPortChanged:(NSNotification *)nc
{	
	WiiRemote* inWiimote = (WiiRemote*)[nc object];
	
	if ([inWiimote isExpansionPortAttached]){
		[inWiimote setExpansionPortEnabled:YES];
		// add string of attached peripheral to menu?  (no reason to really)
	} else {
		[inWiimote setExpansionPortEnabled:NO];
		int remote_id = [inWiimote getControllerID];
		if (remote_id < maxNumWiimotes && remote_id > 0) {
			if (_service[remote_id] != IO_OBJECT_NULL) {
				// reset all joysticks in virtualHID for inWiimote to centered
				UInt8 properties[3] = {0, 0, 0};
				properties[0] = hid_XYZ;
				CFDataRef request = CFDataCreateWithBytesNoCopy(NULL, properties, 3, kCFAllocatorNull);
				// TODO: the below line could have an access crash on that vector, confirm that the id of the controller has a driver!
				IORegistryEntrySetCFProperties (_service[remote_id], request);	
				CFRelease(request);
				properties[0] = hid_rXYZ;
				request = CFDataCreateWithBytesNoCopy(NULL, properties, 3, kCFAllocatorNull);
				IORegistryEntrySetCFProperties (_service[remote_id], request);	
				CFRelease(request);
			}
		}
	}	
}



#pragma mark -
#pragma mark WiiRemoteDiscovery delegates
- (void) willStartWiimoteConnections
{
	//	NSLog(@"willStartWiimoteConnections:");
}

- (void) willStartDiscovery
{
    if (self.scanMenuTextItem)
    {
        [self.statusBarMenu removeItem:self.scanMenuTextItem];
        self.scanMenuTextItem = nil;
    }
    
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Scanning, click to stop" action:@selector(stopAction:) keyEquivalent:@""];
    [item setEnabled:YES];
    [self.statusBarMenu insertItem:item atIndex:0];
    
    self.scanMenuTextItem = item;
	if (animationTimer) {
		[animationTimer invalidate];
	}
	animationTimer = [NSTimer scheduledTimerWithTimeInterval:0.75 target:self selector:@selector(tick) userInfo:NULL repeats:YES];
}

- (void) willStopDiscovery
{
	if (animationTimer)  {
		[animationTimer invalidate];
		animationTimer = nil;
	}
	[self.scanMenuTextItem setTitle:@"Rescan for Wiimotes"];
    self.scanMenuTextItem.action = @selector(tryAgain:);

	int i;
	for (i = 0; i < maxNumWiimotes; i++) {
		if (_wiimote[i] != nil) {
			[wii_menu setImage:icons[2]];
			break;
		}
	}
	if (i == maxNumWiimotes) {
		[wii_menu setImage:icons[0]]; 
	}
}

- (void) WiiRemoteDiscoveryError:(int)code
{
	if (code == 56) {
		[NSApp activateIgnoringOtherApps:YES];
		NSRunCriticalAlertPanel(@"No Bluetooth Available", 
                        @"Wiiji is Unable to open bluetooth.\nPlease enable bluetooth.",
                        @"OK", nil, nil);
	}
	else if (code != 4) /*if (code == 536870195 || code == -536870195 )*/ {		// 4 is a timeout error
		NSLog(@"WiiRemoteDiscoveryError: %i", code, nil);
		if (_wii_discovery != nil) {
			//[_wii_discovery stop];
			//[_wii_discovery close];
			[_wii_discovery start];
			NSLog(@"Restarting discovery after error.");
			//[_wii_discovery resume];
		}
	}

}

- (void) WiiRemoteDiscovered:(WiiRemote*)wiimote
{
	//	NSLog(@"WiiRemoteDiscovered:");
	int the_id;
	int i;
	for (i = 0; i < maxNumWiimotes; i++) {
		if (_wiimote[i] == nil) {
			the_id = i;
			break;
		}
	}
	if (i == maxNumWiimotes) {
		[wiimote closeConnection];
		return;
	}

	[wiimote setDelegate:self];
	_wiimote[the_id] = wiimote;
	[wiimote setLEDEnabled:the_id];
	[wiimote setControllerID:the_id];
	
	NSMenuItem* item = [self.mainMenu itemWithTag:i+500];
	if (item) {
		[item setEnabled:YES];
		[item setState:NSOnState];
	} 
	
	if ([self.HIDEnabledButton state])
		[self syncVirtualDrivers];
	
	[wii_menu setImage:icons[2]];
	
	[_wii_discovery start];
}

#pragma mark -
#pragma mark Virtual HID kernel Interface Stuff
- (BOOL) syncVirtualDrivers
{
	kern_return_t	kernResult; 
	BOOL ret_val = YES;
	
	int i;
	for (i = 0; i < maxNumWiimotes; i++) {
		if (_wiimote[i] != nil) {
			break;
		}
	}
	if (i == maxNumWiimotes)
		return YES;				// there were no wiimotes to connect to.
	
	if (_isVirtualHIDOpen)
		[self closeVirtualDriver];
	
	io_iterator_t 	iterator;
	CFDictionaryRef	classToMatch;
	
	classToMatch = IOServiceMatching(kMyDriversIOKitClassName);
	if (classToMatch == NULL) {
		NSLog(@"IOServiceMatching returned a NULL dictionary.");
		ret_val = NO;
		goto fail0;
	}
	
	kernResult = IOServiceGetMatchingServices(kIOMasterPortDefault, classToMatch, &iterator);
	if (kernResult != KERN_SUCCESS) {
		NSLog(@"IOServiceGetMatchingServices returned 0x%08x", kernResult, nil);
		ret_val = NO;
		goto fail0;
	}

	//while ((_service[i++] = IOIteratorNext(iterator)) && i < maxNumWiimotes);	//this gets driver # out of sync with _wiimote ID #, but it looked nice, now we need a complex for loop
	for (i = 0; i < maxNumWiimotes; i++) {
		if (_wiimote[i]) {
			if (!(_service[i] = IOIteratorNext(iterator))) {
				ret_val = NO;
				NSLog(@"Couldn't connect to kernel driver #%d.", i);
			}
		}
	}
	IOObjectRelease(iterator);

	// we aren't in need of a full user client, maybe someday we will be
	//kernResult = UserClientOpen(service, &connect);
	//IOObjectRelease(service);
		
fail0:
	if (ret_val == NO) {
		[NSApp activateIgnoringOtherApps:YES];
		NSRunCriticalAlertPanel(@"No Virtual HID Driver Available", 
                        @"Wiiji is Unable to open the Virtual HID Driver.\nHID joypad emulation unavailable.",
                        @"OK", nil, nil);
	}
	//NSLog(@"Wiiji found %d virtual hid drivers to load.", i-1, nil);
	
	_isVirtualHIDOpen = ret_val;
	return ret_val;
}

- (void) closeVirtualDriver
{
	int i;
	for (i= 0; i < maxNumWiimotes; i++); {
		if (_service[i]) {
			IOObjectRelease(_service[i]);
			//_service[i] = 0;
		}
	}
	//IOObjectRelease(_connect);
	_isVirtualHIDOpen = NO;
}

// this is perhaps slow becuase it copies data, and also is an objective-c message, see below for faster version
/*- (void) setVirtualDriverProperties:(void*)properties length:(int)length
{
//	if (_isVirtualHIDOpen) {
		IOReturn ret;

		NSData *request = [NSData dataWithBytes:properties length:length];
		if (request == nil) {
			NSLog(@"Failed to allocate memory for virtual driver communication");
			return;
		}
		
		ret = IORegistryEntrySetCFProperties (_service, (CFDataRef*)request);
		if (ret != kIOReturnSuccess)
			NSLog(@"Failed setting driver properties: 0x%x", ret);
			
	//	if (request != nil)
			[request autorelease];
//	}
}*/

void setVirtualDriverPropertiesFast(io_service_t service, void* properties, int size)
{
	//NSData *request = [NSData dataWithBytes/*NoCopy*/:properties length:size];
	//	IOReturn ret;
	CFDataRef request = CFDataCreateWithBytesNoCopy(NULL, properties, size, kCFAllocatorNull);
	
	/*	ret = */IORegistryEntrySetCFProperties (service, request);
	//if (ret != kIOReturnSuccess)
	//	NSLog(@"Failed setting driver properties: 0x%x", ret);
	CFRelease(request);
}

@end
