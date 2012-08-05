/*
 AppDelegate.m
 EVE
 
 Created by Tobias Sommer on 6/13/12.
 Copyright (c) 2012 Sommer. All rights reserved.
 
 This file is part of EVE.
 
 EVE is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 EVE is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with EVE.  If not, see <http://www.gnu.org/licenses/>. */


#import <Cocoa/Cocoa.h>
#import <AppKit/NSAccessibility.h>
#import <Carbon/Carbon.h>
#import "AppDelegate.h"
#import "UIElementUtilities.h"
#import "NSFileManager+DirectoryLocations.h"
#import "ApplicationData.h"
#import "ProcessPerformedAction.h"
#import "Constants.h"

NSMutableDictionary  *shortcutDictionary;
NSImage              *eve_icon;
NSString             *preferredLang;
NSInteger            appPause;
NSPopover            *popover;
NSString             *lastSendedShortcut;
NSMutableDictionary  *applicationData;

static const int ddLogLevel = LOG_LEVEL_VERBOSE;

@implementation AppDelegate


- (void)applicationDidFinishLaunching:(NSNotification *)note {
    
    // We first have to check if the Accessibility APIs are turned on.  If not, we have to tell the user to do it (they'll need to authenticate to do it).  If you are an accessibility app (i.e., if you are getting info about UI elements in other apps), the APIs won't work unless the APIs are turned on.	
    if (!AXAPIEnabled())
    {
    
	NSAlert *alert = [[NSAlert alloc] init];
	
	[alert setAlertStyle:NSWarningAlertStyle];
	[alert setMessageText:@"EVE requires that the Accessibility API be enabled."];
	[alert setInformativeText:@"Would you like to launch System Preferences so that you can turn on \"Enable access for assistive devices\"?"];
	[alert addButtonWithTitle:@"Open System Preferences"];
	[alert addButtonWithTitle:@"Continue Anyway"];
	[alert addButtonWithTitle:@"Quit UI"];
	
	NSInteger alertResult = [alert runModal];
	        
        switch (alertResult) {
            case NSAlertFirstButtonReturn: {
		NSArray *paths = NSSearchPathForDirectoriesInDomains(NSPreferencePanesDirectory, NSSystemDomainMask, YES);
		if ([paths count] == 1) {
		    NSURL *prefPaneURL = [NSURL fileURLWithPath:[[paths objectAtIndex:0] stringByAppendingPathComponent:@"UniversalAccessPref.prefPane"]];
		    [[NSWorkspace sharedWorkspace] openURL:prefPaneURL];
		}		
	    }
		break;
                
            case NSAlertSecondButtonReturn: // just continue
            default:
                break;
		
            case NSAlertThirdButtonReturn:
                [NSApp terminate:self];
                return;
                break;
        }
        
        
    }
    
    _systemWideElement = AXUIElementCreateSystemWide();
    
    shortcutDictionary = [[NSMutableDictionary alloc] init]; 
    
    applicationData = [ApplicationData loadApplicationData];
    applicationDataDictionary = [applicationData getApplicationDataDictionary];
    
    // Language
    NSUserDefaults* defs = [NSUserDefaults standardUserDefaults];
    NSArray* languages = [defs objectForKey:@"AppleLanguages"];
    preferredLang = [languages objectAtIndex:0];
    DDLogInfo(@"Language: %@", preferredLang);
    
  //  [self registerGlobalMouseListener];
    [self registerAppFrontSwitchedHandler];
    [self registerAppLaunchedHandler];
    
    
    // Logging Framework
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];
    fileLogger.maximumFileSize = (3024 * 3024);
    fileLogger.rollingFrequency = 60 * 60 * 24; // 24 hour rolling
    fileLogger.logFileManager.maximumNumberOfLogFiles = 1;
    
    [DDLog addLogger:fileLogger];
    
    
    // Growl
//        [Growl initializeGrowl];
        [GrowlApplicationBridge setGrowlDelegate:self];
            DDLogInfo(@"Load Growl Framework");
}


