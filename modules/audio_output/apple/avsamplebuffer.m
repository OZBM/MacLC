/*****************************************************************************
 * avsamplebuffer.m: AVSampleBufferRender plugin for iOS and macOS
 *****************************************************************************
 * Copyright (C) 2024 VLC authors, VideoLAN and VideoLABS
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
 * GNU Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this program; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin Street, Fifth Floor, Boston MA 02110-1301, USA.
 *****************************************************************************/

#import "config.h"

#import <TargetConditionals.h>
#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#if TARGET_OS_OSX
#import <CoreAudio/CoreAudio.h>
#endif

#import <vlc_common.h>
#import <vlc_plugin.h>
#import <vlc_aout.h>
#import <vlc_charset.h>

#if TARGET_OS_IPHONE || TARGET_OS_TV || TARGET_OS_VISION
#define HAS_AVAUDIOSESSION
#import "avaudiosession_common.h"
#endif

#import "channel_layout.h"
#import "eac3_dec3.h"
#if TARGET_OS_OSX
#import "atmos_prime.h"
#endif

// for (void)setRate:(float)rate time:(CMTime)time atHostTime:(CMTime)hostTime
#define MIN_MACOS 11.3
#define MIN_IOS 14.5
#define MIN_TVOS 14.5
#define MIN_WATCHOS 7.4

#define ATS_PASSTHROUGH_TEXT N_("Pass through Dolby Atmos (E-AC-3 JOC)")
#define ATS_PASSTHROUGH_LONGTEXT N_("Send compressed E-AC-3/Atmos streams to " \
    "Apple's native renderer. Disable to decode to PCM instead (A/B test).")

// work-around to fix compilation on older Xcode releases
#if defined(TARGET_OS_VISION) && TARGET_OS_VISION
    #define MIN_VISIONOS 1.0
    #define VISIONOS_API_AVAILABLE , visionos(MIN_VISIONOS)
#else
    #define VISIONOS_API_AVAILABLE
#endif

#pragma mark Private

API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS) VISIONOS_API_AVAILABLE)
@interface VLCAVSample : NSObject
{
    audio_output_t *_aout;

    CMAudioFormatDescriptionRef _fmtDesc;
    AVSampleBufferAudioRenderer *_renderer;
    AVSampleBufferRenderSynchronizer *_sync;
    id _observer;
    dispatch_queue_t _dataQueue;
    dispatch_queue_t _timeQueue;
    size_t _bytesPerFrame;

    uint8_t _chanTable[AOUT_CHAN_MAX];
    unsigned _chansToReorder;
    BOOL _encoded;
    BOOL _encodedWaiting;
    unsigned _encodedFramesPerPacket;
#if TARGET_OS_OSX
    BOOL _listeningDevices;
#endif
#if TARGET_OS_OSX
    NSString *_deviceUID;
    BOOL _useDefaultDevice;
#endif

    vlc_mutex_t _bufferLock;
    vlc_cond_t _bufferWait;

    block_t *_outChain;
    block_t **_outChainLast;

    int64_t _ptsSamples;
    vlc_tick_t _firstPts;
    vlc_tick_t _lastDate;
    unsigned _sampleRate;
    BOOL _stopped;
    BOOL _dateReached;
}

- (void)reportDevices;
- (void)stopDeviceListener;
- (void)updateDefaultDevice;
@end

#if TARGET_OS_OSX
/* VLC's macOS device menu identifies outputs by their numeric Core Audio ID,
 * like the auhal output does; "0" is the system default. */
static void
ReportDevices(audio_output_t *aout)
{
    aout_HotplugReport(aout, "0", _("System Sound Output Device"));

    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    UInt32 size;
    if (AudioObjectGetPropertyDataSize(kAudioObjectSystemObject, &addr, 0,
                                       NULL, &size) != noErr)
        return;

    UInt32 count = size / sizeof(AudioDeviceID);
    if (count == 0)
        return;

    AudioDeviceID *devices = vlc_alloc(count, sizeof(*devices));
    if (devices == NULL)
        return;
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL,
                                   &size, devices) != noErr)
    {
        free(devices);
        return;
    }

    for (UInt32 i = 0; i < count; ++i)
    {
        AudioDeviceID device = devices[i];

        AudioObjectPropertyAddress streams = {
            .mSelector = kAudioDevicePropertyStreams,
            .mScope = kAudioDevicePropertyScopeOutput,
            .mElement = kAudioObjectPropertyElementMain,
        };
        UInt32 streams_size;
        if (AudioObjectGetPropertyDataSize(device, &streams, 0, NULL,
                                           &streams_size) != noErr
         || streams_size == 0)
            continue; /* input-only device */

        AudioObjectPropertyAddress name_addr = {
            .mSelector = kAudioObjectPropertyName,
            .mScope = kAudioObjectPropertyScopeGlobal,
            .mElement = kAudioObjectPropertyElementMain,
        };
        CFStringRef cfname = NULL;
        UInt32 name_size = sizeof(cfname);
        if (AudioObjectGetPropertyData(device, &name_addr, 0, NULL, &name_size,
                                       &cfname) != noErr)
            continue;

        char *name = FromCFString(cfname, kCFStringEncodingUTF8);
        CFRelease(cfname);
        if (name == NULL)
            continue;

        char id[12];
        snprintf(id, sizeof(id), "%u", (unsigned) device);
        aout_HotplugReport(aout, id, name);
        free(name);
    }

    free(devices);
}

