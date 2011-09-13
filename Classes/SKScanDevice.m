//
//  SKScanDevice.m
//  SaneKit
//
//  Created by MK on 03.09.11.
//  Copyright 2011 __MyCompanyName__. All rights reserved.
//

#import "SKScanDevice.h"
#import "SKScanParameters.h"
#import "SKScanOption.h"
#import "SKStructs.h"

#include <sane/sane.h>
#include <math.h>

#import <AppKit/AppKit.h>

@interface SKScanDevice (private)

-(SANE_Status) setValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex;
-(SANE_Status) getValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex;
-(void) setUnit:(SANE_Unit) theUnit onOption:(SKScanOption*) theOption;
-(void) setConstraints:(const SANE_Option_Descriptor*) theOptionDescriptor onOption:(SKScanOption*) theOption;

@end


@implementation SKScanDevice (private)

-(SANE_Status) setValue:(void*) theValue forOptionWithIndex:(NSInteger) theIndex;
{
	SANE_Status status;
    SANE_Int info;
    status = sane_control_option(handle->deviceHandle, theIndex, SANE_ACTION_SET_VALUE, theValue, &info);
    return info;
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


-(void) setConstraints:(const SANE_Option_Descriptor*) theOptionDescriptor onOption:(SKScanOption*) theOption
{
    if (SANE_CONSTRAINT_RANGE == theOptionDescriptor->constraint_type)
    {
        const SANE_Range* range = theOptionDescriptor->constraint.range;
        if (SANE_TYPE_FIXED == theOptionDescriptor->type)
            NSLog(@"%s - Min: %g, Max: %g, Quantisation: %d", theOptionDescriptor->name, SANE_UNFIX(range->min), SANE_UNFIX(range->max), SANE_UNFIX(range->quant));
        else
            NSLog(@"%s - Min: %d, Max: %d, Quantisation: %d", theOptionDescriptor->name, range->min, range->max, range->quant);
    }
    else if (SANE_CONSTRAINT_WORD_LIST == theOptionDescriptor->constraint_type)
    {
        const SANE_Word* possibleValues = theOptionDescriptor->constraint.word_list;
        const SANE_Int listLength = possibleValues[0];
        for (int j = 0; possibleValues && j <= listLength; ++j) {
            if (SANE_TYPE_FIXED == theOptionDescriptor->type)
                NSLog(@"%s - possible option %d: %g", theOptionDescriptor->name, j, SANE_UNFIX(possibleValues[j]));
            else
                NSLog(@"%s - possible option %d: %d", theOptionDescriptor->name, j, possibleValues[j]);
        }
    }
    else if (SANE_CONSTRAINT_STRING_LIST == theOptionDescriptor->constraint_type)
    {
        const SANE_String_Const* modes = theOptionDescriptor->constraint.string_list;
        for (int j = 0; modes && modes[j]; ++j) {
            NSLog(@"%s - possible option %d: %s", theOptionDescriptor->name, j, modes[j]);
        }
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
    }
    return self;
}


/**
 * Release all ressources
 */
-(void) dealloc
{
    [name release];
    [vendor release];
    [model release];
    [type release];
    free(handle);
    
    [super dealloc];
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
 * Open the scan device.
 *
 * @return YES if successful, NO otherwise
 */
-(BOOL) open
{
	SANE_Status openStatus = 0;
    openStatus = sane_open([name UTF8String], &(handle->deviceHandle));
    
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
 *
 * @return a fully initialized SKScanParameters instance
 */
-(SKScanParameters*) scanParameters
{
    SANE_Status parameterStatus;
    SANE_Parameters scanParameters;
    parameterStatus = sane_get_parameters(handle->deviceHandle, &scanParameters);
    if (SANE_STATUS_GOOD != parameterStatus)
    {
        NSLog(@"Sane get parameters error: %s", sane_strstatus(parameterStatus));
        return nil;
    }
    
    SKScanParameters* parameters = [[SKScanParameters alloc] initWithFormat: scanParameters.format
                                                                  lastFrame: scanParameters.last_frame
                                                               bytesPerLine: scanParameters.bytes_per_line
                                                               pixelsPerLin: scanParameters.pixels_per_line
                                                                      lines: scanParameters.lines
                                                                      depth: scanParameters.depth];
    
    return [parameters autorelease];
}


/**
 * Reads all options available from the current device and processes them into SKScanOption objects.
 *
 * @return NSArray instance returning all valid options as SKScanOption objects
 */
-(NSArray*) scanOptions
{
    SANE_Int numOptions = 0;
    SANE_Status optionStatus = 0;
    const SANE_Option_Descriptor* optionDescr;
    
    optionDescr = sane_get_option_descriptor(handle->deviceHandle, 0);
    if (!optionDescr)
    {
    	NSLog(@"Unable to retrieve options");
        return nil;
    }
    
    optionStatus = [self getValue: &numOptions forOptionWithIndex: 0];
    if (SANE_STATUS_GOOD != optionStatus)
    {
    	NSLog(@"Error retrieving number of available options");
        return nil;
    }

    NSMutableArray* optionsArray = [NSMutableArray arrayWithCapacity: numOptions];
    SKScanOption* option;
    
    for (int i = 0; i < numOptions; ++i)
    {
        optionDescr = sane_get_option_descriptor(handle->deviceHandle, i);
        if (!optionDescr || !optionDescr->name || !optionDescr->type)
            continue;

        if ( (SANE_TYPE_FIXED == optionDescr->type || SANE_TYPE_INT == optionDescr->type)
             && (sizeof(SANE_Int) == optionDescr->size))
        {
            SANE_Int value = 0;
            optionStatus = [self getValue: &value forOptionWithIndex: i];

            if (SANE_STATUS_GOOD != optionStatus)
                continue;
            
            option = [[SKScanOption alloc] initWithIntValue: value
                                                 optionName: [NSString stringWithCString: optionDescr->name]
                                                optionIndex: i];
        }
        else if (SANE_TYPE_STRING == optionDescr->type && 0 < optionDescr->size)
        {
            SANE_String value = calloc(optionDescr->size, sizeof(SANE_Char));
            optionStatus = [self getValue: value forOptionWithIndex: i];
            
            if (SANE_STATUS_GOOD != optionStatus)
                continue;

            option = [[SKScanOption alloc] initWithCStringValue: value
                                                     optionName: [NSString stringWithCString: optionDescr->name]
                                                    optionIndex: i];
            free(value);
        }
        else if (SANE_TYPE_BOOL == optionDescr->type
                 && (sizeof(SANE_Word) == optionDescr->size))
        {
            SANE_Bool value = SANE_FALSE;
            optionStatus = [self getValue: &value forOptionWithIndex: i];

            if (SANE_STATUS_GOOD != optionStatus)
                continue;

            option = [[SKScanOption alloc] initWithBoolValue: ((SANE_TRUE == value) ? YES : NO)
                                                 optionName: [NSString stringWithCString: optionDescr->name]
                                                optionIndex: i];
        }
        else
        {
            NSString* infoString = [NSString stringWithFormat: @"Type: %d", optionDescr->type];
            option = [[SKScanOption alloc] initWithStringValue: infoString
                                                    optionName: [NSString stringWithCString: optionDescr->name]
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

            [option autorelease];
            [optionsArray addObject: option];
        }
    }

    // turn mutable array into non mutable array
    return [NSArray arrayWithArray: optionsArray];
}


/**
 * This method takes an instance of SKScanOption and sets the value on the current scan device.
 */
-(BOOL) setScanOption:(SKScanOption*) theOption
{
	SANE_Status setStatus = [self setValue: [theOption value] forOptionWithIndex: [theOption index]];
    
    if (SANE_INFO_INEXACT & setStatus)
        NSLog(@"Option value was rounded upon setting the option");
    else if (SANE_INFO_RELOAD_OPTIONS & setStatus)
        NSLog(@"Application should reload all options (multiple options have been affected by setting this one)");
    else if (SANE_INFO_RELOAD_PARAMS & setStatus)
        NSLog(@"Application should reload all parameters (multiple parameters have been affected by setting this option)");
    return YES;
}



/**
 * This method does a basic scan but currently doesn't do anything with the read data.
 */
-(BOOL) doScan
{
	SANE_Status scanStatus = 0;
    SANE_Parameters scanParameters;
    
    scanStatus = sane_start (handle->deviceHandle);
    if (SANE_STATUS_GOOD != scanStatus)
    {
        NSLog(@"Sane start error: %s", sane_strstatus(scanStatus));
        return NO;
    }
    
    do
    {
        SKScanParameters* parameters = [self scanParameters];
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
        NSBitmapImageRep* bitmap = [[NSBitmapImageRep alloc]
                                    initWithBitmapDataPlanes: &buffer
                                    pixelsWide: [parameters widthPixel]
                                    pixelsHigh: [parameters heightPixel]
                                    bitsPerSample: 8
                                    samplesPerPixel: 3  // or 4 with alpha
                                    hasAlpha: NO
                                    isPlanar: NO // only use the first element of buffer
                                    colorSpaceName: NSDeviceRGBColorSpace
                                    bitmapFormat: 0
                                    bytesPerRow: [parameters widthPixel] * 3  // 0 == determine automatically
                                    bitsPerPixel: [parameters bitsPerPixel]];  // 0 == determine automatically
        
        if (nil != bitmap)
        {
            NSDictionary* imageProperties = [NSDictionary dictionaryWithObject:[NSNumber numberWithFloat:1.0] forKey:NSImageCompressionFactor];
            NSData* bitmapData = [bitmap representationUsingType: NSTIFFFileType properties: imageProperties];
            [bitmapData writeToFile: @"test.tiff" atomically: NO];
        }
        free(buffer);
    }
    while (!scanParameters.last_frame);
    
    sane_cancel(handle->deviceHandle);
    
    return YES;
}


@end
