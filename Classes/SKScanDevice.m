/*
 This file is licensed under the FreeBSD-License.
 For details see https://www.gnu.org/licenses/license-list.html#FreeBSD
 
 Copyright 2011 Manfred Kroehnert. All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification, are
 permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this list of
 conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice, this list
 of conditions and the following disclaimer in the documentation and/or other materials
 provided with the distribution.
 
 THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ''AS IS'' AND ANY EXPRESS OR IMPLIED
 WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
 FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL <COPYRIGHT HOLDER> OR
 CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON
 ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
 NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF
 ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 
 The views and conclusions contained in the software and documentation are those of the
 authors and should not be interpreted as representing official policies, either expressed
 or implied, of Manfred Kroehnert.
 */

#import "SKScanDevice.h"
#import "SKScanParameters.h"
#import "SKScanOption.h"
#import "SKRange.h"
#import "SKRangeFixed.h"
#import "SKStructs.h"

#include <sane/sane.h>
#include <sane/saneopts.h>
#include <math.h>

#import <AppKit/AppKit.h>

@interface SKScanDevice (private)

-(SANE_Status) setValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex info:(SANE_Int*) info;
-(SANE_Status) getValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex;
-(void) setUnit:(SANE_Unit) theUnit onOption:(SKScanOption*) theOption;
-(void) setConstraints:(const SANE_Option_Descriptor*) theOptionDescriptor onOption:(SKScanOption*) theOption;
-(void) setCapabilities:(SANE_Int) theCapabilities onOption:(SKScanOption*) theOption;
-(void) handleSaneStatusError:(SANE_Status) saneStatus;

@end


@implementation SKScanDevice (private)

-(SANE_Status) setValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex info:(SANE_Int*) info;
{
    // no need to check if parameter info is NULL
    // in the NULL case no additianal information is stored in info
	SANE_Status status;
    status = sane_control_option(handle->deviceHandle, theIndex, SANE_ACTION_SET_VALUE, theValue, info);
    if (SANE_STATUS_GOOD != status)
        [self handleSaneStatusError: status];
    
    return status;
}


-(SANE_Status) getValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex;
{
    return sane_control_option(handle->deviceHandle, theIndex, SANE_ACTION_GET_VALUE, theValue, NULL);
}


-(void) setUnit:(SANE_Unit) theUnit onOption:(SKScanOption*) theOption
{
    NSString* unitString = nil;
    switch (theUnit) {
        case SANE_UNIT_NONE:
            unitString = @"";
            break;
        case SANE_UNIT_PIXEL:
            unitString = @"pixel";
            break;
        case SANE_UNIT_BIT:
            unitString = @"Bit";
            break;
        case SANE_UNIT_MM:
            unitString = @"mm";
            break;
        case SANE_UNIT_DPI:
            unitString = @"dpi";
            break;
        case SANE_UNIT_PERCENT:
            unitString = @"%";
            break;
        case SANE_UNIT_MICROSECOND:
            unitString = @"uSec";
            break;
    }
    [theOption setUnitString: unitString];
}


/**
 * This method stores the constraints from parameter theOptionDescriptor->constraint on the
 * option object passed in as parameter theOption.
 */
