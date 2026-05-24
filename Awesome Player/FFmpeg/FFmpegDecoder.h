#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>

NS_ASSUME_NONNULL_BEGIN

@protocol FFmpegDecoderDelegate <NSObject>
- (void)decoderDidDecodeVideoFrame:(CVPixelBufferRef)pixelBuffer
                               pts:(double)pts
                          duration:(double)duration;
- (void)decoderDidDecodeAudioSamples:(NSData *)pcmData
                            channels:(int)channels
                          sampleRate:(int)sampleRate
                                 pts:(double)pts;
- (void)decoderDidFinishPlaying;
- (void)decoderDidCompleteSeek;
- (void)decoderDidUpdateDuration:(double)duration;
@end

@interface FFmpegDecoder : NSObject

@property (nonatomic, weak, nullable) id<FFmpegDecoderDelegate> delegate;
@property (nonatomic, readonly) double duration;
@property (nonatomic, readonly) int videoWidth;
@property (nonatomic, readonly) int videoHeight;
@property (nonatomic, readonly) int audioSampleRate;
@property (nonatomic, readonly) int audioChannels;
@property (nonatomic, readonly) BOOL hasVideo;
@property (nonatomic, readonly) BOOL hasAudio;
@property (nonatomic, readonly) NSString *videoCodecName;
@property (nonatomic, readonly) NSString *audioCodecName;


- (BOOL)openFile:(NSString *)path;
- (void)play;
- (void)pause;
- (void)seekTo:(double)seconds;
- (void)close;
- (double)currentTime;

@end

NS_ASSUME_NONNULL_END