static OSStatus
DeviceListChanged(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                  const AudioObjectPropertyAddress *inAddresses,
                  void *inClientData)
{
    VLCAVSample *self = (__bridge VLCAVSample *) inClientData;
    [self reportDevices];
    [self updateDefaultDevice];
    return noErr;
}

static OSStatus
DefaultDeviceChanged(AudioObjectID inObjectID, UInt32 inNumberAddresses,
                     const AudioObjectPropertyAddress *inAddresses,
                     void *inClientData)
{
    VLCAVSample *self = (__bridge VLCAVSample *) inClientData;
    [self updateDefaultDevice];
    return noErr;
}

/* AVSampleBufferAudioRenderer takes the device UID, not its Core Audio ID. */
static NSString *
CopyDeviceUID(AudioDeviceID device)
{
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioDevicePropertyDeviceUID,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    CFStringRef uid = NULL;
    UInt32 size = sizeof(uid);
    if (AudioObjectGetPropertyData(device, &addr, 0, NULL, &size, &uid) != noErr)
        return nil;
    return CFBridgingRelease(uid);
}

static NSString *
CopyDefaultDeviceUID(void)
{
    AudioObjectPropertyAddress addr = {
        .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    AudioDeviceID device;
    UInt32 size = sizeof(device);
    if (AudioObjectGetPropertyData(kAudioObjectSystemObject, &addr, 0, NULL,
                                   &size, &device) != noErr)
        return nil;
    return CopyDeviceUID(device);
}

#endif

@implementation VLCAVSample

- (id)init:(audio_output_t*)aout
{
    _aout = aout;
    _dataQueue = dispatch_queue_create("VLC AVSampleBuffer data queue", DISPATCH_QUEUE_SERIAL);
    if (_dataQueue == nil)
        return nil;

    _timeQueue = dispatch_queue_create("VLC AVSampleBuffer time queue", DISPATCH_QUEUE_SERIAL);
    if (_timeQueue == nil)
        return nil;

    vlc_mutex_init(&_bufferLock);
    vlc_cond_init(&_bufferWait);

    _outChain = NULL;
    _outChainLast = &_outChain;

    /* The first call to CMAudioFormatDescriptionCreate() might take some time
     * (between 200 and 600ms) as it is initializing some static context/libs.
     * Therefore, call it from the Open() callback with dummy params. Indeed,
     * the playback is not yet started and a longer Open() call won't mess with
     * playback timings. */
    static const AudioStreamBasicDescription dummyDesc = {
        .mSampleRate = 48000,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mChannelsPerFrame = 2,
        .mFramesPerPacket = 1,
        .mBitsPerChannel = 32,
    };
    CMAudioFormatDescriptionRef dummyFmtDesc;
    OSStatus status =
        CMAudioFormatDescriptionCreate(kCFAllocatorDefault, &dummyDesc, 0, nil,
                                       0, nil, nil, &dummyFmtDesc);
    if (status == noErr)
        CFRelease(dummyFmtDesc);

    self = [super init];
    if (self == nil)
        return nil;

    return self;
}

- (void)dealloc
{
    [self stopDeviceListener];
    assert(_outChain == NULL);
}

static void
customBlock_Free(void *refcon, void *doomedMemoryBlock, size_t sizeInBytes)
{
    block_t *block = refcon;

    assert(block->i_buffer == sizeInBytes);
    block_Release(block);

    (void) doomedMemoryBlock;
    (void) sizeInBytes;
}

- (CMSampleBufferRef)wrapBuffer:(block_t **)pblock
{
    // This function take the block ownership
    block_t *block = *pblock;
    *pblock = NULL;

    const CMBlockBufferCustomBlockSource blockSource = {
        .version = kCMBlockBufferCustomBlockSourceVersion,
        .FreeBlock = customBlock_Free,
        .refCon = block,
    };

    OSStatus status;
    CMBlockBufferRef blockBuf;
    status = CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                                block->p_buffer,  // memoryBlock
                                                block->i_buffer,  // blockLength
                                                NULL,             // blockAllocator
                                                &blockSource,     // customBlockSource
                                                0,                // offsetToData
                                                block->i_buffer,  // dataLength
                                                0,                // flags
                                                &blockBuf);
    if (status != noErr)
    {
        msg_Err(_aout, "CMBlockBufferRef creation failure %li", (long)status);
        block_Release(block);
        return nil;
    }

    const CMSampleTimingInfo timeInfo = {
        .duration = kCMTimeInvalid,
        .presentationTimeStamp = CMTimeMake(_ptsSamples, _sampleRate),
        .decodeTimeStamp = kCMTimeInvalid,
    };

    CMSampleBufferRef sampleBuf;
    status = CMSampleBufferCreateReady(kCFAllocatorDefault,
                                       blockBuf,             // dataBuffer
                                       _fmtDesc,             // formatDescription
                                       block->i_nb_samples,  // numSamples
                                       1,                    // numSampleTimingEntries
                                       &timeInfo,            // sampleTimingArray
                                       1,                    // numSampleSizeEntries
                                       &_bytesPerFrame,      // sampleSizeArray
                                       &sampleBuf);
    CFRelease(blockBuf);

    if (status != noErr)
    {
        msg_Warn(_aout, "CMSampleBufferRef creation failure %li", (long)status);
        return nil;
    }

    return sampleBuf;
}

