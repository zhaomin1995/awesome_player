/// Direct FFmpeg decode engine with separate demux and video decode threads.
/// The demux thread reads packets and decodes audio inline (fast).
/// Video packets are dispatched to a separate decode thread so video decode
/// never blocks audio, matching VLC's architecture.
#import "FFmpegDecoder.h"
#import <AVFoundation/AVFoundation.h>
#import <QuartzCore/QuartzCore.h>

#include "libavformat/avformat.h"
#include "libavcodec/avcodec.h"
#include "libavutil/imgutils.h"
#include "libavutil/hwcontext.h"
#include "libswresample/swresample.h"
#include "libswscale/swscale.h"
#include <stdatomic.h>

static void seekLog(NSString *msg) {
    NSString *line = [NSString stringWithFormat:@"[%.3f] %@\n", CACurrentMediaTime(), msg];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath:@"/tmp/seek_debug.log"];
    if (fh) { [fh seekToEndOfFile]; [fh writeData:[line dataUsingEncoding:NSUTF8StringEncoding]]; [fh closeFile]; }
    else { [line writeToFile:@"/tmp/seek_debug.log" atomically:NO encoding:NSUTF8StringEncoding error:nil]; }
}

@implementation FFmpegDecoder {
    AVFormatContext *_formatCtx;
    AVCodecContext *_videoCodecCtx;
    AVCodecContext *_audioCodecCtx;
    SwrContext *_swrCtx;

    int _videoStreamIndex;
    int _audioStreamIndex;

    AVFrame *_audioFrame;
    AVPacket *_packet;

    dispatch_queue_t _demuxQueue;
    dispatch_queue_t _videoDecodeQueue;
    BOOL _playing;
    BOOL _closed;
    double _currentPts;
    double _audioClock;
    atomic_bool _atomicSeeking;
    atomic_bool _atomicNeedsFlush;
    double _seekTarget;
}


static enum AVPixelFormat get_hw_format(AVCodecContext *ctx, const enum AVPixelFormat *pix_fmts) {
    for (const enum AVPixelFormat *p = pix_fmts; *p != AV_PIX_FMT_NONE; p++) {
        if (*p == AV_PIX_FMT_VIDEOTOOLBOX) return *p;
    }
    return pix_fmts[0];
}

- (BOOL)openFile:(NSString *)path {
    _formatCtx = NULL;
    _videoStreamIndex = -1;
    _audioStreamIndex = -1;
    _playing = NO;
    _closed = NO;
    _currentPts = 0;
    _audioClock = 0;
    atomic_store(&_atomicSeeking, false);

    if (avformat_open_input(&_formatCtx, path.UTF8String, NULL, NULL) < 0) return NO;
    if (avformat_find_stream_info(_formatCtx, NULL) < 0) {
        avformat_close_input(&_formatCtx);
        return NO;
    }

    _duration = _formatCtx->duration > 0 ? (double)_formatCtx->duration / AV_TIME_BASE : 0;
    [self.delegate decoderDidUpdateDuration:_duration];

    _videoStreamIndex = av_find_best_stream(_formatCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    _audioStreamIndex = av_find_best_stream(_formatCtx, AVMEDIA_TYPE_AUDIO, -1, -1, NULL, 0);

    if (_videoStreamIndex >= 0) [self setupVideoDecoder];
    if (_audioStreamIndex >= 0) [self setupAudioDecoder];

    _packet = av_packet_alloc();
    _audioFrame = av_frame_alloc();
    _demuxQueue = dispatch_queue_create("com.awesomeplayer.demux", DISPATCH_QUEUE_SERIAL);
    _videoDecodeQueue = dispatch_queue_create("com.awesomeplayer.videodecode", DISPATCH_QUEUE_SERIAL);

    return YES;
}

- (void)setupVideoDecoder {
    AVStream *stream = _formatCtx->streams[_videoStreamIndex];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) return;

    _videoCodecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_videoCodecCtx, stream->codecpar);

    _videoWidth = stream->codecpar->width;
    _videoHeight = stream->codecpar->height;
    _hasVideo = YES;
    _videoCodecName = [NSString stringWithUTF8String:codec->name ?: "unknown"];

    _videoCodecCtx->thread_count = 4;
    _videoCodecCtx->thread_type = FF_THREAD_FRAME | FF_THREAD_SLICE;

    if (avcodec_open2(_videoCodecCtx, codec, NULL) < 0) {
        avcodec_free_context(&_videoCodecCtx);
        _hasVideo = NO;
    }
}