-(void) setConstraints:(const SANE_Option_Descriptor*) theOptionDescriptor onOption:(SKScanOption*) theOption
{
    if (SANE_CONSTRAINT_RANGE == theOptionDescriptor->constraint_type)
    {
        SKRange* rangeConstraint = nil;
        const SANE_Range* range = theOptionDescriptor->constraint.range;
        if (SANE_TYPE_FIXED == theOptionDescriptor->type)
            rangeConstraint = [[SKRangeFixed alloc] initWithDoubleMinimum: SANE_UNFIX(range->min)
                                                                  maximum: SANE_UNFIX(range->max)
                                                             quantisation: SANE_UNFIX(range->quant)];
        else
            rangeConstraint = [[SKRange alloc] initWithMinimum: range->min
                                                       maximum: range->max
                                                  quantisation: range->quant];

        [theOption setRangeConstraint: rangeConstraint];
    }
    else if (SANE_CONSTRAINT_WORD_LIST == theOptionDescriptor->constraint_type)
    {
        const SANE_Word* possibleValues = theOptionDescriptor->constraint.word_list;
        const SANE_Int listLength = possibleValues[0];
        NSMutableArray* optionList = [NSMutableArray arrayWithCapacity: listLength];
        for (int j = 0; possibleValues && j <= listLength; ++j)
        {
            if (SANE_TYPE_FIXED == theOptionDescriptor->type)
                [optionList addObject: [NSNumber numberWithDouble: SANE_UNFIX(possibleValues[j]) ]];
            else if (SANE_TYPE_INT == theOptionDescriptor->type)
                [optionList addObject: [NSNumber numberWithInt: possibleValues[j] ]];
        }
        [theOption setNumericConstraints: optionList];
    }
    else if (SANE_CONSTRAINT_STRING_LIST == theOptionDescriptor->constraint_type)
    {
        const SANE_String_Const* modes = theOptionDescriptor->constraint.string_list;
        NSMutableArray* optionList = [NSMutableArray arrayWithCapacity: 1];
        for (int j = 0; modes && modes[j]; ++j)
        {
            [optionList addObject: [NSString stringWithCString: modes[j] ]];
        }
        [theOption setStringConstraints: optionList];
    }
}


/**
 * This method sets the various capabilities stored in the parameter theCapabilities on
 * the option object passed in as paramter theOption.
 */
-(void) setCapabilities:(SANE_Int) theCapabilities onOption:(SKScanOption*) theOption
{
	if ( (SANE_CAP_SOFT_SELECT & theCapabilities) && (SANE_CAP_HARD_SELECT & theCapabilities) )
    {
        NSLog(@"ERROR: SOFT and HARD Select can't be set at the same time");
        return;
    }
	else if ( (SANE_CAP_SOFT_SELECT & theCapabilities) && ( !(SANE_CAP_SOFT_DETECT & theCapabilities) ) )
    {
        NSLog(@"This option MUST be set!");
        return;
    }
    if(!( (SANE_CAP_SOFT_SELECT | SANE_CAP_HARD_SELECT | SANE_CAP_SOFT_DETECT) & theCapabilities ))
    {
        NSLog(@"Option is not useable (if one of these three is not set, option is useless, skip it)");
        return;
    }
    
    [theOption setReadOnly: (!(SANE_CAP_SOFT_SELECT & theCapabilities) && (SANE_CAP_SOFT_DETECT & theCapabilities))];
    [theOption setEmulated: (SANE_CAP_EMULATED & theCapabilities)];
    [theOption setAutoSelect: (SANE_CAP_AUTOMATIC & theCapabilities)];
    [theOption setInactive: (SANE_CAP_INACTIVE & theCapabilities)];
    [theOption setAdvanced: (SANE_CAP_ADVANCED & theCapabilities)];
}


/**
 * Handle status errors returned by libsane
 */
-(void) handleSaneStatusError:(SANE_Status) saneStatus
{
    switch (saneStatus) {
        case SANE_STATUS_CANCELLED:
            NSLog(@"Operation was cancelled");
            break;
        case SANE_STATUS_DEVICE_BUSY:
            NSLog(@"Device is busy right now");
            break;
        case SANE_STATUS_JAMMED:
            NSLog(@"Document feeder is jammed");
            break;
        case SANE_STATUS_NO_DOCS:
            NSLog(@"Document feeder is out of documents");
            break;
        case SANE_STATUS_COVER_OPEN:
            NSLog(@"The scanner cover is open");
            break;
        case SANE_STATUS_IO_ERROR:
            NSLog(@"Error occurred while communicating with the scan device");
            break;
        case SANE_STATUS_NO_MEM:
            NSLog(@"Not enough memory");
            break;
        case SANE_STATUS_UNSUPPORTED:
            NSLog(@"Operation is not supported by the current scan device");
            break;
        case SANE_STATUS_INVAL:
            /*
             SANE_STATUS_INVAL:
             The scan cannot be started with the current set of options. 
             The frontend should reload the option descriptors, as if SANE_INFO_RELOAD_OPTIONS
             had been returned from a call to sane_control_option(), since the device's capabilities may have changed. 
             */
            NSLog(@"Invalid option(s)");
            break;
        case SANE_STATUS_ACCESS_DENIED:
            NSLog(@"Access to option denied due to invalid authentication");
            break;
        default:
            NSLog(@"Unknown option: %d", saneStatus);
            break;
    }
}