- (CMSampleBufferRef)wrapEncodedBuffer:(block_t **)pblock
{
    // This function take the block ownership
    block_t *block = *pblock;
    *pblock = NULL;

    const CMBlockBufferCustomBlockSource blockSource = {
        .version = kCMBlockBufferCustomBlockSourceVersion,
        .FreeBlock = customBlock_Free,
        .refCon = block,
    };

    CMBlockBufferRef blockBuf;
    OSStatus status =
        CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,
                                           block->p_buffer,
                                           block->i_buffer,
                                           NULL,          /* blockAllocator */
                                           &blockSource,  /* customBlockSource */
                                           0,             /* offsetToData */
                                           block->i_buffer,
                                           0,             /* flags */
                                           &blockBuf);
    if (status != noErr)
    {
        msg_Err(_aout, "CMBlockBufferRef creation failure %li", (long) status);
        block_Release(block);
        return nil;
    }

    /* One compressed E-AC-3 access unit per sample buffer. The renderer reads
     * its duration from the format description's frames-per-packet field. */
    const AudioStreamPacketDescription packet = {
        .mStartOffset = 0,
        .mVariableFramesInPacket = 0,
        .mDataByteSize = block->i_buffer,
    };

    CMSampleBufferRef sampleBuf;
    status = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
        kCFAllocatorDefault,
        blockBuf,            /* dataBuffer */
        _fmtDesc,            /* formatDescription */
        1,                   /* sampleCount */
        CMTimeMake(_ptsSamples, _sampleRate),
        &packet,             /* packetDescriptions */
        &sampleBuf);
    CFRelease(blockBuf);

    if (status != noErr)
    {
        msg_Warn(_aout, "CMSampleBufferRef creation failure %li", (long) status);
        return nil;
    }

    return sampleBuf;
}

- (void)reportDevices
{
#if TARGET_OS_OSX
    ReportDevices(_aout);
#endif
}

- (void)updateDefaultDevice
{
#if TARGET_OS_OSX
    if (!_useDefaultDevice || _renderer == nil)
        return;
    NSString *uid = CopyDefaultDeviceUID();
    if (uid != nil)
        _renderer.audioOutputDeviceUniqueID = uid;
#endif
}

- (void)stopDeviceListener
{
#if TARGET_OS_OSX
    if (!_listeningDevices)
        return;

    AudioObjectPropertyAddress devices = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &devices,
                                      DeviceListChanged, (__bridge void *) self);
    AudioObjectPropertyAddress defdev = {
        .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    AudioObjectRemovePropertyListener(kAudioObjectSystemObject, &defdev,
                                      DefaultDeviceChanged, (__bridge void *) self);
    _listeningDevices = NO;
#endif
}

- (void)selectDevice:(const char *)name
{
#if TARGET_OS_OSX
    /* The interface passes Core Audio IDs (see ReportDevices); "0" and an
     * empty string mean the system default. */
    NSString *uid;
    if (name == NULL || name[0] == '\0' || strcmp(name, "0") == 0)
    {
        /* The renderer property does not accept nil; resolve the current
         * default output instead and follow future default changes. */
        _useDefaultDevice = YES;
        uid = CopyDefaultDeviceUID();
    }
    else
    {
        _useDefaultDevice = NO;
        char *end;
        unsigned long device = strtoul(name, &end, 10);
        if (end != NULL && *end == '\0' && device <= UINT32_MAX)
            uid = CopyDeviceUID((AudioDeviceID) device);
        else
            uid = @(name);
    }

    _deviceUID = uid;
    if (_renderer != nil && uid != nil)
        _renderer.audioOutputDeviceUniqueID = uid;

    if (name != NULL)
        aout_DeviceReport(_aout, name);
#else
    (void) name;
#endif
}

- (void)setMute:(BOOL)muted
{
    _renderer.muted = muted;
    aout_MuteReport(_aout, muted);
}

- (void)setVolume:(float)volume
{
    _renderer.volume = volume * volume * volume;
    aout_VolumeReport(_aout, volume);
}

+ (vlc_tick_t)CMTimeTotick:(CMTime) timestamp
{
    CMTime scaled = CMTimeConvertScale(
            timestamp, CLOCK_FREQ,
            kCMTimeRoundingMethod_Default);

    return scaled.value;
}

- (void)flush
{
    if (_ptsSamples >= 0)
        [self stopSyncRenderer];

    _ptsSamples = -1;
    _dateReached = NO;
    _firstPts = VLC_TICK_INVALID;
    _lastDate = VLC_TICK_INVALID;
}

- (void)pause:(BOOL)pause date:(vlc_tick_t)date
{
    (void) date;

    if (_ptsSamples >= 0)
        _sync.rate = pause ? 0.0f : 1.0f;
}

- (void)whenTimeObserved:(CMTime) time
{
    assert(_firstPts != VLC_TICK_INVALID);

    if (time.value == 0)
        return;
    vlc_tick_t system_now = vlc_tick_now();
    vlc_tick_t pos_ticks = [VLCAVSample CMTimeTotick:time] + _firstPts;

    aout_TimingReport(_aout, system_now, pos_ticks);
}

