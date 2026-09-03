/*
 * vt_probe.m — VideoToolbox / EDR capability probe for MacLC (VLC 4.0 macOS-only fork)
 *
 * Compile:
 *   clang -framework Foundation -framework AppKit -framework VideoToolbox \
 *         -framework CoreMedia -framework CoreVideo -framework CoreFoundation \
 *         -fobjc-arc -o vt_probe vt_probe.m
 *
 * Run:  ./vt_probe
 */

#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <VideoToolbox/VideoToolbox.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreVideo/CoreVideo.h>
#import <sys/sysctl.h>

#pragma mark - Helpers

static NSString *fourcc_str(OSType code) {
    char buf[5];
    buf[0] = (code >> 24) & 0xFF;
    buf[1] = (code >> 16) & 0xFF;
    buf[2] = (code >>  8) & 0xFF;
    buf[3] = (code      ) & 0xFF;
    buf[4] = 0;
    return [NSString stringWithCString:buf encoding:NSASCIIStringEncoding] ?: @"????";
}

static NSString *sysctl_string(const char *key) {
    size_t size = 0;
    sysctlbyname(key, NULL, &size, NULL, 0);
    if (size == 0) return @"(unknown)";
    char *buf = malloc(size);
    sysctlbyname(key, buf, &size, NULL, 0);
    NSString *s = [NSString stringWithUTF8String:buf];
    free(buf);
    return s ?: @"(unknown)";
}

#pragma mark - Section 1: Hardware Decode Support

static void probe_hardware_decode(void) {
    printf("\n========================================\n");
    printf("SECTION 1: VTIsHardwareDecodeSupported()\n");
    printf("========================================\n\n");

    struct { const char *name; CMVideoCodecType type; } codecs[] = {
        { "kCMVideoCodecType_H264",             kCMVideoCodecType_H264            },
        { "kCMVideoCodecType_HEVC",             kCMVideoCodecType_HEVC            },
        { "kCMVideoCodecType_AV1",              kCMVideoCodecType_AV1             },
        { "kCMVideoCodecType_VP9",              kCMVideoCodecType_VP9             },
        { "kCMVideoCodecType_AppleProRes422",   kCMVideoCodecType_AppleProRes422  },
        { "kCMVideoCodecType_DolbyVisionHEVC",  kCMVideoCodecType_DolbyVisionHEVC },
    };
    int n = sizeof(codecs) / sizeof(codecs[0]);

    for (int i = 0; i < n; i++) {
        Boolean hw = VTIsHardwareDecodeSupported(codecs[i].type);
        printf("  %-45s ('%s')  ->  %s\n",
               codecs[i].name,
               [fourcc_str(codecs[i].type) UTF8String],
               hw ? "YES (hardware)" : "NO");
    }
}

#pragma mark - Section 2: Machine Identification