@end


@implementation SKScanDevice

/**
 * Initialize the class using the parameters stored in an instance of SANE_device.
 */
-(id) initWithName:(NSString*) aName vendor:(NSString*) aVendor model:(NSString*) aModel type:(NSString*) aType
{
    self = [super init];
    if (self)
    {
        name = [aName retain];
        vendor = [aVendor retain];
        model = [aModel retain];
        type = [aType retain];
        handle = calloc(1, sizeof(handle));
        options = [[NSMutableDictionary dictionaryWithCapacity: 20] retain];
        parameters = nil;
    }
    return self;
}


/**
 * Init method to initialize the device from an array (e.g. from a stored userdefaults)
 */
-(id) initWithDictionary:(NSDictionary*) aDictionary
{
	NSString* theName = [aDictionary objectForKey:@"name"];
	NSString* theVendor = [aDictionary objectForKey:@"vendor"];
	NSString* theModel = [aDictionary objectForKey:@"model"];
	NSString* theType = [aDictionary objectForKey:@"type"];
    if (! (theName && theVendor && theModel && theType) )
        return nil;
    return [self initWithName: theName vendor: theVendor model: theModel type: theType];
}


/**
 * Release all ressources
 */
-(void) dealloc
{
    if (name)
        [name release];
    if (vendor)
        [vendor release];
    if (model)
        [model release];
    if (type)
        [type release];
    free(handle);
    if (options)
        [options release];
    if (parameters)
        [parameters release];
    
    [super dealloc];
}


/**
 * @return a dictionary which can be used to store the device identification in NSUserDefaults
 */
-(NSDictionary*) toUserDefaultsDict
{
	return [NSDictionary dictionaryWithObjectsAndKeys: name, @"name", vendor, @"vendor", model, @"model", type, @"type", nil];
}


/**
 * Returns an NSString instance describing the SKScanDevice
 */
-(NSString*) description
{
    NSString* deviceDescription = [NSString stringWithFormat: @"ScanDevice:\n\tName: %@\n\tVendor: %@\n\tModel: %@\n\tType: %@\n", name, vendor, model, type];
    return deviceDescription;
}


/**
 * Open the scan device and run an initial [self reloadScanOptions] and [self reloadScanParameters].
 *
 * @return YES if successful, NO otherwise
 */
-(BOOL) open
{
	SANE_Status openStatus = 0;
    openStatus = sane_open([name UTF8String], &(handle->deviceHandle));
    
    if (SANE_STATUS_GOOD == openStatus)
    {
        // populate the options dictionary
        [self reloadScanOptions];
        // create initial SKScanParameters instance
        [self reloadScanParameters];
    }

    return (SANE_STATUS_GOOD == openStatus) ? YES : NO;
}


/**
 * Close the scan device.
 */
-(void) close
{
	sane_close(handle->deviceHandle);
}


/**
 * This method reads the current scan parameters from the current SANE_Handle and creates
 * an SKScanParameters instance from them.
 */
-(void) reloadScanParameters
{
    SANE_Status parameterStatus;
    SANE_Parameters scanParameters;
    parameterStatus = sane_get_parameters(handle->deviceHandle, &scanParameters);
    if (SANE_STATUS_GOOD != parameterStatus)
    {
        NSLog(@"Sane get parameters error: %s", sane_strstatus(parameterStatus));
        if (parameters)
            [parameters release];
        parameters = nil;
        return;
    }
    
    if (parameters)
    {
        [parameters updateFormat: scanParameters.format
                       lastFrame: scanParameters.last_frame
                    bytesPerLine: scanParameters.bytes_per_line
                   pixelsPerLine: scanParameters.pixels_per_line
                           lines: scanParameters.lines
                           depth: scanParameters.depth];
    }
    else
    {
        parameters = [[SKScanParameters alloc] initWithFormat: scanParameters.format
                                                    lastFrame: scanParameters.last_frame
                                                 bytesPerLine: scanParameters.bytes_per_line
                                                pixelsPerLine: scanParameters.pixels_per_line
                                                        lines: scanParameters.lines
                                                        depth: scanParameters.depth];
    }
}