- (void)startNow:(vlc_tick_t)delta
{
    assert(!_dateReached);

    _dateReached = YES;
    CMTime time = CMTimeMake(0, _sampleRate);
    [_sync setRate:1.0f time:time];

    const CMTime interval = CMTimeMake(CLOCK_FREQ, CLOCK_FREQ);
    __weak typeof(self) weakSelf = self;
    _observer = [_sync addPeriodicTimeObserverForInterval:interval
                                                    queue:_timeQueue
                                               usingBlock:^ (CMTime time){
        [weakSelf whenTimeObserved:time];
    }];
}

- (void)whenDataReady
{
    vlc_mutex_lock(&_bufferLock);

    while (_renderer.readyForMoreMediaData || !_dateReached)
    {
        if (!_dateReached && !_stopped)
        {
            /* Start playback at the requested date */

            CMTime writtenTime = CMTimeMake(_ptsSamples, _sampleRate);
            vlc_tick_t writtenTicks = [VLCAVSample CMTimeTotick:writtenTime];
            vlc_tick_t now = vlc_tick_now();
            vlc_tick_t deadline = _lastDate - writtenTicks;
            vlc_tick_t delta = deadline - now;

            if (delta <= 0)
            {
                msg_Dbg(_aout, "starting late (%"PRId64" us)", delta);
                [self startNow:delta];
            }
            else
            {
                msg_Dbg(_aout, "deferring start (%"PRId64" us)", delta);

                int timeout = 0;
                /* Wait for the start date if there are no buffers to enqueue */
                while (!_stopped && _outChain == NULL && timeout == 0)
                {
                    timeout = vlc_cond_timedwait(&_bufferWait, &_bufferLock,
                                                 deadline);
                    deadline = _lastDate - writtenTicks;
                }

                if (timeout != 0 && !_stopped)
                {
                    msg_Dbg(_aout, "started");
                    [self startNow:0];
                }
            }
        }

        while (!_stopped && _outChain == NULL)
            vlc_cond_wait(&_bufferWait, &_bufferLock);

        if (_stopped)
        {
            vlc_mutex_unlock(&_bufferLock);
            return;
        }

        block_t *block = _outChain;
        _outChain = _outChain->p_next;
        if (_outChain == NULL)
            _outChainLast = &_outChain;

        if (_chansToReorder != 0)
            aout_ChannelReorder(block->p_buffer, block->i_buffer,
                                _chansToReorder, _chanTable, VLC_CODEC_FL32);

        const unsigned samples = _encoded
        ? (block->i_nb_samples ? block->i_nb_samples : _encodedFramesPerPacket)
        : 0;

        CMSampleBufferRef buffer = _encoded
            ? [self wrapEncodedBuffer:&block]
            : [self wrapBuffer:&block];
        if (buffer == nil)
        {
            vlc_mutex_unlock(&_bufferLock);
            return;
        }

        if (_encoded)
            _ptsSamples += samples;
        else
            _ptsSamples += CMSampleBufferGetNumSamples(buffer);

        [_renderer enqueueSampleBuffer:buffer];

        CFRelease(buffer);
    }

    vlc_mutex_unlock(&_bufferLock);
}

- (void)play:(block_t *)block date:(vlc_tick_t)date
{
    if (_encoded && _fmtDesc == NULL)
    {
        if (![self prepareEncoded:block])
        {
            if (_encodedWaiting)
            {
                /* A bare AC-3 core carries no E-AC-3 frames yet; drop it and
                 * keep the timeline at the next E-AC-3 access unit. */
                block_Release(block);
                return;
            }

            msg_Err(_aout, "cannot start compressed E-AC-3 output");
            block_Release(block);
            aout_RestartRequest(_aout, true);
            return;
        }
    }

    vlc_mutex_lock(&_bufferLock);

    if (_ptsSamples == -1)
    {
        _stopped = NO;
        _firstPts = block->i_pts;
        _ptsSamples = 0;

        __weak typeof(self) weakSelf = self;
        [_renderer requestMediaDataWhenReadyOnQueue:_dataQueue usingBlock:^{
            [weakSelf whenDataReady];
        }];
    }
    _lastDate = date;

    block_ChainLastAppend(&_outChainLast, block);

    vlc_cond_signal(&_bufferWait);
    vlc_mutex_unlock(&_bufferLock);

    if (_renderer.status == AVQueuedSampleBufferRenderingStatusFailed)
    {
        msg_Err(_aout, "AVQueuedSampleBufferRenderingStatusFailed, restarting");
        aout_RestartRequest(_aout, _encoded);
    }
}

- (void)stopSyncRenderer
{
    vlc_mutex_lock(&_bufferLock);
    _sync.rate = 0.0f;

    [_renderer stopRequestingMediaData];
    [_renderer flush];

    if (_dateReached)
        [_sync removeTimeObserver:_observer];

    _stopped = YES;

    block_ChainRelease(_outChain);
    _outChain = NULL;
    _outChainLast = &_outChain;

    vlc_cond_signal(&_bufferWait);
    vlc_mutex_unlock(&_bufferLock);

    /* From the doc: "Call dispatch_sync after removeTimeObserver: to wait for
     * any in-flight blocks to finish executing." */
    dispatch_sync(_timeQueue, ^{});

    /* Not in any doc:, stopRequestingMediaData() and flush() won't wait for
     * any blocks to finish executing, so wait here. */
     dispatch_sync(_dataQueue, ^{});
}