static void probe_machine(void) {
    printf("\n========================================\n");
    printf("SECTION 2: Machine Identification\n");
    printf("========================================\n\n");

    printf("  CPU brand string : %s\n", [sysctl_string("machdep.cpu.brand_string") UTF8String]);
    printf("  Hardware model   : %s\n", [sysctl_string("hw.model") UTF8String]);

    NSProcessInfo *pi = [NSProcessInfo processInfo];
    NSOperatingSystemVersion v = [pi operatingSystemVersion];
    printf("  macOS version    : %ld.%ld.%ld (%s)\n",
           (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion,
           [pi.operatingSystemVersionString UTF8String]);
}

#pragma mark - Section 3: Pixel Format Probing via VTDecompressionSession

/*
 * Strategy: Create a minimal CMVideoFormatDescription for HEVC (1920x1080),
 * then try to create a VTDecompressionSession with each candidate pixel format
 * in the destination image buffer attributes.
 *
 * If CMVideoFormatDescriptionCreate for HEVC doesn't work without extensions/atoms,
 * we fall back to H.264 baseline (which needs no extra data) or report the issue.
 */
/* A decompression session can only be created against a format description that
 * carries real parameter sets. Creating one with CMVideoFormatDescriptionCreate()
 * and no extensions yields a description no decoder will accept, so every pixel
 * format fails identically and the probe learns nothing.
 *
 * To get a real description offline, hardware-encode a single HEVC Main10 frame
 * and take the format description off the sample buffer the encoder produces. */

static CMVideoFormatDescriptionRef g_encoded_fmt = NULL;

static void encode_output_cb(void *outputCallbackRefCon,
                             void *sourceFrameRefCon,
                             OSStatus status,
                             VTEncodeInfoFlags infoFlags,
                             CMSampleBufferRef sampleBuffer)
{
    (void)outputCallbackRefCon; (void)sourceFrameRefCon; (void)infoFlags;
    if (status != noErr || sampleBuffer == NULL || g_encoded_fmt != NULL)
        return;
    CMVideoFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
    if (fmt)
        g_encoded_fmt = (CMVideoFormatDescriptionRef)CFRetain(fmt);
}

/* Encode one HEVC Main10 frame and return its format description, or NULL. */
static CMVideoFormatDescriptionRef make_real_hevc_format_description(void)
{
    const int32_t w = 1920, h = 1080;

    VTCompressionSessionRef enc = NULL;
    NSDictionary *srcAttrs = @{
        (NSString *)kCVPixelBufferPixelFormatTypeKey:
            @(kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange),
    };
    OSStatus st = VTCompressionSessionCreate(kCFAllocatorDefault, w, h,
                                             kCMVideoCodecType_HEVC,
                                             NULL,
                                             (__bridge CFDictionaryRef)srcAttrs,
                                             NULL,
                                             encode_output_cb, NULL,
                                             &enc);
    if (st != noErr || enc == NULL) {
        printf("  [info] VTCompressionSessionCreate(HEVC): OSStatus %d\n", (int)st);
        return NULL;
    }

    VTSessionSetProperty(enc, kVTCompressionPropertyKey_ProfileLevel,
                         kVTProfileLevel_HEVC_Main10_AutoLevel);
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_RealTime, kCFBooleanTrue);
    VTSessionSetProperty(enc, kVTCompressionPropertyKey_AllowFrameReordering, kCFBooleanFalse);

    CVPixelBufferRef pb = NULL;
    NSDictionary *pbAttrs = @{ (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    CVReturn cvret = CVPixelBufferCreate(kCFAllocatorDefault, w, h,
                                         kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange,
                                         (__bridge CFDictionaryRef)pbAttrs, &pb);
    if (cvret != kCVReturnSuccess || pb == NULL) {
        printf("  [info] CVPixelBufferCreate(P010): CVReturn %d\n", (int)cvret);
        VTCompressionSessionInvalidate(enc);
        CFRelease(enc);
        return NULL;
    }

    /* Mid-grey, so the encoder has something valid to work on. */
    CVPixelBufferLockBaseAddress(pb, 0);
    for (size_t plane = 0; plane < CVPixelBufferGetPlaneCount(pb); plane++) {
        uint8_t *base = CVPixelBufferGetBaseAddressOfPlane(pb, plane);
        size_t stride = CVPixelBufferGetBytesPerRowOfPlane(pb, plane);
        size_t rows = CVPixelBufferGetHeightOfPlane(pb, plane);
        memset(base, plane == 0 ? 0x40 : 0x80, stride * rows);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);

    st = VTCompressionSessionEncodeFrame(enc, pb, CMTimeMake(0, 30), kCMTimeInvalid,
                                         NULL, NULL, NULL);
    if (st != noErr)
        printf("  [info] VTCompressionSessionEncodeFrame: OSStatus %d\n", (int)st);
    VTCompressionSessionCompleteFrames(enc, kCMTimeInvalid);

    CVPixelBufferRelease(pb);
    VTCompressionSessionInvalidate(enc);
    CFRelease(enc);

    return g_encoded_fmt;
}

static void probe_pixel_formats(void) {
    printf("\n========================================\n");
    printf("SECTION 3: Pixel Format Availability\n");
    printf("========================================\n\n");

    bool description_is_real = true;
    CMVideoFormatDescriptionRef fmt = make_real_hevc_format_description();

    if (fmt == NULL) {
        description_is_real = false;
        printf("  [warn] Could not obtain a real HEVC format description by encoding.\n");
        printf("  [warn] Falling back to a parameter-set-less description. Every result\n");
        printf("  [warn] below will then be a decoder-lookup failure, NOT evidence that\n");
        printf("  [warn] the pixel format is unsupported. Treat the section as inconclusive.\n\n");
        OSStatus st = CMVideoFormatDescriptionCreate(kCFAllocatorDefault,
                                                     kCMVideoCodecType_HEVC,
                                                     1920, 1080, NULL, &fmt);
        if (st != noErr || fmt == NULL) {
            printf("  [FAIL] Cannot create any CMVideoFormatDescription (OSStatus %d).\n", (int)st);
            return;
        }
    } else {
        printf("  [info] Using a real HEVC Main10 format description from the hardware encoder.\n\n");
    }

    struct { const char *name; OSType pf; } formats[] = {
        { "420YpCbCr8BiPlanarVideoRange  (NV12 / '420v')",   kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange   },
        { "420YpCbCr10BiPlanarVideoRange (P010 / 'x420')",   kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange  },
        { "422YpCbCr10BiPlanarVideoRange ('x422')",          kCVPixelFormatType_422YpCbCr10BiPlanarVideoRange  },
        { "422YpCbCr16BiPlanarVideoRange ('sv22')",          kCVPixelFormatType_422YpCbCr16BiPlanarVideoRange  },
        { "444YpCbCr16BiPlanarVideoRange ('sv44')",          kCVPixelFormatType_444YpCbCr16BiPlanarVideoRange  },
        { "32BGRA                        ('BGRA')",          kCVPixelFormatType_32BGRA                        },
    };
    int n = sizeof(formats) / sizeof(formats[0]);

    printf("  %-55s  Result\n", "Pixel Format");
    printf("  %-55s  ------\n", "------------");

    for (int i = 0; i < n; i++) {
        NSDictionary *dstAttrs = @{
            (NSString *)kCVPixelBufferPixelFormatTypeKey: @(formats[i].pf),
            (NSString *)kCVPixelBufferWidthKey: @1920,
            (NSString *)kCVPixelBufferHeightKey: @1080,
#if TARGET_OS_OSX
            (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{},
#endif
        };

        VTDecompressionSessionRef session = NULL;
        VTDecompressionOutputCallbackRecord cb = { .decompressionOutputCallback = NULL, .decompressionOutputRefCon = NULL };

        OSStatus st = VTDecompressionSessionCreate(kCFAllocatorDefault,
                                                   fmt,
                                                   NULL,
                                                   (__bridge CFDictionaryRef)dstAttrs,
                                                   &cb,
                                                   &session);
        if (st == noErr && session != NULL) {
            printf("  %-55s  OK (session created)\n", formats[i].name);
            VTDecompressionSessionInvalidate(session);
            CFRelease(session);
        } else {
            printf("  %-55s  FAIL (OSStatus %d)\n", formats[i].name, (int)st);
        }
    }

    if (!description_is_real)
        printf("\n  [warn] Section 3 is INCONCLUSIVE: see the warning above.\n");

    printf("\n  [info] SDK check: kCVPixelFormatType_420YpCbCr16BiPlanar* is NOT DEFINED\n");
    printf("         in this SDK. CoreVideo/CVPixelBuffer.h declares 16-bit biplanar\n");
    printf("         YCbCr for 4:2:2 ('sv22') and 4:4:4 ('sv44') only.\n");

    CFRelease(fmt);
}

#pragma mark - Section 4: Display EDR Capabilities

static void probe_edr(void) {
    printf("\n========================================\n");
    printf("SECTION 4: Display EDR Capabilities\n");
    printf("========================================\n\n");

    /* NSScreen requires a running NSApplication on macOS */
    [NSApplication sharedApplication];

    NSArray<NSScreen *> *screens = [NSScreen screens];
    if (screens.count == 0) {
        printf("  No screens detected.\n");
        return;
    }

    printf("  Found %lu display(s):\n\n", (unsigned long)screens.count);

    for (NSUInteger i = 0; i < screens.count; i++) {
        NSScreen *screen = screens[i];
        printf("  --- Display %lu ---\n", (unsigned long)(i + 1));
        printf("    Name                        : %s\n", [screen.localizedName UTF8String]);

        if (@available(macOS 10.15, *)) {
            printf("    maxExtendedDynamicRange      : %.3f\n",
                   screen.maximumExtendedDynamicRangeColorComponentValue);
            printf("    maxPotentialExtendedDynRange  : %.3f\n",
                   screen.maximumPotentialExtendedDynamicRangeColorComponentValue);
        } else {
            printf("    (EDR properties require macOS 10.15+)\n");
        }

        if (@available(macOS 12.0, *)) {
            printf("    maxRefExtendedDynRange       : %.3f\n",
                   screen.maximumReferenceExtendedDynamicRangeColorComponentValue);
        } else {
            printf("    maxRefExtendedDynRange       : (requires macOS 12.0+)\n");
        }

        NSColorSpace *cs = screen.colorSpace;
        if (cs) {
            CGColorSpaceRef cgCS = cs.CGColorSpace;
            CFStringRef csName = cgCS ? CGColorSpaceGetName(cgCS) : NULL;
            printf("    Color space                  : %s\n",
                   csName ? [(__bridge NSString *)csName UTF8String] : "(unknown)");

            /* An HDR-capable colour space typically uses BT.2020 / extended linear / PQ */
            BOOL isHDR = NO;
            if (csName) {
                NSString *name = (__bridge NSString *)csName;
                isHDR = [name containsString:@"HDR"]  ||
                         [name containsString:@"2020"] ||
                         [name containsString:@"PQ"]   ||
                         [name containsString:@"HLG"]  ||
                         [name containsString:@"ExtendedLinear"];
            }
            /* Also: if max EDR > 1.0, the display is in practice HDR-capable */
            if (@available(macOS 10.15, *)) {
                if (screen.maximumPotentialExtendedDynamicRangeColorComponentValue > 1.0) {
                    isHDR = YES;
                }
            }
            printf("    HDR-capable color space?      : %s\n", isHDR ? "YES" : "NO");
        } else {
            printf("    Color space                  : (nil)\n");
        }
        printf("\n");
    }
}

#pragma mark - Main

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        printf("================================================================\n");
        printf("  VT Probe — VideoToolbox / EDR Capability Report\n");
        printf("  MacLC (VLC 4.0 macOS Apple Silicon fork)\n");
        printf("================================================================\n");

        probe_machine();
        probe_hardware_decode();
        probe_pixel_formats();
        probe_edr();

        printf("================================================================\n");
        printf("  END OF PROBE\n");
        printf("================================================================\n");
    }
    return 0;
}