/**
 * @return the current SKScanParameters instance
 */
-(SKScanParameters*) scanParameters
{
    [self reloadScanParameters];
    return [[parameters retain] autorelease];
}


/**
 * Reads all options available from the current device and processes them into SKScanOption objects.
 */
-(void) reloadScanOptions
{
    SANE_Int numOptions = 0;
    SANE_Status optionStatus = 0;
    const SANE_Option_Descriptor* optionDescr;
    
    optionDescr = sane_get_option_descriptor(handle->deviceHandle, 0);
    if (!optionDescr)
    {
    	NSLog(@"Unable to retrieve options");
        return;
    }
    
    optionStatus = [self getValue: &numOptions forOptionWithIndex: 0];
    if (SANE_STATUS_GOOD != optionStatus)
    {
    	NSLog(@"Error retrieving number of available options");
        return;
    }

    // copy the old options dictionary because some values
    // might disappear on a second options scan
    NSDictionary* oldOptions = [options copy];
    // then clear the old values
    [options removeAllObjects];
    
    SKScanOption* option;
    
    // start with element #1 as element #0 contains 'only' the number of available options
    for (int i = 1; i < numOptions; ++i)
    {
        optionDescr = sane_get_option_descriptor(handle->deviceHandle, i);
        if (!optionDescr || !optionDescr->name || !optionDescr->type)
            continue;
        
        // create this string at the beginning as it is used in every if-case
        NSString* optionName = [NSString stringWithCString: optionDescr->name];
        option = [[oldOptions objectForKey: optionName] retain];
        
        if (SANE_TYPE_INT == optionDescr->type)
        {
            if (sizeof(SANE_Int) == optionDescr->size)
            {
                SANE_Int intValue = 0;
                optionStatus = [self getValue: &intValue forOptionWithIndex: i];
                
                if (SANE_STATUS_GOOD != optionStatus)
                    continue;
                // check if option was already present
                if (option)
                    [option setIntegerValue: intValue];
                else
                    option = [[SKScanOption alloc] initWithIntValue: intValue
                                                         optionName: optionName
                                                        optionIndex: i];
            }
            else
            {
                NSLog(@"%s => size of Int vector: %d", optionDescr->name, (optionDescr->size / sizeof(SANE_Int)));
                option = nil;
            }
        }
        else if (SANE_TYPE_FIXED == optionDescr->type)
        {
            if (sizeof(SANE_Int) == optionDescr->size)
            {
                SANE_Int fixedValue = 0;
                optionStatus = [self getValue: &fixedValue forOptionWithIndex: i];
                
                if (SANE_STATUS_GOOD != optionStatus)
                    continue;
                
                // check if option was already present
                if (option)
                    [option setDoubleValue: SANE_UNFIX(fixedValue)];
                else
                    option = [[SKScanOption alloc] initWithFixedValue: fixedValue
                                                           optionName: optionName
                                                          optionIndex: i];
            }
            else
            {
                NSLog(@"%s => size of Fixed Float vector: %d", optionDescr->name, (optionDescr->size / sizeof(SANE_Int)));
                option = nil;
            }
        }
        else if (SANE_TYPE_STRING == optionDescr->type && 0 < optionDescr->size)
        {
            SANE_String cStringValue = calloc(optionDescr->size, sizeof(SANE_Char));
            optionStatus = [self getValue: cStringValue forOptionWithIndex: i];
            
            if (SANE_STATUS_GOOD != optionStatus)
                continue;

            NSString* stringValue = [NSString stringWithCString: cStringValue];
            
            // check if option was already present
            if (option)
                [option setStringValue: stringValue];
            else
                option = [[SKScanOption alloc] initWithStringValue: stringValue
                                                         optionName: optionName
                                                        optionIndex: i];
            free(cStringValue);
        }
        else if (SANE_TYPE_BOOL == optionDescr->type
                 && (sizeof(SANE_Word) == optionDescr->size))
        {
            SANE_Bool value = SANE_FALSE;
            optionStatus = [self getValue: &value forOptionWithIndex: i];

            if (SANE_STATUS_GOOD != optionStatus)
                continue;

            BOOL boolValue = ((SANE_TRUE == value) ? YES : NO);
            // check if option was already present
            if (option)
                [option setBoolValue: boolValue];
            else
                option = [[SKScanOption alloc] initWithBoolValue: boolValue
                                                 optionName: optionName
                                                optionIndex: i];
        }
        else
        {
            // only SANE_TYPE_BUTTON and SANE_TYPE_GROUP are left
            // only title and type are valid for SANE_TYPE_GROUP
            NSString* optionTypeString = @"Button Option";
            if (SANE_TYPE_GROUP == optionDescr->type)
                optionTypeString = @"Group Option";
            
            NSString* stringValue = [NSString stringWithCString: optionDescr->title];
            
            if (option)
                [option setStringValue: stringValue];
            else
                option = [[SKScanOption alloc] initWithStringValue: stringValue
                                                    optionName: optionTypeString
                                                   optionIndex: i];
        }
 
        if (option)
        {
            [self setUnit: optionDescr->unit onOption: option];
            [self setConstraints: optionDescr onOption: option];
            if (optionDescr->title)
                [option setTitle: [NSString stringWithCString: optionDescr->title]];
            if (optionDescr->desc)
                [option setExplanation: [NSString stringWithCString: optionDescr->desc]];
            if ((optionDescr->cap) && (SANE_TYPE_GROUP != optionDescr->type))
                [self setCapabilities: optionDescr->cap onOption: option];

            [option autorelease];
            [options setObject: option forKey: [option name]];
        }
    }
    
    [oldOptions release];
}