- (void)stop
{
    NSNotificationCenter *notifCenter = [NSNotificationCenter defaultCenter];

    [self stopDeviceListener];

    if (_ptsSamples >= 0)
        [self stopSyncRenderer];

    if (_renderer != nil)
    {
        [_sync removeRenderer:_renderer atTime:kCMTimeInvalid completionHandler:nil];
        _renderer = nil;
        _sync = nil;
    }

#ifdef HAS_AVAUDIOSESSION
    avas_SetActive(_aout, [AVAudioSession sharedInstance], false,
                   AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation);
#endif

    if (_fmtDesc != NULL)
    {
        CFRelease(_fmtDesc);
        _fmtDesc = NULL;
    }

    _encoded = NO;
    [notifCenter removeObserver:self];
}

- (void)flushedAutomatically:(NSNotification *)notification
{
    msg_Warn(_aout, "flushedAutomatically");
    aout_RestartRequest(_aout, false);
}

- (void)outputConfigurationChanged:(NSNotification *)notification
{
    msg_Warn(_aout, "outputConfigurationChanged");
    aout_RestartRequest(_aout, false);
}

- (BOOL)prepareEncoded:(block_t *)block
{
    if (_fmtDesc != NULL)
        return YES;

    if (block == NULL || block->p_buffer == NULL || block->i_buffer < 7)
        return NO;

    eac3_info_t info;
    bool have_independent = false;
    bool have_eac3 = false;
    unsigned num_dep_sub = 0;
    uint16_t chan_loc = 0;
    size_t offset = 0;

    while (offset + 7 <= block->i_buffer)
    {
        eac3_info_t frame;
        if (!eac3_ParseFrame(block->p_buffer + offset,
                             block->i_buffer - offset, &frame))
            break;
        if (frame.frame_size == 0
         || offset + frame.frame_size > block->i_buffer)
            break;

        if (frame.is_ac3)
        {
            /* AC-3 core: the independent substream of this E-AC-3 access
             * unit (the packetizer hands the whole access unit over). */
            if (!have_independent)
            {
                info = frame;
                have_independent = true;
            }
        }
        else
        {
            have_eac3 = true;

            if (!have_independent || (info.is_ac3 && frame.strmtyp == 0))
            {
                info = frame;
                have_independent = true;
            }
            else if (frame.strmtyp == 1)
            {
                ++num_dep_sub;
                if (frame.has_chanmap)
                {
                    /* The 16-bit channel map is MSB-first; the dec3 chan_loc
                     * is the compact 9-bit map used by Apple's parser. */
                    for (unsigned i = 0; i < 8; ++i)
                        if ((frame.chan_loc >> (10 - i)) & 1)
                            chan_loc |= (uint16_t) (1u << i);
                    if ((frame.chan_loc >> 1) & 1)
                        chan_loc |= (uint16_t) (1u << 8);
                }
                else
                    chan_loc |= (uint16_t) frame.acmod;
            }

            if (frame.carries_joc)
            {
                info.carries_joc = true;
                info.complexity_index = frame.complexity_index;
            }
        }

        offset += frame.frame_size;
    }

    if (!have_independent || !have_eac3)
    {
        if (!have_eac3)
            _encodedWaiting = YES; /* an AC-3 core only; wait for E-AC-3 */
        return NO;
    }

    _encodedWaiting = NO;

    info.num_dep_sub = num_dep_sub;
    info.chan_loc = chan_loc;
    if (num_dep_sub > 0)
        info.channels = 8;

    if (info.rate == 0 || info.frames_per_packet == 0
     || info.channels < 1 || info.channels > 8)
        return NO;

    uint8_t dec3[64];
    const size_t dec3_size = eac3_BuildDec3(&info, 0,
                                            dec3, sizeof(dec3));
    if (dec3_size == 0)
        return NO;

    AudioStreamBasicDescription desc = {
        .mSampleRate = info.rate,
        .mFormatID = kAudioFormatEnhancedAC3,
        .mFormatFlags = 0,
        .mChannelsPerFrame = info.channels,
        .mFramesPerPacket = info.frames_per_packet,
        .mBytesPerFrame = 0,
        .mBytesPerPacket = 0,
        .mBitsPerChannel = 0,
    };

    /* The dec3 cookie carries the channel layout Apple uses. For the common
     * 5.1 and 7.1 cases a standard tag also keeps the spatial-audio path
     * available; other layouts get channel descriptions in AC-3 order. */
    AudioChannelLayout tagLayout = {
        .mChannelLayoutTag = kAudioChannelLayoutTag_UseChannelDescriptions,
        .mNumberChannelDescriptions = 0,
    };
    AudioChannelLayout *layout = &tagLayout;
    size_t layout_size = sizeof(*layout);
    AudioChannelLayout *layoutBuf = NULL;

    if (info.channels == 6)
        tagLayout.mChannelLayoutTag = kAudioChannelLayoutTag_MPEG_5_1_C;
    else
    {
        static const AudioChannelLabel ac3Labels[8][5] = {
            { kAudioChannelLabel_Left, kAudioChannelLabel_Right },
            { kAudioChannelLabel_Center },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Right },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_CenterSurround },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right, kAudioChannelLabel_CenterSurround },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround },
            { kAudioChannelLabel_Left, kAudioChannelLabel_Center, kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround, kAudioChannelLabel_RightSurround },
        };
        static const unsigned ac3Channels[8] = { 2, 1, 2, 3, 3, 4, 4, 5 };
        /* Apple's E-AC-3 decoder emits 7.1 in this order, which is not the
         * order implied by kAudioChannelLayoutTag_MPEG_7_1_C. */
        static const AudioChannelLabel eac3_71_labels[8] = {
            kAudioChannelLabel_Left, kAudioChannelLabel_Center,
            kAudioChannelLabel_Right, kAudioChannelLabel_LeftSurround,
            kAudioChannelLabel_RightSurround, kAudioChannelLabel_LFEScreen,
            kAudioChannelLabel_RearSurroundLeft,
            kAudioChannelLabel_RearSurroundRight,
        };

        layout_size = offsetof(AudioChannelLayout, mChannelDescriptions)
                    + info.channels * sizeof(AudioChannelDescription);
        layoutBuf = calloc(1, layout_size);
        if (layoutBuf == NULL)
            return NO;

        layoutBuf->mChannelLayoutTag =
            kAudioChannelLayoutTag_UseChannelDescriptions;
        layoutBuf->mNumberChannelDescriptions = info.channels;

        unsigned n = 0;
        if (info.channels == 8)
        {
            for (unsigned i = 0; i < 8; ++i)
                layoutBuf->mChannelDescriptions[n++].mChannelLabel =
                    eac3_71_labels[i];
        }
        else
        {
            for (unsigned i = 0; i < ac3Channels[info.acmod]; ++i)
                layoutBuf->mChannelDescriptions[n++].mChannelLabel =
                    ac3Labels[info.acmod][i];
            if (info.lfeon)
                layoutBuf->mChannelDescriptions[n++].mChannelLabel =
                    kAudioChannelLabel_LFEScreen;
        }

        if (n != info.channels)
        {
            free(layoutBuf);
            return NO;
        }
        layout = layoutBuf;
    }

    OSStatus status = CMAudioFormatDescriptionCreate(
        kCFAllocatorDefault, &desc, layout_size, layout,
        dec3_size, dec3, NULL, &_fmtDesc);
    free(layoutBuf);
    if (status != noErr)
    {
        msg_Warn(_aout, "CMAudioFormatDescriptionRef creation failure %li",
                 (long) status);
        return NO;
    }

    _sampleRate = info.rate;
    _encodedFramesPerPacket = info.frames_per_packet;
    _bytesPerFrame = 0;

    const unsigned bitrate =
        8 * info.frame_size * info.rate / info.frames_per_packet;

    msg_Dbg(_aout, "E-AC-3 %s: %u Hz, %u ch, %u samples/packet, %u kbit/s, "
            "dec3 %zu bytes", info.carries_joc ? "JOC/Atmos" : "stream",
            info.rate, info.channels, info.frames_per_packet,
            bitrate / 1000, dec3_size);

    return [self createRenderer];
}