-(void)growlNotificationWasClicked:(id) clickedContext { // a Growl delegate method, called when a notification is clicked. Check the value of the clickContext argument to determine what to do
    if(clickedContext){
        DDLogInfo(@"ClickContext successfully received!");
        
        if (!learnedWindowController) {
            learnedWindowController = [[LearnedWindowController alloc] initWithWindowNibName:@"LearnedWindow"];
            [learnedWindowController setAppDelegate: self];
        }
        
        [self setClickContextArray: clickedContext];
        
        NSWindow *learnedWindow = [learnedWindowController window];
        [learnedWindow orderFront:self];
        [learnedWindow setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces];
        
        [NSApp runModalForWindow: learnedWindow];
        
        [NSApp endSheet: learnedWindow];
        [NSApp activateIgnoringOtherApps:YES];
        
        [learnedWindow orderOut: self];
    }
    else
    {
        DDLogError(@"Something went wrong in the click context: %@", clickedContext);
    }
}


#pragma mark -

// -------------------------------------------------------------------------------
//	setCurrentUIElement:uiElement
// -------------------------------------------------------------------------------
- (void)setCurrentUIElement:(AXUIElementRef)uiElement
{   
    _currentUIElement = uiElement;
}

// -------------------------------------------------------------------------------
//	currentUIElement:
// -------------------------------------------------------------------------------
- (AXUIElementRef)currentUIElement
{
    return _currentUIElement;
}


// -------------------------------------------------------------------------------
//	updateCurrentUIElement:
// -------------------------------------------------------------------------------
- (void)updateCurrentUIElement
{
    
        // The current mouse position with origin at top right.
	   NSPoint cocoaPoint = [NSEvent mouseLocation];
	        
        // Only ask for the UIElement under the mouse if has moved since the last check.
        if (!NSEqualPoints(cocoaPoint, _lastMousePoint)) {

	    CGPoint pointAsCGPoint = [UIElementUtilities carbonScreenPointFromCocoaScreenPoint:cocoaPoint];

           AXUIElementRef newElement;
	    
	    /* If the interaction window is not visible, but we still think we are interacting, change that */
            if (_currentlyInteracting) {
                _currentlyInteracting = ! _currentlyInteracting;
            }

            // Ask Accessibility API for UI Element under the mouse
            // And update the display if a different UIElement
            if (AXUIElementCopyElementAtPosition( _systemWideElement, pointAsCGPoint.x, pointAsCGPoint.y, &newElement ) == kAXErrorSuccess
                && newElement
                && ([self currentUIElement] == NULL || ! CFEqual( [self currentUIElement], newElement ))) {

                [self setCurrentUIElement:newElement];
            }
            
            _lastMousePoint = cocoaPoint;
        }
}

// -------------------------------------------------------------------------------
//
// -------------------------------------------------------------------------------
- (void) registerGlobalMouseListener
{
    _eventMonitor = [NSEvent addGlobalMonitorForEventsMatchingMask:(NSLeftMouseUp)
                                                           handler:^(NSEvent *incomingEvent) {
                                                               if(!appPause) {
                             
                                                                   // listing important
                                                                   [self updateCurrentUIElement];
                                                                   
                                                                   
                                                                   if([self currentUIElement])
                                                                   {
                                                                       // Filter to do not to much work
                                                                       if ([self elememtInFilter: [self currentUIElement]])                                                                                                                        {
                                                                           [ProcessPerformedAction treatPerformedAction:incomingEvent :_currentUIElement :    [applicationDataDictionary valueForKey:learnedShortcuts]];
                                                                       }
                                                                   }
                                                               }
                                                           }];
  
}

- (void) registerAppFrontSwitchedHandler {
    EventTypeSpec spec = { kEventClassApplication,  kEventAppFrontSwitched };
    OSStatus err = InstallApplicationEventHandler(NewEventHandlerUPP(AppFrontSwitchedHandler), 1, &spec, (__bridge void*)self, NULL);
    
    if (err)
        DDLogError(@"Could not install event handler");
}

- (void) registerAppLaunchedHandler {
    EventTypeSpec spec = { kEventClassApplication,  kEventAppLaunched };
    OSStatus err = InstallApplicationEventHandler(NewEventHandlerUPP(AppLaunchedHandler), 1, &spec, (__bridge void*)self, NULL);    
    if (err)
        DDLogError(@"Could not install event handler");
}