- (void)setupAudioDecoder {
    AVStream *stream = _formatCtx->streams[_audioStreamIndex];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec) return;

    _audioCodecCtx = avcodec_alloc_context3(codec);
    avcodec_parameters_to_context(_audioCodecCtx, stream->codecpar);
    if (avcodec_open2(_audioCodecCtx, codec, NULL) < 0) {
        avcodec_free_context(&_audioCodecCtx);
        return;
    }

    _audioSampleRate = _audioCodecCtx->sample_rate;
    _audioChannels = _audioCodecCtx->ch_layout.nb_channels;
    _hasAudio = YES;
    _audioCodecName = [NSString stringWithUTF8String:codec->name ?: "unknown"];

    _swrCtx = swr_alloc();
    AVChannelLayout outLayout;
    av_channel_layout_default(&outLayout, 2);
    swr_alloc_set_opts2(&_swrCtx, &outLayout, AV_SAMPLE_FMT_FLT, _audioSampleRate,
                        &_audioCodecCtx->ch_layout, _audioCodecCtx->sample_fmt, _audioSampleRate, 0, NULL);
    swr_init(_swrCtx);
    _audioChannels = 2;
}

- (void)play {
    if (_playing) return;
    _playing = YES;
    dispatch_async(_demuxQueue, ^{ [self demuxLoop]; });
}

- (void)pause { _playing = NO; }

- (double)currentTime { return _currentPts; }

- (void)seekTo:(double)seconds {
    seekLog([NSString stringWithFormat:@"seekTo: %.1f", seconds]);
    _seekTarget = seconds;
    atomic_store(&_atomicSeeking, true);

    // If the demux loop has exited (EOF or paused), restart it
    if (!_playing) {
        _playing = YES;
        dispatch_async(_demuxQueue, ^{ [self demuxLoop]; });
    }
}

- (void)close {
    _closed = YES;
    _playing = NO;
    dispatch_async(_demuxQueue, ^{ [self cleanup]; });
}

- (void)cleanup {
    if (_swrCtx) { swr_free(&_swrCtx); _swrCtx = NULL; }
    if (_audioFrame) { av_frame_free(&_audioFrame); _audioFrame = NULL; }
    if (_packet) { av_packet_free(&_packet); _packet = NULL; }
    if (_videoCodecCtx) { avcodec_free_context(&_videoCodecCtx); }
    if (_audioCodecCtx) { avcodec_free_context(&_audioCodecCtx); }
    if (_formatCtx) { avformat_close_input(&_formatCtx); }
}

#pragma mark - Demux Loop (Thread 1: demux + audio decode)

- (void)demuxLoop {
    while (_playing && !_closed) {
        // Handle seek — no dispatch_sync to avoid deadlock with video thread
        if (atomic_load(&_atomicSeeking)) {
            double target = _seekTarget;
            int64_t ts = (int64_t)(target * AV_TIME_BASE);
            av_seek_frame(_formatCtx, -1, ts, AVSEEK_FLAG_BACKWARD);
            if (_audioCodecCtx) avcodec_flush_buffers(_audioCodecCtx);
            _currentPts = target;
            _audioClock = target;
            atomic_store(&_atomicNeedsFlush, true);
            atomic_store(&_atomicSeeking, false);
            seekLog(@"SEEK: done, calling decoderDidCompleteSeek");
            [self.delegate decoderDidCompleteSeek];
            continue;
        }

        int ret = av_read_frame(_formatCtx, _packet);
        if (ret < 0) {
            // EOF — notify delegate but keep loop alive for seeking
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate decoderDidFinishPlaying];
            });
            // Wait for seek or close
            while (_playing && !_closed && !atomic_load(&_atomicSeeking)) {
                usleep(50000);
            }
            if (atomic_load(&_atomicSeeking)) continue; // process the seek
            break;
        }

        if (_packet->stream_index == _videoStreamIndex) {
            // Clone packet and dispatch to video decode thread
            AVPacket *videoPkt = av_packet_clone(_packet);
            dispatch_async(_videoDecodeQueue, ^{
                [self decodeVideoPacket:videoPkt];
                av_packet_free(&videoPkt);
            });
        } else if (_packet->stream_index == _audioStreamIndex) {
            // Decode audio inline on demux thread (fast)
            [self decodeAudioPacket];
        }

        av_packet_unref(_packet);
    }
}

#pragma mark - Video Decode (Thread 2)