- (BOOL)createRenderer
{
    _renderer = [[AVSampleBufferAudioRenderer alloc] init];
    if (_renderer == nil)
        return NO;

#if TARGET_OS_OSX
    ReportDevices(_aout);
    if (_deviceUID != nil)
        _renderer.audioOutputDeviceUniqueID = _deviceUID;
    else
        aout_DeviceReport(_aout, "0");

    AudioObjectPropertyAddress devices = {
        .mSelector = kAudioHardwarePropertyDevices,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    if (AudioObjectAddPropertyListener(kAudioObjectSystemObject, &devices,
                                       DeviceListChanged,
                                       (__bridge void *) self) == noErr)
        _listeningDevices = YES;

    AudioObjectPropertyAddress defdev = {
        .mSelector = kAudioHardwarePropertyDefaultOutputDevice,
        .mScope = kAudioObjectPropertyScopeGlobal,
        .mElement = kAudioObjectPropertyElementMain,
    };
    AudioObjectAddPropertyListener(kAudioObjectSystemObject, &defdev,
                                   DefaultDeviceChanged,
                                   (__bridge void *) self);
#endif

#if !TARGET_OS_WATCH
    /* Apple TV and QuickTime spatialise mono, stereo and multichannel video
     * (the AVPlayerItem default for video content); AVSampleBufferAudioRenderer
     * alone defaults to multichannel only. The system setting still decides
     * whether spatial audio is used. */
    if (@available(macOS 12.0, iOS 15.0, tvOS 15.0, *))
        _renderer.allowedAudioSpatializationFormats =
            AVAudioSpatializationFormatMonoStereoAndMultichannel;
#endif

    _sync = [[AVSampleBufferRenderSynchronizer alloc] init];
    if (_sync == nil)
    {
        _renderer = nil;
        return NO;
    }

#if (TARGET_OS_OSX   && defined(__MAC_11_3)     && MAC_OS_X_VERSION_MAX_ALLOWED    >= __MAC_11_3) || \
    (TARGET_OS_IOS   && defined(__IPHONE_14_5)  && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_14_5) || \
    (TARGET_OS_TV    && defined(__TVOS_14_5)     && __TV_OS_VERSION_MAX_ALLOWED     >= __TVOS_14_5) || \
    (TARGET_OS_WATCH && defined(__WATCHOS_7_4)   && __WATCH_OS_VERSION_MAX_ALLOWED  >= __WATCHOS_7_4)
    if (@available(macOS 11.3, iOS 14.5, tvOS 14.5, watchOS 7.4, *))
        _sync.delaysRateChangeUntilHasSufficientMediaData = NO;
#endif
    [_sync addRenderer:_renderer];

    _stopped = NO;
    _dateReached = NO;

    _ptsSamples = -1;
    _firstPts = VLC_TICK_INVALID;
    _lastDate = VLC_TICK_INVALID;

    NSNotificationCenter *notifCenter = [NSNotificationCenter defaultCenter];
    [notifCenter addObserver:self
                    selector:@selector(flushedAutomatically:)
                        name:AVSampleBufferAudioRendererWasFlushedAutomaticallyNotification
                      object:nil];
#if (TARGET_OS_OSX   && defined(__MAC_12_0)    && MAC_OS_X_VERSION_MAX_ALLOWED    >= __MAC_12_0) || \
    (TARGET_OS_IOS   && defined(__IPHONE_15_0) && __IPHONE_OS_VERSION_MAX_ALLOWED >= __IPHONE_15_0) || \
    (TARGET_OS_TV    && defined(__TVOS_15_0)   && __TV_OS_VERSION_MAX_ALLOWED     >= __TVOS_15_0) || \
    (TARGET_OS_WATCH && defined(__WATCHOS_8_0) && __WATCH_OS_VERSION_MAX_ALLOWED  >= __WATCHOS_8_0)
    if (@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *))
    {
        [notifCenter addObserver:self
                        selector:@selector(outputConfigurationChanged:)
                            name:AVSampleBufferAudioRendererOutputConfigurationDidChangeNotification
                          object:nil];
    }
#endif

    return YES;
}

