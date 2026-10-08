// SPDX-License-Identifier: MIT
// Copyright (c) 2026 Nabeel Hassan
// Renders the app icon (1024x1024 PNG): a remote display above a Touch Bar strip with lit keys.
// Usage: make_icon <output.png>

#import <Cocoa/Cocoa.h>

static NSImage *Symbol(NSString *name, CGFloat size, NSFontWeight weight, NSColor *color) {
    NSImageSymbolConfiguration *cfg = [NSImageSymbolConfiguration configurationWithPointSize:size weight:weight];
    NSImage *base = [[NSImage imageWithSystemSymbolName:name accessibilityDescription:nil] imageWithSymbolConfiguration:cfg];
    if (!base) return nil;
    NSImage *tinted = [NSImage imageWithSize:base.size flipped:NO drawingHandler:^BOOL(NSRect r) {
        [base drawInRect:r];
        [color set];
        NSRectFillUsingOperation(r, NSCompositingOperationSourceAtop);
        return YES;
    }];
    return tinted;
}

static void DrawCentered(NSImage *img, NSPoint center) {
    if (!img) return;
    NSRect r = NSMakeRect(center.x - img.size.width / 2, center.y - img.size.height / 2, img.size.width, img.size.height);
    [img drawInRect:r];
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc < 2) { fprintf(stderr, "usage: make_icon out.png\n"); return 1; }
        const CGFloat S = 1024;
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithBitmapDataPlanes:NULL pixelsWide:S pixelsHigh:S
                                    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
                                    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0];
        [NSGraphicsContext saveGraphicsState];
        [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithBitmapImageRep:rep]];

        // macOS icon grid: 824pt body, ~185pt corner radius, soft drop shadow.
        NSRect body = NSMakeRect(100, 100, 824, 824);
        NSBezierPath *squircle = [NSBezierPath bezierPathWithRoundedRect:body xRadius:185 yRadius:185];
        [NSGraphicsContext saveGraphicsState];
        NSShadow *shadow = [[NSShadow alloc] init];
        shadow.shadowColor = [NSColor colorWithWhite:0 alpha:0.35];
        shadow.shadowBlurRadius = 28;
        shadow.shadowOffset = NSMakeSize(0, -12);
        [shadow set];
        [[NSColor blackColor] set];
        [squircle fill];
        [NSGraphicsContext restoreGraphicsState];

        NSGradient *bg = [[NSGradient alloc] initWithColors:@[
            [NSColor colorWithSRGBRed:0.13 green:0.20 blue:0.45 alpha:1],
            [NSColor colorWithSRGBRed:0.24 green:0.36 blue:0.85 alpha:1],
            [NSColor colorWithSRGBRed:0.47 green:0.31 blue:0.93 alpha:1]]];
        [bg drawInBezierPath:squircle angle:-60];

        // Soft glow behind the display.
        NSGradient *glow = [[NSGradient alloc] initWithStartingColor:[NSColor colorWithWhite:1 alpha:0.22]
                                                         endingColor:[NSColor colorWithWhite:1 alpha:0]];
        [NSGraphicsContext saveGraphicsState];
        [squircle addClip];
        [glow drawFromCenter:NSMakePoint(512, 640) radius:0 toCenter:NSMakePoint(512, 640) radius:420 options:0];
        [NSGraphicsContext restoreGraphicsState];

        // Remote display.
        DrawCentered(Symbol(@"display", 330, NSFontWeightSemibold, [NSColor whiteColor]), NSMakePoint(512, 600));
        // Small cursor on the display, like a remote session.
        DrawCentered(Symbol(@"cursorarrow", 92, NSFontWeightBold, [NSColor colorWithSRGBRed:0.38 green:0.65 blue:1 alpha:1]),
                     NSMakePoint(560, 630));

        // Touch Bar strip with keys.
        NSRect strip = NSMakeRect(170, 205, 684, 128);
        NSBezierPath *stripPath = [NSBezierPath bezierPathWithRoundedRect:strip xRadius:30 yRadius:30];
        [[NSColor colorWithSRGBRed:0.05 green:0.06 blue:0.10 alpha:0.92] set];
        [stripPath fill];
        [[NSColor colorWithWhite:1 alpha:0.18] set];
        stripPath.lineWidth = 4;
        [stripPath stroke];

        NSArray *keys = @[@{@"sym": @"cursorarrow.rays", @"on": @YES},
                          @{@"sym": @"arrow.up.left.and.arrow.down.right", @"on": @YES},
                          @{@"sym": @"square.grid.3x2", @"on": @NO},
                          @{@"sym": @"rectangle.3.group", @"on": @NO}];
        CGFloat keyW = 146, keyH = 92, gap = 18;
        CGFloat x = strip.origin.x + (strip.size.width - (keys.count * keyW + (keys.count - 1) * gap)) / 2;
        for (NSDictionary *k in keys) {
            NSRect kr = NSMakeRect(x, strip.origin.y + (strip.size.height - keyH) / 2, keyW, keyH);
            NSBezierPath *kp = [NSBezierPath bezierPathWithRoundedRect:kr xRadius:18 yRadius:18];
            if ([k[@"on"] boolValue]) [[NSColor colorWithSRGBRed:0.23 green:0.51 blue:0.96 alpha:1] set];
            else [[NSColor colorWithSRGBRed:0.25 green:0.26 blue:0.30 alpha:1] set];
            [kp fill];
            DrawCentered(Symbol(k[@"sym"], 44, NSFontWeightSemibold, [NSColor whiteColor]), NSMakePoint(NSMidX(kr), NSMidY(kr)));
            x += keyW + gap;
        }

        [NSGraphicsContext restoreGraphicsState];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToFile:[NSString stringWithUTF8String:argv[1]] atomically:YES]) return 1;
    }
    return 0;
}