- (void) appFrontSwitched {
    if (_eventMonitor ) {
        [NSEvent removeMonitor:_eventMonitor];
        _eventMonitor = NULL;
    }
      
      if(!appPause) {
        NSString     *activeApplicationName = [NSString stringWithFormat:@"%@",[UIElementUtilities readApplicationName]];
        DDLogInfo(@"Active Application: %@", activeApplicationName);
        
        id applicationDisabled = [[applicationDataDictionary valueForKey:DISABLED_APPLICATIONS] valueForKey:activeApplicationName];
          
        if ( !(applicationDisabled ? [applicationDisabled boolValue] : NO) )
        {
            // Add the mouse listener to track the user actions
        [self registerGlobalMouseListener];
            DDLogInfo(@"Registered the Mouse Listener");
            
        NSMutableDictionary *applicationShortcuts = [applicationDataDictionary valueForKey:@"applicationShortcuts"];
        
        AXUIElementRef appRef = AXUIElementCreateApplication( [[[[NSWorkspace sharedWorkspace] activeApplication] valueForKey:@"NSApplicationProcessIdentifier"] intValue] );
        
          
        NSDictionary *menuBarShortcuts   = [NSDictionary dictionaryWithDictionary:[UIElementUtilities createApplicationMenuBarShortcutDictionary:appRef]];
          NSDictionary *appAddinitionalShortcuts = [NSDictionary dictionaryWithDictionary:[[applicationShortcuts valueForKey:preferredLang]  valueForKey:activeApplicationName]];
          NSDictionary *globalAddintionalShortcuts = [NSDictionary dictionaryWithDictionary:[[applicationShortcuts valueForKey:preferredLang]  valueForKey:@"global"]];
          [applicationShortcuts setValue:appAddinitionalShortcuts forKey:@"additionalShortcuts"];
          [applicationShortcuts setValue:globalAddintionalShortcuts forKey:@"global"];
        
        [applicationShortcuts setValue:menuBarShortcuts forKey:@"menuBarShortcuts"];

        [shortcutDictionary setValue:applicationShortcuts forKey:activeApplicationName];
        
          
        DDLogInfo(@"ShortcutDictionary for %@ created", activeApplicationName); 
        DDLogInfo(@"I create a menuBarShortcutDictionary   with %lu Items", menuBarShortcuts.count);
        CFRelease(appRef);
        }
        else
        {
                DDLogInfo(@"You disabled this Application: %@", activeApplicationName);
                DDLogInfo(@"Disabled the Mouse Listener.");
        }
    }
}

static OSStatus AppLaunchedHandler(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData) {
    [(__bridge id)inUserData appFrontSwitched];
    return 0;
}


static OSStatus AppFrontSwitchedHandler(EventHandlerCallRef inHandlerCallRef, EventRef inEvent, void *inUserData) {
   [(__bridge id)inUserData appFrontSwitched];
    return 0;
}



- (void) setClickContextArray:(NSArray*) id {
    clickContext = id;
}

- (NSArray*) getClickContextArray {
    return clickContext;
}

- (ApplicationData*) getApplicationData {
    return applicationData;
}

- (Boolean) elememtInFilter :(AXUIElementRef) element {
    NSString* role = [UIElementUtilities readkAXAttributeString:[self currentUIElement] :kAXRoleAttribute];
    AXUIElementRef parentRef;
    
    NSString *parent = [[NSString alloc] init];
    if(AXUIElementCopyAttributeValue( element, (CFStringRef) kAXParentAttribute, (CFTypeRef*) &parentRef ) == kAXErrorSuccess){
        parent = [UIElementUtilities readkAXAttributeString:parentRef :kAXRoleAttribute];
    }
                            
    if ( ([role isEqualToString:(NSString*)kAXButtonRole]
        || ([role isEqualToString:(NSString*)kAXRadioButtonRole]
            && ![parent isEqualToString:(NSString*)kAXTabGroupRole])
        || [role isEqualToString:(NSString*)kAXTextFieldRole]
        || [role isEqualToString:(NSString*)kAXPopUpButtonRole]
        || [role isEqualToString:(NSString*)kAXCheckBoxRole]
        || [role isEqualToString:(NSString*)kAXMenuButtonRole]
        || [role isEqualToString:(NSString*)kAXMenuItemRole]
        || [role isEqualToString:(NSString*)kAXStaticTextRole])
        && ![UIElementUtilities isWebArea:element])
    {
        return true;
    }
    
    DDLogInfo(@"UIElement not in the Filter: %@ Parent:%@", role, parent);
    return false;
}



@end