- (BOOL)start:(audio_sample_format_t *)fmt
{
#if TARGET_OS_OSX
    if (fmt->i_format == VLC_CODEC_EAC3)
    {
        /* A/B switch: disable compressed passthrough so the same stream is
         * decoded by avcodec and spatialised as PCM instead. */
        if (!var_InheritBool(_aout, "atmos-passthrough"))
        {
            msg_Dbg(_aout, "Atmos passthrough disabled by preference; "
                    "using decoded PCM");
            return NO;
        }

        /* Some demuxers (e.g. MP4/M4A) do not report the channel count for
         * E-AC-3; the real count (and JOC flag) come from the first packet's
         * dec3 parsing below. */
        if (fmt->i_rate == 0
         || (fmt->i_channels != 0 && (fmt->i_channels < 2 || fmt->i_channels > 8)))
            return NO;

        _encoded = YES;
        _encodedWaiting = NO;
        _encodedFramesPerPacket = 0;
        _sampleRate = fmt->i_rate;
        _bytesPerFrame = 0;
        _chansToReorder = 0;
        _ptsSamples = -1;
        _firstPts = VLC_TICK_INVALID;
        _lastDate = VLC_TICK_INVALID;
        _stopped = NO;
        _dateReached = NO;

        /* Filters run on linear PCM; a compressed stream cannot go through
         * them. Tell the user when a filter they enabled will not apply. */
        char *filters = var_InheritString(_aout, "audio-filter");
        if (filters != NULL)
        {
            if (strstr(filters, "maclc_dialogue") != NULL)
                msg_Warn(_aout, "Voice Boost has no effect on compressed "
                         "E-AC-3 (Atmos) output");
            free(filters);
        }

        /* The renderer (and the dec3 cookie) are built from the first packet,
         * because that is where the JOC signal lives. */
        return YES;
    }
#endif

    if (aout_BitsPerSample(fmt->i_format) == 0)
        return NO; /* Can handle PT */

    _encoded = NO;
    _encodedFramesPerPacket = 0;

    fmt->i_format = VLC_CODEC_FL32;
    _chansToReorder = 0;

    /* That filter renders the mix to stereo, which keeps the system from
     * spatialising the stream: the two paths cannot be used together. */
    char *filters = var_InheritString(_aout, "audio-filter");
    if (filters != NULL)
    {
        if (strstr(filters, "spatializer") != NULL)
            msg_Warn(_aout, "the spatializer filter disables Apple spatial "
                     "audio; turn off Headphone Surround Spatializer");
        free(filters);
    }

#ifdef HAS_AVAUDIOSESSION
    AVAudioSession *instance = [AVAudioSession sharedInstance];
    if (avas_SetActive(_aout, instance, true, 0) != VLC_SUCCESS)
        return NO;
    avas_PrepareFormat(_aout, instance, fmt, true);

    enum port_type port_type;
    if (avas_GetPortType(_aout, instance, &port_type) == VLC_SUCCESS)
    {
        msg_Dbg(_aout, "Output on %s, channel count: %u",
                port_type == PORT_TYPE_HDMI ? "HDMI" :
                port_type == PORT_TYPE_USB ? "USB" :
                port_type == PORT_TYPE_HEADPHONES ? "Headphones" : "Default",
                aout_FormatNbChannels(fmt));

        _aout->current_sink_info.headphones = port_type == PORT_TYPE_HEADPHONES;
    }
#endif

    AudioChannelLayout *inlayout_buf = NULL;
    size_t inlayout_size = 0;
    uint32_t chan_order[AOUT_CHAN_MAX];
    int err = channel_layout_MapSpatialFromVLC(_aout, fmt, &inlayout_buf,
                                               &inlayout_size, chan_order);
    if (err != VLC_SUCCESS)
        goto error_avas;

    if (fmt->channel_type == AUDIO_CHANNEL_TYPE_BITMAP)
    {
        _chansToReorder = aout_CheckChannelReorder(NULL, chan_order,
                                                   fmt->i_physical_channels,
                                                   _chanTable);
        if (_chansToReorder != 0)
            msg_Dbg(_aout, "reordering %u channel(s) for the CoreAudio layout",
                    _chansToReorder);
    }

    unsigned nb_channels = aout_FormatNbChannels(fmt);

    AudioStreamBasicDescription desc = {
        .mSampleRate = fmt->i_rate,
        .mFormatID = kAudioFormatLinearPCM,
        .mFormatFlags = kAudioFormatFlagsNativeFloatPacked,
        .mChannelsPerFrame = nb_channels,
        .mFramesPerPacket = 1,
        .mBitsPerChannel = 32,
    };

    desc.mBytesPerFrame = desc.mBitsPerChannel * desc.mChannelsPerFrame / 8;
    desc.mBytesPerPacket = desc.mBytesPerFrame * desc.mFramesPerPacket;

    OSStatus status =
        CMAudioFormatDescriptionCreate(kCFAllocatorDefault,
                                       &desc,
                                       inlayout_size,
                                       inlayout_buf,
                                       0,
                                       nil,
                                       nil,
                                       &_fmtDesc);
    free(inlayout_buf);
    if (status != noErr)
    {
        msg_Warn(_aout, "CMAudioFormatDescriptionRef creation failure %li", (long)status);
        goto error_avas;
    }

    const AudioChannelLayout *layout =
        CMAudioFormatDescriptionGetChannelLayout(_fmtDesc, NULL);
    msg_Dbg(_aout, "format description layout tag 0x%08x",
            layout != NULL ? (unsigned) layout->mChannelLayoutTag : 0);

    _sampleRate = fmt->i_rate;
    _bytesPerFrame = desc.mBytesPerFrame;

    if (![self createRenderer])
        goto error;

    return YES;
error:
    if (_fmtDesc != NULL)
    {
        CFRelease(_fmtDesc);
        _fmtDesc = NULL;
    }
error_avas:
#ifdef HAS_AVAUDIOSESSION
    avas_SetActive(_aout, instance, false,
                   AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation);
#endif
    return NO;
}