- (void)decodeVideoPacket:(AVPacket *)pkt {
    if (!_videoCodecCtx) return;

    // Flush decoder if a seek just happened
    if (atomic_load(&_atomicNeedsFlush)) {
        avcodec_flush_buffers(_videoCodecCtx);
        atomic_store(&_atomicNeedsFlush, false);
    }

    int ret = avcodec_send_packet(_videoCodecCtx, pkt);
    if (ret < 0) return;

    AVFrame *frame = av_frame_alloc();
    while ((ret = avcodec_receive_frame(_videoCodecCtx, frame)) >= 0) {
        if (atomic_load(&_atomicSeeking)) { av_frame_unref(frame); continue; }

        double pts = 0;
        AVStream *stream = _formatCtx->streams[_videoStreamIndex];
        if (frame->best_effort_timestamp != AV_NOPTS_VALUE)
            pts = frame->best_effort_timestamp * av_q2d(stream->time_base);
        else if (frame->pts != AV_NOPTS_VALUE)
            pts = frame->pts * av_q2d(stream->time_base);

        double frameDuration = av_q2d(stream->avg_frame_rate) > 0
            ? 1.0 / av_q2d(stream->avg_frame_rate) : 1.0 / 30.0;

        _currentPts = pts;

        CVPixelBufferRef pixelBuffer = NULL;
        if (frame->format == AV_PIX_FMT_VIDEOTOOLBOX) {
            pixelBuffer = (CVPixelBufferRef)frame->data[3];
            if (pixelBuffer) CVPixelBufferRetain(pixelBuffer);
        } else {
            pixelBuffer = [self createPixelBufferFromFrame:frame];
        }

        if (pixelBuffer) {
            seekLog([NSString stringWithFormat:@"VIDEO pts=%.3f dur=%.4f", pts, frameDuration]);
            [self.delegate decoderDidDecodeVideoFrame:pixelBuffer pts:pts duration:frameDuration];
            CVPixelBufferRelease(pixelBuffer);
        }

        av_frame_unref(frame);
    }
    av_frame_free(&frame);
}

- (CVPixelBufferRef)createPixelBufferFromFrame:(AVFrame *)frame {
    int w = frame->width, h = frame->height;
    CVPixelBufferRef pb = NULL;
    NSDictionary *attrs = @{ (id)kCVPixelBufferIOSurfacePropertiesKey: @{} };
    if (CVPixelBufferCreate(NULL, w, h, kCVPixelFormatType_32BGRA, (__bridge CFDictionaryRef)attrs, &pb) != 0)
        return NULL;

    CVPixelBufferLockBaseAddress(pb, 0);
    uint8_t *dst = CVPixelBufferGetBaseAddress(pb);
    int dstStride = (int)CVPixelBufferGetBytesPerRow(pb);

    struct SwsContext *sws = sws_getContext(w, h, frame->format, w, h, AV_PIX_FMT_BGRA,
                                            SWS_BILINEAR, NULL, NULL, NULL);
    if (sws) {
        uint8_t *dstSlice[] = { dst };
        int dstLine[] = { dstStride };
        sws_scale(sws, (const uint8_t * const *)frame->data, frame->linesize, 0, h, dstSlice, dstLine);
        sws_freeContext(sws);
    }
    CVPixelBufferUnlockBaseAddress(pb, 0);
    return pb;
}

#pragma mark - Audio Decode (on demux thread)

- (void)decodeAudioPacket {
    if (!_audioCodecCtx || atomic_load(&_atomicSeeking)) return;

    int ret = avcodec_send_packet(_audioCodecCtx, _packet);
    if (ret < 0) return;

    while ((ret = avcodec_receive_frame(_audioCodecCtx, _audioFrame)) >= 0) {
        if (atomic_load(&_atomicSeeking)) { av_frame_unref(_audioFrame); continue; }

        double pts = 0;
        AVStream *stream = _formatCtx->streams[_audioStreamIndex];
        if (_audioFrame->best_effort_timestamp != AV_NOPTS_VALUE)
            pts = _audioFrame->best_effort_timestamp * av_q2d(stream->time_base);
        _audioClock = pts;

        int outSamples = swr_get_out_samples(_swrCtx, _audioFrame->nb_samples);
        int bufSize = outSamples * 2 * sizeof(float);
        uint8_t *outBuf = malloc(bufSize);
        int converted = swr_convert(_swrCtx, &outBuf, outSamples,
                                    (const uint8_t **)_audioFrame->extended_data,
                                    _audioFrame->nb_samples);
        if (converted > 0) {
            int dataSize = converted * 2 * sizeof(float);
            NSData *pcm = [NSData dataWithBytesNoCopy:outBuf length:dataSize freeWhenDone:YES];
            [self.delegate decoderDidDecodeAudioSamples:pcm channels:2
                                            sampleRate:self->_audioSampleRate pts:pts];
            outBuf = NULL;
        }
        if (outBuf) free(outBuf);
        av_frame_unref(_audioFrame);
    }
}

@end