/**
 * @return NSArray instance returning all valid options as SKScanOption objects
 */
-(NSArray*) scanOptions
{
    return [options allValues];
}


/**
 * This method takes an instance of SKScanOption and sets the value on the current scan device.
 */
-(BOOL) setScanOption:(SKScanOption*) theOption
{
    SANE_Int info;
	SANE_Status setStatus = [self setValue: [theOption value] forOptionWithIndex: [theOption index] info: &info];
    
    if (SANE_INFO_INEXACT & info)
        NSLog(@"Option value was rounded upon setting the option");
    else if (SANE_INFO_RELOAD_OPTIONS & info)
        [self reloadScanOptions];
    else if (SANE_INFO_RELOAD_PARAMS & info)
        [self reloadScanParameters];
    return YES;
}


/**
 * This method does a basic scan and stores the data in an instance of NSBitmapImageRep.
 * Note: you should call scanParameters to get an idea of the expected parameters of the scanned image.
 *
 * @return NSArray instance with all scanned images as NSBitmapImageRep
 */
-(NSArray*) doScan
{
	SANE_Status scanStatus = 0;
    NSBitmapImageRep* bitmapRep;
    NSMutableArray* scannedImages = [NSMutableArray arrayWithCapacity: 1];
    
    scanStatus = sane_start(handle->deviceHandle);
    if (SANE_STATUS_GOOD != scanStatus)
    {
        NSLog(@"Sane start error: %s", sane_strstatus(scanStatus));
        [self handleSaneStatusError: scanStatus];
        return scannedImages;
    }
    
    do
    {
        [self reloadScanParameters];
        if (![parameters checkParameters])
            continue;

        NSLog(@"Scan parameters:\n%@\n", parameters);
        int totalBytesToRead = [parameters totalBytes];
        NSLog(@"100%% = %d", totalBytesToRead);

        SANE_Int readBytes = 0;
        // TODO: correct for (lines < 0)
        const SANE_Int maxBufferSize = totalBytesToRead * sizeof(SANE_Byte);
        SANE_Byte* buffer = calloc(totalBytesToRead, sizeof(SANE_Byte));
        SANE_Word totalBytesRead = 0;

        do
        {
            scanStatus = sane_read(handle->deviceHandle, (buffer + totalBytesRead ), (maxBufferSize - totalBytesRead - 1), &readBytes);
            totalBytesRead += (SANE_Word)readBytes;
            double progr = ((totalBytesRead * 100.0) / (double) totalBytesToRead);
            progr = fminl(progr, 100.0);
            NSLog(@"Progress: %3.1f%%, total bytes: %d\n", progr, totalBytesRead);
        }
        while (SANE_STATUS_GOOD == scanStatus || SANE_STATUS_EOF != scanStatus);
        
        // first create an image rep which owns the bitmapData buffer and free()'s it itself
        // then copy the buffer contents into the bitmapData buffer
        // afterwards the buffer can be free()'d without issues and the image rep can
        // get passed around without creating memory leaks
        bitmapRep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL
                                                            pixelsWide: [parameters widthPixel]
                                                            pixelsHigh: [parameters heightPixel]
                                                         bitsPerSample: [parameters depth]
                                                       samplesPerPixel: [parameters samplesPerPixel] // or 4 with alpha
                                                              hasAlpha: NO
                                                              isPlanar: NO // only use the first element of buffer
                                                        colorSpaceName: [parameters colorSpaceName]
                                                          bitmapFormat: 0
                                                           bytesPerRow: [parameters bytesPerRow]    // 0 == determine automatically
                                                          bitsPerPixel: [parameters bitsPerPixel]]; // 0 == determine automatically

        // only copy the buffer into the image rep if they have the same size
        if (maxBufferSize == [bitmapRep bytesPerPlane])
            memcpy([bitmapRep bitmapData], buffer, maxBufferSize);
        free(buffer);

        if (nil != bitmapRep)
        {
        	[bitmapRep autorelease];
            [scannedImages addObject: bitmapRep];
        }
    }
    while (![parameters isLastFrame]);
    
    sane_cancel(handle->deviceHandle);
    
    return scannedImages;
}