@end

static int API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
DeviceSelect(audio_output_t *aout, const char *name)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys selectDevice:name];

    return VLC_SUCCESS;
}

static int API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
MuteSet(audio_output_t *aout, bool mute)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys setMute:mute];

    return VLC_SUCCESS;
}

static int API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
VolumeSet(audio_output_t *aout, float volume)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys setVolume:volume];

    return VLC_SUCCESS;
}

static void API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
Flush(audio_output_t *aout)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys flush];
}

static void API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
Pause(audio_output_t *aout, bool pause, vlc_tick_t date)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys pause:pause date:date];
}

static void API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
Play(audio_output_t *aout, block_t *block, vlc_tick_t date)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys play:block date:date];
}

static void API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
Stop(audio_output_t *aout)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    [sys stop];
}

static int API_AVAILABLE(macos(MIN_MACOS), ios(MIN_IOS), tvos(MIN_TVOS), watchos(MIN_WATCHOS) VISIONOS_API_AVAILABLE)
Start(audio_output_t *aout, audio_sample_format_t *restrict fmt)
{
    VLCAVSample *sys = (__bridge VLCAVSample*)aout->sys;

    return [sys start:fmt] ? VLC_SUCCESS : VLC_EGENERIC;
}

static void
Close(vlc_object_t *obj)
{
    if (@available(macOS MIN_MACOS, iOS MIN_IOS, tvOS MIN_TVOS, watchOS MIN_WATCHOS, *))
    {
        audio_output_t *aout = (audio_output_t *)obj;
        /* Transfer ownership back from VLC to ARC so that it can be released. */
        VLCAVSample *sys = (__bridge_transfer VLCAVSample*)aout->sys;
        (void) sys;
    }
}

static int
Open(vlc_object_t *obj)
{
    audio_output_t *aout = (audio_output_t *)obj;

    if (@available(macOS MIN_MACOS, iOS MIN_IOS, tvOS MIN_TVOS, watchOS MIN_WATCHOS, *))
    {
        aout->sys = (__bridge_retained void*) [[VLCAVSample alloc] init:aout];
        if (aout->sys == nil)
            return VLC_EGENERIC;

#if TARGET_OS_OSX
        /* Register Apple's Atmos decoder here, at output creation, rather
         * than in start()/play() so the one-shot priming wait never delays
         * the playback start path. Registration is a side effect of creating
         * an AVPlayer item with an E-AC-3 JOC stream; observed to work on
         * macOS 27.2 (26B123) with AirPods 3. No documented API exists. */
        atmos_prime_Begin();
#endif

        aout->start = Start;
        aout->stop = Stop;
        aout->play = Play;
        aout->pause = Pause;
        aout->flush = Flush;
        aout->volume_set = VolumeSet;
        aout->mute_set = MuteSet;
        aout->device_select = DeviceSelect;

        return VLC_SUCCESS;
    }
    return VLC_EGENERIC;
}

vlc_module_begin ()
    set_shortname("avsample")
    set_description(N_("AVSampleBufferAudioRenderer output"))
    /* Keep AUHAL (101) the default output. Users opt in to this path with
     * --aout=avsamplebuffer until it has been tested across all devices. */
    set_capability("audio output", 100)
    set_subcategory(SUBCAT_AUDIO_AOUT)
    set_callbacks(Open, Close)
    add_bool("atmos-passthrough", true, ATS_PASSTHROUGH_TEXT,
             ATS_PASSTHROUGH_LONGTEXT)
vlc_module_end ()