/**
 * Set the scan mode on the current device.
 */
-(BOOL) setMode:(NSString*) theMode
{
    SKScanOption* option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_MODE]];
    [[option retain] autorelease];
    [option setStringValue: theMode];
    return [self setScanOption: option];
}


/**
 * Set the scan depth on the current device.
 */
-(BOOL) setDepth:(NSInteger) theDepth
{
    SKScanOption* option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_BIT_DEPTH]];
    [[option retain] autorelease];
    [option setIntegerValue: theDepth];
    return [self setScanOption: option];
}


/**
 * Set the scan resolution on the current device.
 */
-(BOOL) setResolution:(NSInteger) theResolution
{
    SKScanOption* option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_RESOLUTION]];
    [[option retain] autorelease];
    [option setIntegerValue: theResolution];
    return [self setScanOption: option];
}


/**
 * Set to YES if the scan should be a preview scan.
 */
-(BOOL) setPreview:(BOOL) doPreview
{
    SKScanOption* option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_PREVIEW]];
    [[option retain] autorelease];
    [option setBoolValue: doPreview];
    return [self setScanOption: option];
}


/**
 * Set the rectangle which should be scanned in the next scan.
 */
-(BOOL) setScanRect:(NSRect) scanRect
{
    SKScanOption* option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_TL_X]];
    [[option retain] autorelease];
    [option setDoubleValue: scanRect.origin.x];
    [self setScanOption: option];

    option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_TL_Y]];
    [[option retain] autorelease];
    [option setDoubleValue: scanRect.origin.y];
    [self setScanOption: option];

    option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_BR_X]];
    [[option retain] autorelease];
    [option setDoubleValue: scanRect.origin.x + scanRect.size.width];
    [self setScanOption: option];

    option = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_BR_Y]];
    [[option retain] autorelease];
    [option setDoubleValue: scanRect.origin.y + scanRect.size.height];
    [self setScanOption: option];

    return YES;
}


/**
 * @return an NSRect containing the boundaries of the scan area
 */
-(NSRect) maxScanRect
{
    SKScanOption* xOption = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_TL_X]];
    SKScanOption* yOption = (SKScanOption*)[options objectForKey: [NSString stringWithCString: SANE_NAME_SCAN_TL_Y]];
    double xMin = [[xOption rangeConstraint] min];
    double yMin = [[yOption rangeConstraint] min];
    double xSize = [[xOption rangeConstraint] max] - xMin;
    double ySize = [[yOption rangeConstraint] max] - yMin;
    return NSMakeRect(xMin, yMin, xSize, ySize);
}

@end
